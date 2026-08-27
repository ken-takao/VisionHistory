import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    let openScanner: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        hero
                        serviceStrip
                        recentMemories
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottom) {
                if let message = model.lastMessage {
                    Text(message)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(AppTheme.lime))
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("KIOKU")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(AppTheme.lime)
                Text("RELAY")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.paper)
            }
            Spacer()
            ZStack {
                Circle().fill(AppTheme.panelRaised).frame(width: 46, height: 46)
                Image(systemName: "brain.head.profile.fill")
                    .foregroundStyle(AppTheme.lime)
            }
        }
        .padding(.top, 12)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("目の前を、\n検索できる記憶へ。")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.paper)
                    Text("30秒の映像を端末内で間引き・特徴量化。\n最大15枚を検索できる記憶にします。")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.fog)
                }
                Spacer(minLength: 8)
                Image(systemName: "camera.metering.center.weighted")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(AppTheme.lime)
            }

            Button(action: openScanner) {
                Label(
                    "\(MemoryScanConfiguration.standard.durationSeconds)秒の記憶スキャン",
                    systemImage: "viewfinder"
                )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundStyle(AppTheme.ink)
                    .background(RoundedRectangle(cornerRadius: 16).fill(AppTheme.lime))
            }
            .buttonStyle(.plain)
        }
        .glassCard()
    }

    private var serviceStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MEMORY STACK")
                .font(.caption2.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(AppTheme.fog)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(model.serviceStatuses) { ServicePill(status: $0) }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var recentMemories: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近の記憶")
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.paper)
                Spacer()
                Text("\(model.memories.count)件")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.fog)
            }
            ForEach(model.memories.prefix(6)) { memory in
                NavigationLink(value: memory) {
                    MemoryCard(memory: memory)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationDestination(for: MemoryItem.self) { MemoryDetailView(memory: $0) }
    }
}
