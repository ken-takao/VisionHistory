import SwiftUI

struct SearchMemoriesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""

    private let suggestions = ["鍵はどこ？", "青い封筒", "白いケーブル", "昨日見た書類"]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        title
                        searchBox
                        suggestionsRow
                        resultList
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MemoryItem.self) { MemoryDetailView(memory: $0) }
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("記憶を探す")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.paper)
            Text("日本語の意味・時刻・場所から検索")
                .font(.subheadline)
                .foregroundStyle(AppTheme.fog)
        }
        .padding(.top, 8)
    }

    private var searchBox: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.lime)
            TextField("例：玄関で見た黒い鍵", text: $query)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { Task { await model.search(query) } }
            Button {
                model.lastMessage = model.secrets.hasShisa
                    ? "Shisa音声入力の接続準備ができています"
                    : "Shisa APIキーを設定すると音声検索を使えます"
            } label: {
                Image(systemName: "waveform")
                    .foregroundStyle(model.secrets.hasShisa ? AppTheme.mint : AppTheme.fog)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.lime.opacity(0.22), lineWidth: 1)
                )
        )
        .onChange(of: query) { _, newValue in
            Task {
                try? await Task.sleep(for: .milliseconds(180))
                if query == newValue { await model.search(newValue) }
            }
        }
    }

    private var suggestionsRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                        query = suggestion
                        Task { await model.search(suggestion) }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.paper)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(AppTheme.panel))
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var resultList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(query.isEmpty ? "すべての記憶" : "近い記憶")
                    .font(.headline)
                    .foregroundStyle(AppTheme.paper)
                Spacer()
                Text("\(model.searchResults.count)件")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.fog)
            }

            if model.searchResults.isEmpty {
                ContentUnavailableView(
                    "見つかりませんでした",
                    systemImage: "sparkle.magnifyingglass",
                    description: Text("色・場所・時刻を変えて試してください")
                )
                .foregroundStyle(AppTheme.fog)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                ForEach(model.searchResults) { result in
                    NavigationLink(value: result.memory) {
                        MemoryCard(memory: result.memory, score: query.isEmpty ? nil : result.score)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
