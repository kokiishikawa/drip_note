//
//  BrewLogViews.swift
//  抽出ログの一覧・詳細・記録
//

import SwiftData
import SwiftUI

/// iPad では「左に一覧・右に詳細」の2列、iPhone では一覧から詳細へ切り替わる
struct BrewLogListView: View {
    @Query(sort: \BrewLog.brewedAt, order: .reverse) private var logs: [BrewLog]
    @Environment(\.modelContext) private var context
    @State private var selection: BrewLog?

    var body: some View {
        NavigationSplitView {
            Group {
                if logs.isEmpty {
                    ContentUnavailableView {
                        Label("ログがありません", systemImage: "book.closed")
                    } description: {
                        Text("タイマーで抽出を終えると、ここに記録が残ります")
                    }
                } else {
                    List(selection: $selection) {
                        ForEach(logs) { log in
                            NavigationLink(value: log) {
                                BrewLogRow(log: log, showsRecipeName: true)
                            }
                        }
                        .onDelete { offsets in
                            for log in offsets.map({ logs[$0] }) { delete(log) }
                        }
                    }
                }
            }
            .navigationTitle("ログ")
        } detail: {
            if let selection {
                NavigationStack {
                    BrewLogDetailView(log: selection)
                }
                .id(selection.id)
            } else {
                ContentUnavailableView("ログを選んでください", systemImage: "book.closed")
            }
        }
    }

    /// 表示中のログを消すと、削除済みのデータを詳細画面が読んで落ちるため、先に選択を外す
    private func delete(_ log: BrewLog) {
        if selection == log { selection = nil }
        DispatchQueue.main.async { context.delete(log) }
    }
}

struct BrewLogRow: View {
    let log: BrewLog
    let showsRecipeName: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsRecipeName {
                Text(log.recipeName).font(.headline)
            }
            HStack {
                Text(log.brewedAt.formatted(date: .abbreviated, time: .shortened))
                Text(Fmt.mmss(log.duration))
                    .monospacedDigit()
                Spacer()
                StarsText(rating: log.rating)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !log.memo.isEmpty {
                Text(log.memo)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct BrewLogDetailView: View {
    let log: BrewLog
    @Environment(AppState.self) private var appState
    @State private var isEditing = false
    @State private var isRevisingRecipe = false

    var body: some View {
        List {
            Section("概要") {
                LabeledContent("日時", value: log.brewedAt.formatted(date: .long, time: .shortened))
                LabeledContent("抽出時間", value: Fmt.mmss(log.duration))
                LabeledContent("評価") { StarsText(rating: log.rating) }
            }

            let scores = log.sortedScores
            if !scores.isEmpty {
                Section("味") {
                    ForEach(scores) { score in
                        LabeledContent(score.attributeName) {
                            HStack(spacing: 4) {
                                ForEach(1...5, id: \.self) { value in
                                    Circle()
                                        .fill(value <= score.value ? Color.accentColor : Color.secondary.opacity(0.2))
                                        .frame(width: 10, height: 10)
                                }
                            }
                            .accessibilityLabel("\(score.value)")
                        }
                    }
                }
            }

            if !log.memo.isEmpty {
                Section("メモ") { Text(log.memo) }
            }

            if let snapshot = log.snapshot {
                Section("使ったレシピ") {
                    Text(snapshot.name).font(.headline)
                    Text(snapshot.summary).font(.caption).foregroundStyle(.secondary)
                    ForEach(snapshot.steps.indices, id: \.self) { index in
                        StepRowView(snapshot: snapshot, index: index)
                    }
                }
            }

            Section {
                if let recipe = log.recipe {
                    Button("このログを元にレシピを修正", systemImage: "slider.horizontal.3") {
                        isRevisingRecipe = true
                    }
                    Button("このレシピでもう一度淹れる", systemImage: "play.fill") {
                        appState.startBrew(recipe)
                    }
                } else if log.snapshot != nil {
                    Button("このレシピを新しく登録する", systemImage: "plus") {
                        isRevisingRecipe = true
                    }
                }
            }
        }
        .navigationTitle(log.recipeName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("編集") { isEditing = true }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack { BrewLogEditorView(mode: .edit(log)) }
        }
        .sheet(isPresented: $isRevisingRecipe) {
            if let recipe = log.recipe {
                RecipeEditorView(recipe: recipe, referenceLog: log)
            } else {
                RecipeEditorView(recipe: nil, initialDraft: log.snapshot, referenceLog: log)
            }
        }
    }
}

/// 抽出ログの記録・編集
struct BrewLogEditorView: View {
    enum Mode {
        case new(BrewSession)
        case edit(BrewLog)
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Query(sort: \TasteAttribute.sortOrder) private var attributes: [TasteAttribute]

    @State private var rating = 0
    @State private var memo = ""
    /// 評価項目名 → 点数
    @State private var scores: [String: Int] = [:]
    @State private var loaded = false
    @State private var confirmDiscard = false

    private var recipeName: String {
        switch mode {
        case .new(let session): session.snapshot.name
        case .edit(let log): log.recipeName
        }
    }

    private var duration: Double {
        switch mode {
        case .new(let session): session.elapsed
        case .edit(let log): log.duration
        }
    }

    /// 今ある評価項目と、ログに残っている（削除済みの）項目を合わせたもの
    private var attributeNames: [String] {
        var names = attributes.map(\.name)
        if case .edit(let log) = mode {
            for score in log.sortedScores where !names.contains(score.attributeName) {
                names.append(score.attributeName)
            }
        }
        return names
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("レシピ", value: recipeName)
                LabeledContent("抽出時間", value: Fmt.mmss(duration))
            }

            Section("総合評価") {
                StarRatingView(rating: $rating, size: 34)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }

            Section {
                if attributeNames.isEmpty {
                    Text("評価項目がありません。設定から追加できます。")
                        .foregroundStyle(.secondary)
                }
                ForEach(attributeNames, id: \.self) { name in
                    ScoreSelector(name: name, value: Binding(
                        get: { scores[name] ?? 0 },
                        set: { scores[name] = $0 }
                    ))
                }
            } header: {
                Text("味")
            } footer: {
                Text("同じ点数をもう一度タップすると未評価に戻ります。")
            }

            Section("メモ") {
                TextField("味の感想、次に試したいことなど", text: $memo, axis: .vertical)
                    .lineLimit(3...10)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(isNew ? "抽出を記録" : "ログを編集")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isNew)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(isNew ? "記録しない" : "キャンセル") {
                    guard isNew else { dismiss(); return }
                    KeyboardSupport.commitEditing {
                        // 何も入力していなければ、消えて困るものがないので確認せずに閉じる
                        if hasInput { confirmDiscard = true } else { appState.closeSession() }
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { KeyboardSupport.commitEditing(then: save) }
            }
        }
        .alert("記録せずに閉じますか？", isPresented: $confirmDiscard) {
            Button("キャンセル", role: .cancel) {}
            Button("記録しない", role: .destructive) { appState.closeSession() }
        } message: {
            Text("入力した評価やメモは保存されません。")
        }
        .onAppear(perform: load)
        .onChange(of: draft) { _, newDraft in
            // 新規の記録では、入力内容をタイマー側に残す（スワイプで戻っても消えないように）
            if case .new(let session) = mode { session.logDraft = newDraft }
        }
    }

    private var draft: LogDraft {
        LogDraft(rating: rating, memo: memo, scores: scores)
    }

    /// 評価・味・メモのどれかを入力したか
    private var hasInput: Bool { draft.hasInput }

    private var isNew: Bool {
        if case .new = mode { return true }
        return false
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch mode {
        case .new(let session):
            // スワイプで戻ってから開き直したときは、前回の入力内容を復元する
            rating = session.logDraft.rating
            memo = session.logDraft.memo
            scores = session.logDraft.scores
        case .edit(let log):
            rating = log.rating
            memo = log.memo
            for score in log.sortedScores { scores[score.attributeName] = score.value }
        }
    }

    private func save() {
        let log: BrewLog
        switch mode {
        case .new(let session):
            log = BrewLog(
                brewedAt: session.startedAt ?? Date(),
                duration: session.elapsed,
                snapshot: session.snapshot,
                recipe: session.recipe
            )
            context.insert(log)
        case .edit(let existing):
            log = existing
            for score in existing.scores ?? [] { context.delete(score) }
            existing.scores = []
        }

        log.rating = rating
        log.memo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        for (order, name) in attributeNames.enumerated() {
            guard let value = scores[name], value > 0 else { continue }
            let score = TasteScore(attributeName: name, value: value, sortOrder: order)
            context.insert(score)
            score.attribute = attributes.first { $0.name == name }
            score.log = log
        }
        try? context.save()

        if isNew {
            appState.closeSession()
        } else {
            dismiss()
        }
    }
}

#Preview("一覧") {
    BrewLogListView()
        .previewEnvironment()
}

#Preview("詳細") {
    NavigationStack {
        BrewLogDetailView(log: PreviewData.log)
    }
    .previewEnvironment()
}

#Preview("記録") {
    NavigationStack {
        BrewLogEditorView(mode: .new(BrewSession(recipe: PreviewData.recipe)))
    }
    .previewEnvironment()
}
