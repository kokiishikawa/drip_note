//
//  RecipeSnapshot.swift
//  レシピの値をそのまま持つ構造体。編集中の下書き・タイマー実行・ログへの保存に使う
//

import Foundation

nonisolated enum StepKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case bloom
    case pour
    case wait
    case stir
    case finish

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bloom: "蒸らし"
        case .pour: "注湯"
        case .wait: "待機"
        case .stir: "撹拌"
        case .finish: "完了"
        }
    }

    var symbol: String {
        switch self {
        case .bloom: "cloud.fill"
        case .pour: "drop.fill"
        case .wait: "hourglass"
        case .stir: "arrow.clockwise"
        case .finish: "checkmark.circle.fill"
        }
    }

    /// お湯を注ぐステップかどうか
    var hasPour: Bool { self == .bloom || self == .pour }
}

nonisolated struct StepSnapshot: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var startSeconds: Int
    var kind: StepKind
    var pourGrams: Double
    var memo: String = ""
}

nonisolated struct RecipeSnapshot: Codable, Hashable, Sendable {
    var name: String
    var dripper: String
    var beanGrams: Double
    var waterGrams: Double
    var temperature: Double
    var grindSize: String
    var memo: String
    /// 開始時刻の順に並んでいる前提
    var steps: [StepSnapshot]

    mutating func sortSteps() {
        steps.sort { $0.startSeconds < $1.startSeconds }
    }

    /// 湯量が豆の量の何倍か。例: "15倍"（"1:15" は時間に見えるため使わない）
    var ratioText: String {
        guard beanGrams > 0 else { return "-" }
        return Fmt.number(waterGrams / beanGrams) + "倍"
    }

    /// 各ステップの注湯量の合計
    var stepsTotalWater: Double {
        steps.filter { $0.kind.hasPour }.reduce(0) { $0 + $1.pourGrams }
    }

    /// 指定したステップまでの累計湯量
    func cumulativeWater(through index: Int) -> Double {
        steps.prefix(index + 1).filter { $0.kind.hasPour }.reduce(0) { $0 + $1.pourGrams }
    }

    /// 完了ステップの時刻（なければ最後のステップの時刻）
    var totalSeconds: Int? {
        steps.first(where: { $0.kind == .finish })?.startSeconds ?? steps.last?.startSeconds
    }

    /// 表示用のステップ名。注湯は「2投目」のように番号をつける
    func title(for index: Int) -> String {
        let step = steps[index]
        switch step.kind {
        case .pour:
            let number = steps.prefix(index + 1).filter { $0.kind.hasPour }.count
            return "\(number)投目"
        default:
            return step.kind.label
        }
    }

    /// 表示用のステップ詳細。例: "70g 注ぐ（計120g）"
    func detail(for index: Int) -> String {
        let step = steps[index]
        switch step.kind {
        case .bloom, .pour:
            return "\(Fmt.grams(step.pourGrams)) 注ぐ（計\(Fmt.grams(cumulativeWater(through: index)))）"
        case .wait:
            return step.memo.isEmpty ? "待つ" : step.memo
        case .stir:
            return step.memo.isEmpty ? "かき混ぜる" : step.memo
        case .finish:
            return "抽出完了"
        }
    }

    var summary: String {
        var parts: [String] = []
        if !dripper.isEmpty { parts.append(dripper) }
        parts.append("豆\(Fmt.grams(beanGrams))")
        parts.append("湯\(Fmt.grams(waterGrams))")
        parts.append("\(Fmt.number(temperature))℃")
        if !grindSize.isEmpty { parts.append(grindSize) }
        return parts.joined(separator: " / ")
    }
}

extension RecipeSnapshot {
    /// 新規レシピの初期値
    static var newTemplate: RecipeSnapshot {
        RecipeSnapshot(
            name: "",
            dripper: "",
            beanGrams: 15,
            waterGrams: 240,
            temperature: 92,
            grindSize: "中細挽き",
            memo: "",
            steps: [
                StepSnapshot(startSeconds: 0, kind: .bloom, pourGrams: 30),
                StepSnapshot(startSeconds: 40, kind: .pour, pourGrams: 90),
                StepSnapshot(startSeconds: 80, kind: .pour, pourGrams: 120),
                StepSnapshot(startSeconds: 150, kind: .finish, pourGrams: 0),
            ]
        )
    }

    /// 初回起動時に入れるサンプル（4:6メソッド）
    static var sample46: RecipeSnapshot {
        RecipeSnapshot(
            name: "V60 4:6メソッド",
            dripper: "V60",
            beanGrams: 20,
            waterGrams: 300,
            temperature: 93,
            grindSize: "中細挽き",
            memo: "前半の2投で味（甘み・酸味）、後半の3投で濃さを調整する。",
            steps: [
                StepSnapshot(startSeconds: 0, kind: .bloom, pourGrams: 50),
                StepSnapshot(startSeconds: 45, kind: .pour, pourGrams: 70),
                StepSnapshot(startSeconds: 90, kind: .pour, pourGrams: 60),
                StepSnapshot(startSeconds: 130, kind: .pour, pourGrams: 60),
                StepSnapshot(startSeconds: 170, kind: .pour, pourGrams: 60),
                StepSnapshot(startSeconds: 210, kind: .finish, pourGrams: 0),
            ]
        )
    }
}
