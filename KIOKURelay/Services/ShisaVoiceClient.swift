@preconcurrency import AVFoundation
import Foundation

actor ShisaVoiceClient {
    private let apiKey: String
    private let session: URLSession
    private let baseURL = URL(string: "https://api.shisa.ai")!
    private var cachedVoice: TTSVoiceChoice?

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func checkConnection() async throws {
        _ = try await resolveJapaneseVoice(forceRefresh: true)
    }

    func synthesizeJapanese(text: String) async throws -> Data {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw ServiceError.malformedPayload("読み上げる文章がありません")
        }

        // Shisa TTS currently accepts at most 5,000 Unicode characters per request.
        let requestText = String(trimmedText.prefix(5_000))
        let voice = try await resolveJapaneseVoice()
        return try await synthesize(text: requestText, voice: voice)
    }

    private func synthesize(text: String, voice: TTSVoiceChoice) async throws -> Data {
        guard apiKey.hasPrefix("shsk:") else {
            throw ServiceError.notConfigured("Shisa")
        }
        var request = URLRequest(url: baseURL.appending(path: "tts"))
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            TTSRequest(voiceID: voice.id, format: voice.format, text: text, stream: false)
        )
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        guard !data.isEmpty else {
            throw ServiceError.malformedPayload("Shisaの音声データが空でした")
        }
        return data
    }

    private func resolveJapaneseVoice(forceRefresh: Bool = false) async throws -> TTSVoiceChoice {
        if !forceRefresh, let cachedVoice {
            return cachedVoice
        }
        guard apiKey.hasPrefix("shsk:") else {
            throw ServiceError.notConfigured("Shisa")
        }

        var request = URLRequest(url: baseURL.appending(path: "tts/voices"))
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)

        let catalog: TTSVoiceCatalog
        do {
            catalog = try JSONDecoder().decode(TTSVoiceCatalog.self, from: data)
        } catch {
            throw ServiceError.malformedPayload("Shisaの音声一覧を読み取れませんでした")
        }

        let candidates = catalog.voices.compactMap { voice -> TTSVoiceChoice? in
            guard UUID(uuidString: voice.id) != nil,
                  voice.language.localizedCaseInsensitiveContains("japanese"),
                  let format = voice.formats.first(where: {
                      $0.caseInsensitiveCompare("mp3") == .orderedSame
                  }) else {
                return nil
            }
            return TTSVoiceChoice(
                id: voice.id,
                format: format.lowercased(),
                isJapaneseOnly: voice.language.caseInsensitiveCompare("Japanese") == .orderedSame
            )
        }
        .sorted {
            if $0.isJapaneseOnly != $1.isJapaneseOnly {
                return $0.isJapaneseOnly
            }
            return $0.id < $1.id
        }

        guard let selected = candidates.first else {
            throw ServiceError.malformedPayload("日本語・MP3対応のShisa音声が見つかりませんでした")
        }
        cachedVoice = selected
        return selected
    }

    func transcribe(audioData: Data) async throws -> String {
        guard apiKey.hasPrefix("shsk:") else {
            throw ServiceError.notConfigured("Shisa")
        }
        var request = URLRequest(url: baseURL.appending(path: "asr/srt/audio_llm"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(ASRRequest(audio: audioData.base64EncodedString()))
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        let result: ASRResponse
        do {
            result = try JSONDecoder().decode(ASRResponse.self, from: data)
        } catch {
            throw ServiceError.malformedPayload("Shisaの文字起こし結果を読み取れませんでした")
        }
        guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.malformedPayload("Shisaの文字起こし結果が空でした")
        }
        return result.text
    }

    private func validate(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            // Do not surface a response body: it may contain submitted user content.
            let message = HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw ServiceError.http(service: "Shisa", status: http.statusCode, message: message)
        }
    }
}

private struct TTSVoiceCatalog: Decodable, Sendable {
    let voices: [TTSVoice]
}

private struct TTSVoice: Decodable, Sendable {
    let id: String
    let language: String
    let formats: [String]
}

private struct TTSVoiceChoice: Sendable {
    let id: String
    let format: String
    let isJapaneseOnly: Bool
}

private struct TTSRequest: Encodable {
    let voiceID: String
    let format: String
    let text: String
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case voiceID = "voice_id"
        case format
        case text
        case stream
    }
}

private struct ASRRequest: Encodable {
    let audio: String
}

private struct ASRResponse: Decodable, Sendable {
    let text: String
    let language: String
    let confidence: Double
}

enum SpeechPlaybackState: Equatable, Sendable {
    case idle
    case loading(UUID)
    case playing(UUID)

    var memoryID: UUID? {
        switch self {
        case .idle:
            nil
        case .loading(let id), .playing(let id):
            id
        }
    }
}

@MainActor
final class ShisaAudioPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var onPlaybackEnded: (@MainActor () -> Void)?

    func play(_ data: Data, onEnded: @escaping @MainActor () -> Void) throws {
        finishPlayback(notify: false)

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try audioSession.setActive(true)

        let nextPlayer = try AVAudioPlayer(data: data)
        nextPlayer.delegate = self
        guard nextPlayer.prepareToPlay() else {
            try? audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
            throw ServiceError.malformedPayload("Shisaの音声を準備できませんでした")
        }

        player = nextPlayer
        onPlaybackEnded = onEnded
        guard nextPlayer.play() else {
            finishPlayback(notify: false)
            throw ServiceError.malformedPayload("Shisaの音声を再生できませんでした")
        }
    }

    func stop() {
        guard player != nil else { return }
        player?.stop()
        finishPlayback(notify: true)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.finishPlayback(notify: true)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor [weak self] in
            self?.finishPlayback(notify: true)
        }
    }

    private func finishPlayback(notify: Bool) {
        player?.delegate = nil
        player = nil
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: [.notifyOthersOnDeactivation]
        )
        let completion = onPlaybackEnded
        onPlaybackEnded = nil
        if notify {
            completion?()
        }
    }
}
