//
//  RecipeEditorView.swift
//  レシピの作成・編集。下書き（RecipeSnapshot）を編集し、保存時にモデルへ反映する
//

import SwiftData
import SwiftUI

struct RecipeEditorView: View {
    /// nil のときは新規作成
    let recipe: Recipe?
    /// ログを元に修正するときに、参考として表示するログ
    var referenceLog: BrewLog?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RecipeSnapshot
    @State private var editingStep: StepSnapshot?

    init(recipe: Recipe?, initialDraft: RecipeSnapshot? = nil, referenceLog: BrewLog? = nil) {
        self.recipe = recipe
        self.referenceLog = referenceLog
        _draft = State(initialValue: initialDraft ?? recipe?.snapshot ?? .newTemplate)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let log = referenceLog {
                    Section("参考にするログ") {
                        LabeledContent("日時", value: log.brewedAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("評価") { StarsText(rating: log.rating) }
                        ForEach(log.sortedScores) { score in
                            LabeledContent(score.attributeName, value: "\(score.value)")
                        }
                        if !log.memo.isEmpty { Text(log.memo).font(.callout) }
                    }
                }

                Section("基本") {
                    FormTextField("レシピ名", text: $draft.name)
                    FormTextField("器具（例: V60、Kalita）", text: $draft.dripper)
                    NumberField(title: "豆の量", value: $draft.beanGrams, unit: "g")
                    NumberField(title: "湯量", value: $draft.waterGrams, unit: "g")
                    LabeledContent("比率", value: draft.ratioText)
                    NumberField(title: "湯温", value: $draft.temperature, unit: "℃")
                    FormTextField("挽き目（例: 中細挽き）", text: $draft.grindSize)
                }

                Section {
                    ForEach(draft.steps.indices, id: \.self) { index in
                        Button {
                            editingStep = draft.steps[index]
                        } label: {
                            StepRowView(snapshot: draft, index: index)
                        }
                        .tint(.primary)
                    }
                    .onDelete { draft.steps.remove(atOffsets: $0) }

                    Button("ステップを追加", systemImage: "plus.circle") {
                        let lastTime = draft.steps.last?.startSeconds ?? -30
                        editingStep = StepSnapshot(startSeconds: lastTime + 30, kind: .pour, pourGrams: 50)
                    }
                } header: {
                    Text("ステップ")
                } footer: {
                    stepsFooter
                }

                Section("メモ") {
                    TextField("メモ", text: $draft.memo, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(recipe == nil ? "新規レシピ" : "レシピを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { KeyboardSupport.commitEditing(then: save) }
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(item: $editingStep) { step in
                StepEditorView(
                    step: step,
                    isNew: !draft.steps.contains { $0.id == step.id },
                    onSave: { updated in
                        if let index = draft.steps.firstIndex(where: { $0.id == updated.id }) {
                            draft.steps[index] = updated
                        } else {
                            draft.steps.append(updated)
                        }
                        draft.sortSteps()
                    },
                    onDelete: {
                        draft.steps.removeAll { $0.id == step.id }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var stepsFooter: some View {
        let total = draft.stepsTotalWater
        VStack(alignment: .leading, spacing: 4) {
            Text("注湯量の合計: \(Fmt.grams(total))")
            if abs(total - draft.waterGrams) > 0.05 {
                Label("湯量（\(Fmt.grams(draft.waterGrams))）と合っていません", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if !draft.steps.contains(where: { $0.kind == .finish }) {
                Text("「完了」ステップを入れると、その時刻でタイマーが自動で終わります。")
            }
        }
    }

    private func save() {
        draft.name = draft.name.trimmingCharacters(in: .whitespaces)
        draft.sortSteps()
        if let recipe {
            recipe.apply(draft)
        } else {
            Recipe.create(from: draft, in: context)
        }
        dismiss()
    }
}

/// ステップ1つの編集
struct StepEditorView: View {
    @State var step: StepSnapshot
    let isNew: Bool
    let onSave: (StepSnapshot) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var minutes: Binding<Int> {
        Binding(
            get: { step.startSeconds / 60 },
            set: { step.startSeconds = $0 * 60 + step.startSeconds % 60 }
        )
    }

    private var seconds: Binding<Int> {
        Binding(
            get: { step.startSeconds % 60 },
            set: { step.startSeconds = (step.startSeconds / 60) * 60 + $0 }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("種類") {
                    Picker("種類", selection: $step.kind) {
                        ForEach(StepKind.allCases) { kind in
                            Label(kind.label, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("開始時刻（抽出開始からの経過時間）") {
                    HStack(spacing: 0) {
                        Picker("分", selection: minutes) {
                            ForEach(0..<30, id: \.self) { Text("\($0) 分").tag($0) }
                        }
                        Picker("秒", selection: seconds) {
                            ForEach(0..<60, id: \.self) { Text("\($0) 秒").tag($0) }
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 140)
                }

                if step.kind.hasPour {
                    Section("注湯量") {
                        NumberField(title: "注ぐ量", value: $step.pourGrams, unit: "g")
                    }
                }

                Section("メモ") {
                    TextField("例: 中心から外へ円を描くように", text: $step.memo, axis: .vertical)
                }

                if !isNew {
                    Section {
                        Button("このステップを削除", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isNew ? "ステップを追加" : "ステップを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        KeyboardSupport.commitEditing {
                            if !step.kind.hasPour { step.pourGrams = 0 }
                            onSave(step)
                            dismiss()
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}

#Preview("新規作成") {
    RecipeEditorView(recipe: nil)
        .previewEnvironment()
}

#Preview("編集") {
    RecipeEditorView(recipe: PreviewData.recipe)
        .previewEnvironment()
}

#Preview("ステップ編集") {
    StepEditorView(
        step: StepSnapshot(startSeconds: 45, kind: .pour, pourGrams: 70, memo: "中心から円を描くように"),
        isNew: false,
        onSave: { _ in },
        onDelete: {}
    )
}
