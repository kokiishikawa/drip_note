//
//  Models.swift
//  SwiftData のモデル。将来の CloudKit 同期に備え、全プロパティにデフォルト値をつけ、
//  リレーションは Optional にしている
//

import Foundation
import SwiftData

@Model
final class Recipe {
    var id: UUID = UUID()
    var name: String = ""
    var dripper: String = ""
    var beanGrams: Double = 20
    var waterGrams: Double = 300
    var temperature: Double = 92
    var grindSize: String = ""
    var memo: String = ""
    /// お気に入り。一覧の上に固定して表示する
    var isFavorite: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \RecipeStep.recipe)
    var steps: [RecipeStep]? = []

    @Relationship(deleteRule: .nullify, inverse: \BrewLog.recipe)
    var logs: [BrewLog]? = []

    init() {}

    var sortedSteps: [RecipeStep] {
        (steps ?? []).sorted { $0.startSeconds < $1.startSeconds }
    }

    var sortedLogs: [BrewLog] {
        (logs ?? []).sorted { $0.brewedAt > $1.brewedAt }
    }

    var snapshot: RecipeSnapshot {
        RecipeSnapshot(
            name: name,
            dripper: dripper,
            beanGrams: beanGrams,
            waterGrams: waterGrams,
            temperature: temperature,
            grindSize: grindSize,
            memo: memo,
            steps: sortedSteps.map {
                StepSnapshot(startSeconds: $0.startSeconds, kind: $0.kind, pourGrams: $0.pourGrams, memo: $0.memo)
            }
        )
    }

    /// 下書きの内容でレシピを上書きする。事前に context に insert しておくこと
    func apply(_ snapshot: RecipeSnapshot) {
        name = snapshot.name
        dripper = snapshot.dripper
        beanGrams = snapshot.beanGrams
        waterGrams = snapshot.waterGrams
        temperature = snapshot.temperature
        grindSize = snapshot.grindSize
        memo = snapshot.memo
        updatedAt = Date()

        for step in steps ?? [] {
            modelContext?.delete(step)
        }
        steps = []
        for s in snapshot.steps.sorted(by: { $0.startSeconds < $1.startSeconds }) {
            let step = RecipeStep(startSeconds: s.startSeconds, kind: s.kind, pourGrams: s.pourGrams, memo: s.memo)
            modelContext?.insert(step)
            step.recipe = self
        }
    }

    @discardableResult
    static func create(from snapshot: RecipeSnapshot, in context: ModelContext) -> Recipe {
        let recipe = Recipe()
        context.insert(recipe)
        recipe.apply(snapshot)
        return recipe
    }
}

@Model
final class RecipeStep {
    var startSeconds: Int = 0
    var kindRaw: String = StepKind.pour.rawValue
    var pourGrams: Double = 0
    var memo: String = ""
    var recipe: Recipe?

    init(startSeconds: Int, kind: StepKind, pourGrams: Double, memo: String) {
        self.startSeconds = startSeconds
        self.kindRaw = kind.rawValue
        self.pourGrams = pourGrams
        self.memo = memo
    }

    var kind: StepKind {
        get { StepKind(rawValue: kindRaw) ?? .pour }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class BrewLog {
    var id: UUID = UUID()
    var brewedAt: Date = Date()
    /// 実際の総抽出時間（秒）
    var duration: Double = 0
    /// 総合評価 1〜5。0 は未評価
    var rating: Int = 0
    var memo: String = ""
    /// 抽出した時点のレシピ内容（JSON）。あとでレシピを編集してもログは変わらない
    var recipeSnapshotData: Data?
    var recipe: Recipe?

    @Relationship(deleteRule: .cascade, inverse: \TasteScore.log)
    var scores: [TasteScore]? = []

    init(brewedAt: Date, duration: Double, snapshot: RecipeSnapshot, recipe: Recipe?) {
        self.brewedAt = brewedAt
        self.duration = duration
        self.recipeSnapshotData = try? JSONEncoder().encode(snapshot)
        self.recipe = recipe
    }

    var snapshot: RecipeSnapshot? {
        guard let recipeSnapshotData else { return nil }
        return try? JSONDecoder().decode(RecipeSnapshot.self, from: recipeSnapshotData)
    }

    var recipeName: String {
        snapshot?.name ?? recipe?.name ?? "（不明なレシピ）"
    }

    var sortedScores: [TasteScore] {
        (scores ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }
}

@Model
final class TasteScore {
    /// 評価項目の名前。項目が削除・改名されてもログに残るようにコピーして持つ
    var attributeName: String = ""
    /// 1〜5
    var value: Int = 0
    var sortOrder: Int = 0
    var log: BrewLog?
    var attribute: TasteAttribute?

    init(attributeName: String, value: Int, sortOrder: Int) {
        self.attributeName = attributeName
        self.value = value
        self.sortOrder = sortOrder
    }
}

/// ユーザーが自由に作れる味の評価項目
@Model
final class TasteAttribute {
    var id: UUID = UUID()
    var name: String = ""
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \TasteScore.attribute)
    var scores: [TasteScore]? = []

    init(name: String, sortOrder: Int) {
        self.name = name
        self.sortOrder = sortOrder
    }
}

enum SeedData {
    private static let key = "didSeedInitialData.v1"

    static func seedIfNeeded(_ context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        for (i, name) in ["酸味", "苦味", "甘み", "ボディ", "後味"].enumerated() {
            context.insert(TasteAttribute(name: name, sortOrder: i))
        }
        Recipe.create(from: .sample46, in: context)
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }
}
