//
//  BrewActivityAttributes.swift
//  アプリと Widget Extension の両方から使う Live Activity の定義
//

import ActivityKit
import Foundation

nonisolated struct BrewActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// 経過時間 0 にあたる時刻。`Text(_:style: .timer)` でカウントアップ表示に使う
        var timerStart: Date
        /// 一時停止中・完了時の経過時間。nil のときは進行中
        var frozenElapsed: Double?
        /// この状態を作った時刻
        var stateDate: Date
        var currentTitle: String
        var currentDetail: String
        var nextTitle: String?
        var nextDetail: String?
        /// 次のステップの開始時刻
        var nextStepDate: Date?
        var isFinished: Bool
    }

    var recipeName: String
    var summary: String
}

nonisolated enum Fmt {
    /// 秒数を "m:ss" 形式にする
    static func mmss(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// グラム数を "120g" のような文字列にする（小数は1桁まで）
    static func grams(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1))) + "g"
    }

    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
