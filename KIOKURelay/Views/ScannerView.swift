import SwiftUI

struct ScannerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = CameraCaptureService()
    @State private var isScanning = false
    @State private var progress: Double = 0
    @State private var acceptedFrames = 0
    @State private var scanTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            cameraSurface
            scanOverlay
        }
        .task { await camera.requestAndStart() }
        .onDisappear {
            scanTask?.cancel()
            camera.stop()
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue != .active {
                scanTask?.cancel()
                isScanning = false
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
                    Text(isScanning ? "場面の変化を記憶中" : "ゆっくり見渡してください")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(isScanning ? AppTheme.coral : AppTheme.mint).frame(width: 8, height: 8)
                    Text(isScanning ? "解析中" : "端末内処理")
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
                .stroke(AppTheme.lime.opacity(isScanning ? 0.9 : 0.46), lineWidth: 2)
                .overlay(alignment: .topLeading) {
                    Text(isScanning ? "\(acceptedFrames) KEYFRAMES" : "AUTO KEYFRAME")
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
                    Text("30fpsの映像から、意味のある瞬間だけを選択しています")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                } else {
                    Toggle(isOn: $model.cloudEnrichmentEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("代表フレームをAIで説明")
                                .font(.subheadline.weight(.semibold))
                            Text("有効時のみ最後の1枚をOpenAIへ送信")
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
                        Image(systemName: isScanning ? "stop.fill" : "viewfinder")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                    }
                }
                .buttonStyle(.plain)
                .disabled(camera.authorizationState != .authorized)
                .opacity(camera.authorizationState == .authorized ? 1 : 0.45)

                Text(isScanning ? "タップして停止" : "10秒スキャンを開始")
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
            scanTask?.cancel()
            isScanning = false
            return
        }

        isScanning = true
        progress = 0
        acceptedFrames = 0
        scanTask = Task {
            let sampleCount = 5
            for index in 0..<sampleCount {
                if Task.isCancelled { break }
                try? await Task.sleep(for: .seconds(index == 0 ? 0.5 : 2))
                if Task.isCancelled { break }

                progress = Double(index + 1) / Double(sampleCount)
                guard let image = camera.snapshot() else { continue }
                let isRepresentativeFrame = index == sampleCount - 1
                if await model.captureMemory(from: image, useCloud: isRepresentativeFrame) != nil {
                    acceptedFrames += 1
                }
            }
            isScanning = false
        }
    }
}
