import SwiftUI

struct ScannerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = CameraCaptureService()
    @State private var isScanning = false
    @State private var isProcessing = false
    @State private var stopRequested = false
    @State private var progress: Double = 0
    @State private var acceptedFrames = 0
    @State private var scanTask: Task<Void, Never>?

    private let scanConfiguration = MemoryScanConfiguration.standard

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            cameraSurface
            scanOverlay
        }
        .task { await camera.requestAndStart() }
        .onDisappear {
            scanTask?.cancel()
            scanTask = nil
            stopRequested = false
            isScanning = false
            isProcessing = false
            camera.stop()
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue != .active {
                scanTask?.cancel()
                scanTask = nil
                stopRequested = false
                isScanning = false
                isProcessing = false
                camera.stop()
            } else if !camera.isRunning {
                Task { await camera.requestAndStart() }
            }
        }
    }

    @ViewBuilder
    private var cameraSurface: some View {
        switch camera.authorizationState {
        case .authorized:
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
        case .denied:
            emptyState(
                icon: "camera.fill",
                title: "カメラへのアクセスが必要です",
                detail: "設定アプリからKIOKU RELAYのカメラを許可してください。"
            )
        case .unavailable:
            emptyState(
                icon: "iphone.gen3",
                title: "実機で記憶スキャン",
                detail: "シミュレータではカメラ入力を利用できません。UIと検索はそのまま確認できます。"
            )
        case .unknown:
            ProgressView().tint(AppTheme.lime)
        }
    }

    private var scanOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MEMORY SCAN")
                        .font(.caption.bold())
                        .tracking(2)
                        .foregroundStyle(AppTheme.lime)
                    Text(scanStatusTitle)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(isScanning ? AppTheme.coral : AppTheme.mint).frame(width: 8, height: 8)
                    Text(isProcessing ? "メタ情報生成" : isScanning ? "収集中" : "端末内処理")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.56)))
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)

            Spacer()

            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(AppTheme.lime.opacity(isScanning || isProcessing ? 0.9 : 0.46), lineWidth: 2)
                .overlay(alignment: .topLeading) {
                    Text(
                        isScanning || isProcessing
                            ? "\(acceptedFrames)/\(scanConfiguration.targetKeyframeCount) KEYFRAMES"
                            : "AUTO KEYFRAME"
                    )
                        .font(.caption2.monospaced().weight(.bold))
                        .foregroundStyle(AppTheme.lime)
                        .padding(10)
                }
                .padding(.horizontal, 28)
                .frame(height: 360)

            Spacer()

            VStack(spacing: 14) {
                if isScanning {
                    ProgressView(value: progress)
                        .tint(AppTheme.lime)
                    Text(
                        "30fpsの映像から\(scanConfiguration.keyframeIntervalSeconds)秒ごとに"
                            + "最大\(scanConfiguration.targetKeyframeCount)枚を記録しています"
                    )
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                } else if isProcessing {
                    ProgressView()
                        .tint(AppTheme.lime)
                    Text("全キーフレームのメタ情報をまとめて生成しています")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                } else {
                    Toggle(isOn: $model.cloudEnrichmentEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("全キーフレームをAIで説明")
                                .font(.subheadline.weight(.semibold))
                            Text(
                                "有効時は最大\(scanConfiguration.targetKeyframeCount)枚すべてを"
                                    + "OpenAIへ送信"
                            )
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                    .tint(AppTheme.lime)
                }

                Button(action: toggleScan) {
                    ZStack {
                        Circle()
                            .fill(isScanning ? AppTheme.coral : AppTheme.lime)
                            .frame(width: 76, height: 76)
                        Image(systemName: isProcessing ? "sparkles" : isScanning ? "stop.fill" : "viewfinder")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                    }
                }
                .buttonStyle(.plain)
                .disabled(
                    camera.authorizationState != .authorized
                        || isProcessing
                        || stopRequested
                )
                .opacity(camera.authorizationState == .authorized && !isProcessing ? 1 : 0.45)

                Text(scanActionTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(18)
            .background(.ultraThinMaterial)
        }
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.lime)
            Text(title).font(.title3.bold()).foregroundStyle(.white)
            Text(detail)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.fog)
                .padding(.horizontal, 36)
        }
    }

    private func toggleScan() {
        if isScanning {
            stopRequested = true
            return
        }

        guard !isProcessing else { return }
        isScanning = true
        stopRequested = false
        progress = 0
        acceptedFrames = 0
        scanTask = Task {
            let clock = ContinuousClock()
            let startedAt = clock.now
            var capturedFrames: [CapturedMemoryFrame] = []
            capturedFrames.reserveCapacity(scanConfiguration.targetKeyframeCount)

            for offset in scanConfiguration.keyframeOffsetsSeconds {
                do {
                    try await clock.sleep(
                        until: startedAt.advanced(by: .seconds(offset)),
                        tolerance: .milliseconds(80)
                    )
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                if stopRequested { break }

                progress = Double(offset) / Double(scanConfiguration.durationSeconds)
                guard let image = camera.snapshot() else { continue }
                capturedFrames.append(CapturedMemoryFrame(image: image, capturedAt: .now))
                acceptedFrames = capturedFrames.count
            }

            isScanning = false
            stopRequested = false
            guard !Task.isCancelled, !capturedFrames.isEmpty else {
                scanTask = nil
                return
            }

            isProcessing = true
            _ = await model.captureMemories(from: capturedFrames, useCloud: true)
            isProcessing = false
            scanTask = nil
        }
    }

    private var scanStatusTitle: String {
        if isProcessing { return "全キーフレームを解析中" }
        if stopRequested { return "スキャンを停止しています" }
        if isScanning { return "場面の変化を記憶中" }
        return "ゆっくり見渡してください"
    }

    private var scanActionTitle: String {
        if isProcessing { return "メタ情報を生成中" }
        if stopRequested { return "記録済みフレームを保存します" }
        if isScanning { return "タップして停止" }
        return "\(scanConfiguration.durationSeconds)秒スキャンを開始"
    }
}
