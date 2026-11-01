//
//  RecipeListView.swift
//

import SwiftData
import SwiftUI

/// iPad では「左に一覧・右に詳細」の2列、iPhone では一覧から詳細へ切り替わる
struct RecipeListView: View {
    @Query(sort: \Recipe.updatedAt, order: .reverse) private var recipes: [Recipe]
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @State private var isCreating = false
    @State private var selection: Recipe?
    @AppStorage("recipeList.favoritesOnly") private var favoritesOnly = false

    /// お気に入りを上に固定し、その中は更新日の新しい順（@Query の並び）にする
    private var displayedRecipes: [Recipe] {
        let favorites = recipes.filter(\.isFavorite)
        return favoritesOnly ? favorites : favorites + recipes.filter { !$0.isFavorite }
    }

    var body: some View {
        NavigationSplitView {
            Group {
                if recipes.isEmpty {
                    ContentUnavailableView {
                        Label("レシピがありません", systemImage: "cup.and.saucer")
                    } description: {
                        Text("右上の＋からレシピを作成しましょう")
                    }
                } else if displayedRecipes.isEmpty {
                    ContentUnavailableView {
                        Label("お気に入りがありません", systemImage: "star")
                    } description: {
                        Text("レシピの ☆ をタップすると、お気に入りに登録できます")
                    } actions: {
                        Button("すべてのレシピを表示") { favoritesOnly = false }
                    }
                } else {
                    List(selection: $selection) {
                        ForEach(displayedRecipes) { recipe in
                            NavigationLink(value: recipe) {
                                RecipeRow(
                                    recipe: recipe,
                                    onToggleFavorite: { toggleFavorite(recipe) },
                                    onStart: { appState.startBrew(recipe) }
                                )
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    toggleFavorite(recipe)
                                } label: {
                                    Label(
                                        recipe.isFavorite ? "お気に入り解除" : "お気に入り",
                                        systemImage: recipe.isFavorite ? "star.slash" : "star.fill"
                                    )
                                }
                                .tint(.orange)
                            }
                            .contextMenu {
                                Button("抽出を開始", systemImage: "play.fill") { appState.startBrew(recipe) }
                                Button(
                                    recipe.isFavorite ? "お気に入りから外す" : "お気に入りに登録",
                                    systemImage: recipe.isFavorite ? "star.slash" : "star"
                                ) { toggleFavorite(recipe) }
                                Button("複製", systemImage: "plus.square.on.square") { duplicate(recipe) }
                                Button("削除", systemImage: "trash", role: .destructive) { delete(recipe) }
                            }
                        }
                        .onDelete { offsets in
                            let targets = offsets.map { displayedRecipes[$0] }
                            for recipe in targets { delete(recipe) }
                        }
                    }
                }
            }
            .navigationTitle(favoritesOnly ? "お気に入り" : "レシピ")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if !recipes.isEmpty {
                        Button {
                            withAnimation { favoritesOnly.toggle() }
                        } label: {
                            Label(
                                favoritesOnly ? "すべて表示" : "お気に入りだけ表示",
                                systemImage: favoritesOnly ? "star.fill" : "star"
                            )
                        }
                        .tint(favoritesOnly ? .orange : nil)
                    }
                    Button("新規レシピ", systemImage: "plus") { isCreating = true }
                }
            }
            .sheet(isPresented: $isCreating) {
                RecipeEditorView(recipe: nil)
            }
        } detail: {
            if let selection {
                NavigationStack {
                    RecipeDetailView(recipe: selection, onDelete: { delete(selection) })
                }
                .id(selection.id)
            } else {
                ContentUnavailableView("レシピを選んでください", systemImage: "cup.and.saucer")
            }
        }
    }

    private func toggleFavorite(_ recipe: Recipe) {
        withAnimation {
            recipe.isFavorite.toggle()
        }
        if AppSettings.vibrationEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func duplicate(_ recipe: Recipe) {
        var copy = recipe.snapshot
        copy.name += " のコピー"
        Recipe.create(from: copy, in: context)
    }

    /// 表示中のレシピを消すと、削除済みのデータを詳細画面が読んで落ちるため、先に選択を外す
    private func delete(_ recipe: Recipe) {
        if selection == recipe { selection = nil }
        DispatchQueue.main.async { context.delete(recipe) }
    }
}

private struct RecipeRow: View {
    let recipe: Recipe
    let onToggleFavorite: () -> Void
    let onStart: () -> Void

    var body: some View {
        let snapshot = recipe.snapshot
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.name.isEmpty ? "名称未設定" : recipe.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(snapshot.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 10) {
                    // Label は幅が足りないとアイコンだけになるので、アイコンと文字を並べる
                    if let total = snapshot.totalSeconds {
                        HStack(spacing: 3) {
                            Image(systemName: "timer")
                            Text(Fmt.mmss(Double(total)))
                        }
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "list.number")
                        Text("\(snapshot.steps.count)ステップ")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                // 幅が狭くても「3:30」や「6ステップ」を途中で折り返さない
                .lineLimit(1)
                .fixedSize()
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            Button(action: onToggleFavorite) {
                Image(systemName: recipe.isFavorite ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(recipe.isFavorite ? Color.orange : Color.secondary)
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(recipe.isFavorite ? "お気に入りから外す" : "お気に入りに登録")
            Button(action: onStart) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 34))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("抽出を開始")
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RecipeListView()
        .previewEnvironment()
}
