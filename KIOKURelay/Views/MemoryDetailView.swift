import SwiftUI
import UIKit

struct MemoryDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    let memory: MemoryItem

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    image
                    Text(memory.title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(AppTheme.paper)
                    Text(memory.summary)
                        .font(.body)
                        .foregroundStyle(AppTheme.fog)
                    speechButton
                    Label(memory.place, systemImage: "mappin.and.ellipse")
                        .foregroundStyle(AppTheme.lime)
                    Text(memory.capturedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(AppTheme.fog)
                    FlowLayout(spacing: 8) {
                        ForEach(memory.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(AppTheme.panelRaised))
                        }
                    }
                }
                .padding(18)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var speechButton: some View {
        Button {
            Task { await appModel.speak(memory) }
        } label: {
            HStack(spacing: 10) {
                if case .loading(memory.id) = appModel.speechState {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: speechButtonSymbol)
                }
                Text(speechButtonTitle)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.lime)
        .foregroundStyle(AppTheme.ink)
        .disabled(!appModel.secrets.hasShisa)
    }

    private var speechButtonTitle: String {
        guard appModel.secrets.hasShisa else { return "Shisa APIキー未設定" }
        switch appModel.speechState {
        case .loading(memory.id):
            return "読み上げを準備中…"
        case .playing(memory.id):
            return "読み上げを停止"
        default:
            return "Shisaで読み上げ"
        }
    }

    private var speechButtonSymbol: String {
        if case .playing(memory.id) = appModel.speechState {
            return "stop.fill"
        }
        return appModel.secrets.hasShisa ? "speaker.wave.2.fill" : "speaker.slash.fill"
    }

    @ViewBuilder
    private var image: some View {
        if let data = memory.thumbnailJPEG, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(height: 310)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 28).fill(AppTheme.panel)
                Image(systemName: memory.symbolName)
                    .font(.system(size: 72))
                    .foregroundStyle(AppTheme.lime)
            }
            .frame(height: 260)
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width ?? 320
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}
