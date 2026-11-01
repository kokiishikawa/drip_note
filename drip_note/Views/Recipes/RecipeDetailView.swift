//
//  RecipeDetailView.swift
//

import SwiftData
import SwiftUI

struct RecipeDetailView: View {
    let recipe: Recipe
    /// 削除の処理。一覧側で選択を外してから消すために使う
    var onDelete: (() -> Void)?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var isEditing = false
    @State private var confirmDelete = false

    var body: some View {
        let snapshot = recipe.snapshot
        List {
            Section("基本") {
                if !snapshot.dripper.isEmpty { LabeledContent("器具", value: snapshot.dripper) }
                LabeledContent("豆の量", value: Fmt.grams(snapshot.beanGrams))
                LabeledContent("湯量", value: Fmt.grams(snapshot.waterGrams))
                LabeledContent("比率", value: snapshot.ratioText)
                LabeledContent("湯温", value: "\(Fmt.number(snapshot.temperature))℃")
                if !snapshot.grindSize.isEmpty { LabeledContent("挽き目", value: snapshot.grindSize) }
                if let total = snapshot.totalSeconds {
                    LabeledContent("抽出時間", value: Fmt.mmss(Double(total)))
                }
            }

            Section("ステップ") {
                if snapshot.steps.isEmpty {
                    Text("ステップがありません").foregroundStyle(.secondary)
                }
                ForEach(snapshot.steps.indices, id: \.self) { index in
                    StepRowView(snapshot: snapshot, index: index)
                }
            }

            if !snapshot.memo.isEmpty {
                Section("メモ") {
                    Text(snapshot.memo)
                }
            }

            let logs = recipe.sortedLogs
            if !logs.isEmpty {
                Section("最近のログ") {
                    ForEach(logs.prefix(5)) { log in
                        NavigationLink {
                            BrewLogDetailView(log: log)
                        } label: {
                            BrewLogRow(log: log, showsRecipeName: false)
                        }
                    }
                }
            }
        }
        .navigationTitle(recipe.name.isEmpty ? "名称未設定" : recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                appState.startBrew(recipe)
            } label: {
                Label("抽出を開始", systemImage: "play.fill")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation { recipe.isFavorite.toggle() }
                } label: {
                    Label(
                        recipe.isFavorite ? "お気に入りから外す" : "お気に入りに登録",
                        systemImage: recipe.isFavorite ? "star.fill" : "star"
                    )
                    .contentTransition(.symbolEffect(.replace))
                }
                .tint(recipe.isFavorite ? .orange : nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("編集") { isEditing = true }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("複製", systemImage: "plus.square.on.square") {
                    var copy = recipe.snapshot
                    copy.name += " のコピー"
                    Recipe.create(from: copy, in: context)
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("削除", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            RecipeEditorView(recipe: recipe)
        }
        .confirmationDialog("このレシピを削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                if let onDelete {
                    onDelete()
                } else {
                    dismiss()
                    context.delete(recipe)
                }
            }
        } message: {
            Text("ログは削除されずに残ります。")
        }
    }
}

#Preview {
    NavigationStack {
        RecipeDetailView(recipe: PreviewData.recipe)
    }
    .previewEnvironment()
}
