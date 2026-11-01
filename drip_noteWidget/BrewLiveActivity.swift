//
//  BrewLiveActivity.swift
//  ロック画面と Dynamic Island に抽出タイマーを表示する
//

import ActivityKit
import SwiftUI
import WidgetKit

@main
struct DripNoteWidgetBundle: WidgetBundle {
    var body: some Widget {
        BrewLiveActivity()
    }
}

struct BrewLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BrewActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .padding()
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(state.currentTitle, systemImage: "drop.fill")
                            .font(.headline)
                            .foregroundStyle(.brown)
                        Text(state.currentDetail)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(state: state)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    NextStepLine(state: state, isStale: context.isStale)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: state.isFinished ? "checkmark.circle.fill" : "drop.fill")
                    .foregroundStyle(state.isFinished ? .green : .brown)
            } compactTrailing: {
                ElapsedText(state: state)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "drop.fill")
                    .foregroundStyle(.brown)
            }
        }
    }
}

private struct LockScreenView: View {
    let attributes: BrewActivityAttributes
    let state: BrewActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(attributes.recipeName, systemImage: "cup.and.saucer.fill")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Spacer()
                if state.frozenElapsed != nil, !state.isFinished {
                    Text("一時停止中").font(.caption.bold()).foregroundStyle(.orange)
                }
            }
            .foregroundStyle(.white.opacity(0.8))

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.currentTitle)
                        .font(.title2.bold())
                    Text(state.currentDetail)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                Spacer()
                ElapsedText(state: state)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 130, alignment: .trailing)
            }
            .foregroundStyle(.white)

            NextStepLine(state: state, isStale: isStale)
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

/// 経過時間。進行中は OS が自動でカウントアップする
private struct ElapsedText: View {
    let state: BrewActivityAttributes.ContentState

    var body: some View {
        if let frozen = state.frozenElapsed {
            Text(Fmt.mmss(frozen))
        } else {
            Text(state.timerStart, style: .timer)
        }
    }
}

/// 次のステップと、それまでの残り時間
private struct NextStepLine: View {
    let state: BrewActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if isStale && state.frozenElapsed == nil {
            // アプリが止められて表示を更新できないとき
            Text("通知でステップを案内しています。アプリを開くと最新の状態を表示します")
                .font(.caption)
                .lineLimit(2)
        } else if let title = state.nextTitle, let nextDate = state.nextStepDate, nextDate > state.stateDate {
            HStack {
                Text("次: \(title)")
                    .font(.subheadline.bold())
                if let detail = state.nextDetail {
                    Text(detail)
                        .font(.caption)
                        .lineLimit(1)
                }
                Spacer()
                Group {
                    if state.frozenElapsed != nil {
                        Text(Fmt.mmss(nextDate.timeIntervalSince(state.stateDate)))
                    } else {
                        Text(timerInterval: state.stateDate...nextDate, countsDown: true)
                    }
                }
                .font(.headline)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 60, alignment: .trailing)
            }
        } else if state.isFinished {
            Text("おつかれさまでした").font(.caption)
        }
    }
}

// MARK: - Preview

#if DEBUG
private extension BrewActivityAttributes {
    static var preview: BrewActivityAttributes {
        BrewActivityAttributes(recipeName: "V60 4:6メソッド", summary: "V60 / 豆20g / 湯300g / 93℃")
    }
}

private extension BrewActivityAttributes.ContentState {
    static var running: Self {
        let now = Date()
        return Self(
            timerStart: now.addingTimeInterval(-52),
            frozenElapsed: nil,
            stateDate: now,
            currentTitle: "2投目",
            currentDetail: "70g 注ぐ（計120g）",
            nextTitle: "3投目",
            nextDetail: "60g 注ぐ（計180g）",
            nextStepDate: now.addingTimeInterval(38),
            isFinished: false
        )
    }

    static var paused: Self {
        var state = running
        state.frozenElapsed = 52
        return state
    }

    static var finished: Self {
        let now = Date()
        return Self(
            timerStart: now.addingTimeInterval(-210),
            frozenElapsed: 210,
            stateDate: now,
            currentTitle: "抽出完了",
            currentDetail: "おつかれさまでした",
            nextTitle: nil,
            nextDetail: nil,
            nextStepDate: nil,
            isFinished: true
        )
    }
}

#Preview("ロック画面", as: .content, using: BrewActivityAttributes.preview) {
    BrewLiveActivity()
} contentStates: {
    BrewActivityAttributes.ContentState.running
    BrewActivityAttributes.ContentState.paused
    BrewActivityAttributes.ContentState.finished
}

#Preview("Dynamic Island 展開", as: .dynamicIsland(.expanded), using: BrewActivityAttributes.preview) {
    BrewLiveActivity()
} contentStates: {
    BrewActivityAttributes.ContentState.running
}

#Preview("Dynamic Island コンパクト", as: .dynamicIsland(.compact), using: BrewActivityAttributes.preview) {
    BrewLiveActivity()
} contentStates: {
    BrewActivityAttributes.ContentState.running
}

#Preview("Dynamic Island 最小", as: .dynamicIsland(.minimal), using: BrewActivityAttributes.preview) {
    BrewLiveActivity()
} contentStates: {
    BrewActivityAttributes.ContentState.running
}
#endif
