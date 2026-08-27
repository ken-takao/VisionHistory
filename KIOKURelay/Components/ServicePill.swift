import SwiftUI

struct ServicePill: View {
    let status: ServiceStatus

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(status.kind.rawValue)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(AppTheme.paper)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Capsule().fill(AppTheme.panelRaised))
    }

    private var color: Color {
        switch status.state {
        case .local, .connected: AppTheme.mint
        case .checking: AppTheme.lime
        case .notConfigured: AppTheme.fog
        case .failed: AppTheme.coral
        }
    }
}
