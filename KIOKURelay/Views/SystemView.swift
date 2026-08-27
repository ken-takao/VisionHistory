import SwiftUI

struct SystemView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Memory Stack")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.paper)
                            Text("ローカル優先・必要な時だけクラウド")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.fog)
                        }
                        .padding(.top, 8)

                        ForEach(model.serviceStatuses) { status in
                            statusRow(status)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Label("デモ用認証情報", systemImage: "exclamationmark.shield.fill")
                                .font(.headline)
                                .foregroundStyle(AppTheme.coral)
                            Text("DebugSecrets.xcconfigはGit対象外ですが、値はデバッグアプリへ組み込まれます。デモ終了後にキーを失効し、本番ではBFFへ移してください。")
                                .font(.caption)
                                .foregroundStyle(AppTheme.fog)
                        }
                        .glassCard()

                        Button {
                            Task { await model.checkConnections() }
                        } label: {
                            Label("接続を再確認", systemImage: "arrow.clockwise")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(AppTheme.ink)
                                .background(RoundedRectangle(cornerRadius: 16).fill(AppTheme.lime))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(18)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func statusRow(_ status: ServiceStatus) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(AppTheme.panelRaised)
                    .frame(width: 48, height: 48)
                Image(systemName: icon(for: status.kind))
                    .foregroundStyle(color(for: status.state))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(status.kind.rawValue)
                    .font(.headline)
                    .foregroundStyle(AppTheme.paper)
                Text(description(for: status.state))
                    .font(.caption)
                    .foregroundStyle(AppTheme.fog)
                    .lineLimit(2)
            }
            Spacer()
            Circle().fill(color(for: status.state)).frame(width: 9, height: 9)
        }
        .glassCard(padding: 14)
    }

    private func icon(for kind: ServiceKind) -> String {
        switch kind {
        case .localAI: "apple.intelligence"
        case .qdrant: "externaldrive.fill"
        case .openAI: "sparkles"
        case .neo4j: "point.3.connected.trianglepath.dotted"
        case .shisa: "waveform"
        }
    }

    private func color(for state: ConnectionState) -> Color {
        switch state {
        case .local, .connected: AppTheme.mint
        case .checking: AppTheme.lime
        case .notConfigured: AppTheme.fog
        case .failed: AppTheme.coral
        }
    }

    private func description(for state: ConnectionState) -> String {
        switch state {
        case .local: "端末内で利用可能"
        case .notConfigured: "Debugキーが未設定"
        case .checking: "接続を確認中"
        case .connected: "認証・接続OK"
        case .failed(let message): message
        }
    }
}
