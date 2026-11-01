//
//  PreviewData.swift
//  Xcode プレビュー用のサンプルデータ。メモリ上だけに保存するので、実際のデータには影響しない
//

#if DEBUG
import SwiftData
import SwiftUI

enum PreviewData {
    static let container: ModelContainer = {
        // RootView の初回データ投入と重複しないようにする
        UserDefaults.standard.set(true, forKey: "didSeedInitialData.v1")

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Recipe.self, RecipeStep.self, BrewLog.self, TasteScore.self, TasteAttribute.self,
            configurations: config
        )
        let context = container.mainContext

        let attributes = ["酸味", "苦味", "甘み", "ボディ", "後味"].enumerated().map { index, name in
            let attribute = TasteAttribute(name: name, sortOrder: index)
            context.insert(attribute)
            return attribute
        }

        let recipe = Recipe.create(from: .sample46, in: context)
        var simple = RecipeSnapshot.newTemplate
        simple.name = "Kalita ウェーブ 3投"
        simple.dripper = "Kalita"
        Recipe.create(from: simple, in: context)

        for (offset, rating) in [4, 3].enumerated() {
            let log = BrewLog(
                brewedAt: Date().addingTimeInterval(Double(-86_400 * offset)),
                duration: 212,
                snapshot: recipe.snapshot,
                recipe: recipe
            )
            log.rating = rating
            log.memo = "甘みがしっかり。次は少し粗く挽いてみる。"
            context.insert(log)
            for (order, attribute) in attributes.enumerated() {
                let score = TasteScore(attributeName: attribute.name, value: (order + offset) % 5 + 1, sortOrder: order)
                context.insert(score)
                score.attribute = attribute
                score.log = log
            }
        }
        try? context.save()
        return container
    }()

    static var recipe: Recipe {
        let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate { $0.name == "V60 4:6メソッド" })
        return try! container.mainContext.fetch(descriptor).first!
    }

    static var log: BrewLog {
        try! container.mainContext.fetch(FetchDescriptor<BrewLog>(sortBy: [SortDescriptor(\.brewedAt, order: .reverse)])).first!
    }
}

extension View {
    /// プレビューで必要なデータと AppState を渡す
    func previewEnvironment() -> some View {
        modelContainer(PreviewData.container)
            .environment(AppState())
    }
}
#endif
