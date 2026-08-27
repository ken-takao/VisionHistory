import SwiftUI
import UIKit

struct MemoryCard: View {
    let memory: MemoryItem
    var score: Double?

    var body: some View {
        HStack(spacing: 14) {
            thumbnail
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(memory.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.paper)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let score {
                        Text("\(Int(score * 100))%")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(AppTheme.lime)
                    }
                }

                Text(memory.summary)
                    .font(.caption)
                    .foregroundStyle(AppTheme.fog)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Label(memory.place, systemImage: "mappin.and.ellipse")
                    Text("·")
                    Text(memory.capturedAt, style: .relative)
                    if memory.neo4jSynced {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .foregroundStyle(AppTheme.mint)
                    }
                }
                .font(.caption2)
                .foregroundStyle(AppTheme.fog.opacity(0.8))
            }
        }
        .glassCard(padding: 12)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = memory.thumbnailJPEG, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                LinearGradient(
                    colors: [AppTheme.panelRaised, AppTheme.lime.opacity(0.22)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: memory.symbolName)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(AppTheme.lime)
            }
        }
    }
}
