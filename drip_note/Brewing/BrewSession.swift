//
//  BrewSession.swift
//  抽出タイマーの本体
//

import Foundation
import Observation
import SwiftUI
import UIKit

@Observable
final class BrewSession: Identifiable {
    enum Phase {
        case ready, running, paused, finished
    }

    let id = UUID()
    let snapshot: RecipeSnapshot
    let recipe: Recipe?

    private(set) var phase: Phase = .ready
    /// 経過時間（秒）。表示用に定期的に更新する
    private(set) var elapsed: Double = 0
    /// 現在のステップ。開始前は nil
    private(set) var currentStepIndex: Int?
    private(set) var startedAt: Date?
    /// 記録画面の入力内容。記録画面からスワイプで戻っても消えないよう、ここに持つ
    var logDraft = LogDraft()

    /// 経過時間 0 にあたる時刻。カウントを積み上げず、この時刻との差分で経過時間を出す
    @ObservationIgnored private var zeroDate: Date?
    @ObservationIgnored private var frozenElapsed: Double = 0
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var lastCountdownSecond: Int?
    @ObservationIgnored private var isInBackground = false
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private let liveActivity = LiveActivityController()

    init(recipe: Recipe) {
        self.recipe = recipe
        self.snapshot = recipe.snapshot
    }

    // MARK: 表示用

    var steps: [StepSnapshot] { snapshot.steps }

    var nextStepIndex: Int? {
        let index = (currentStepIndex ?? -1) + 1
        return index < steps.count ? index : nil
    }

    /// 次のステップまでの残り秒数
    var timeToNextStep: Double? {
        nextStepIndex.map { Double(steps[$0].startSeconds) - elapsed }
    }

    /// 現在のステップの中での進み具合（0〜1）
    var currentStepProgress: Double {
        guard let current = currentStepIndex, let next = nextStepIndex else { return phase == .ready ? 0 : 1 }
        let start = Double(steps[current].startSeconds)
        let end = Double(steps[next].startSeconds)
        guard end > start else { return 1 }
        return min(max((elapsed - start) / (end - start), 0), 1)
    }

    var totalProgress: Double {
        guard let total = snapshot.totalSeconds, total > 0 else { return 0 }
        return min(elapsed / Double(total), 1)
    }

    // MARK: 途中から開始（シーク）

    /// 開始位置を動かせる状態か（開始前と一時停止中だけ）
    var canSeek: Bool {
        (phase == .ready || phase == .paused) && seekableDuration != nil
    }

    /// 動かせる範囲（秒）。完了ステップの時刻まで
    var seekableDuration: Double? {
        guard let total = snapshot.totalSeconds, total > 0 else { return nil }
        return Double(total)
    }

    /// 経過時間を指定した秒数に動かす。完了ステップの手前までに収める
    func seek(to seconds: Double) {
        guard canSeek, let total = seekableDuration else { return }
        let target = min(max(0, seconds.rounded()), total - 1)
        frozenElapsed = target
        elapsed = target
        lastCountdownSecond = nil
        if phase == .ready && target == 0 {
            currentStepIndex = nil
        } else {
            currentStepIndex = steps.lastIndex { Double($0.startSeconds) <= target }
        }
    }

    /// シークの操作が終わったときに呼ぶ（一時停止中なら Live Activity に反映する）
    func endSeeking() {
        if phase == .paused { liveActivity.update(activityState()) }
    }

    /// ステップ単位で移動できる時刻（0:00 と各ステップの開始時刻。完了ステップは除く）
    private var jumpTargets: [Double] {
        guard let total = seekableDuration else { return [] }
        let starts = steps.map { Double($0.startSeconds) }.filter { $0 < total }
        return Array(Set([0] + starts)).sorted()
    }

    var canGoToNextStep: Bool {
        canSeek && jumpTargets.contains { $0 > elapsed }
    }

    var canGoToPreviousStep: Bool {
        canSeek && jumpTargets.contains { $0 < elapsed }
    }

    /// 次のステップの開始時刻へ移動する
    @discardableResult
    func goToNextStep() -> Bool {
        guard canSeek, let target = jumpTargets.first(where: { $0 > elapsed }) else { return false }
        seek(to: target)
        endSeeking()
        return true
    }

    /// 前のステップの開始時刻へ移動する。ステップの途中にいるときは、まずそのステップの先頭に戻る
    @discardableResult
    func goToPreviousStep() -> Bool {
        guard canSeek, let target = jumpTargets.last(where: { $0 < elapsed }) else { return false }
        seek(to: target)
        endSeeking()
        return true
    }

    // MARK: 操作

    func start() {
        guard phase == .ready else { return }
        // シークしていればその位置から始める
        zeroDate = Date().addingTimeInterval(-frozenElapsed)
        startedAt = Date()
        phase = .running
        UIApplication.shared.isIdleTimerDisabled = true
        // 開始時に今のステップの合図を鳴らすため、一度リセットしてから判定する
        currentStepIndex = nil
        tick(silently: false)
        if phase == .running {
            liveActivity.start(recipe: snapshot, state: activityState())
            startTicking()
        }
    }

    func pause() {
        guard phase == .running else { return }
        frozenElapsed = currentElapsed()
        elapsed = frozenElapsed
        phase = .paused
        stopTicking()
        BrewNotificationScheduler.cancelAll()
        liveActivity.update(activityState())
    }

    func resume() {
        guard phase == .paused else { return }
        zeroDate = Date().addingTimeInterval(-frozenElapsed)
        phase = .running
        startTicking()
        liveActivity.update(activityState())
        if isInBackground {
            BrewNotificationScheduler.schedule(snapshot: snapshot, elapsed: currentElapsed())
        }
    }

    func reset() {
        stopTicking()
        BrewNotificationScheduler.cancelAll()
        liveActivity.end(immediately: true)
        phase = .ready
        frozenElapsed = 0
        elapsed = 0
        currentStepIndex = nil
        lastCountdownSecond = nil
        startedAt = nil
        zeroDate = nil
    }

    func finish() {
        guard phase == .running || phase == .paused else { return }
        frozenElapsed = currentElapsed()
        elapsed = frozenElapsed
        phase = .finished
        stopTicking()
        BrewNotificationScheduler.cancelAll()
        liveActivity.end(finalState: activityState(), immediately: false)
        UIApplication.shared.isIdleTimerDisabled = false
        if !isInBackground { BrewFeedback.finished() }
    }

    /// 画面を閉じるときの後片付け
    func discard() {
        stopTicking()
        BrewNotificationScheduler.cancelAll()
        liveActivity.end(immediately: true)
        endBackgroundTask()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: バックグラウンド

    func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .background:
            isInBackground = true
            guard phase == .running else { return }
            // アプリが止められても知らせられるよう、残りのステップを通知で予約する
            BrewNotificationScheduler.schedule(snapshot: snapshot, elapsed: currentElapsed())
            // 止められるまでの少しの間は、Live Activity の表示を更新し続ける
            beginBackgroundTask()
        case .active:
            isInBackground = false
            BrewNotificationScheduler.cancelAll()
            endBackgroundTask()
            if phase == .running {
                tick(silently: true)
                liveActivity.update(activityState())
            }
        default:
            break
        }
    }

    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "brew-timer") { [weak self] in
            Task { @MainActor in self?.endBackgroundTask() }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: 内部処理

    private func currentElapsed(at date: Date = Date()) -> Double {
        switch phase {
        case .running:
            guard let zeroDate else { return 0 }
            return date.timeIntervalSince(zeroDate)
        case .ready, .paused, .finished:
            return frozenElapsed
        }
    }

    private func startTicking() {
        stopTicking()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick(silently: self.isInBackground)
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func tick(silently: Bool) {
        let now = currentElapsed()
        elapsed = now

        let newIndex = steps.lastIndex { Double($0.startSeconds) <= now }
        if newIndex != currentStepIndex {
            currentStepIndex = newIndex
            lastCountdownSecond = nil
            if let index = newIndex, steps[index].kind == .finish {
                finish()
                return
            }
            if !silently, newIndex != nil { BrewFeedback.stepChanged() }
            liveActivity.update(activityState())
        }

        // 次のステップの数秒前にカウントダウン
        if let remaining = timeToNextStep {
            let second = Int(remaining.rounded(.up))
            if second >= 1, second <= AppSettings.countdownSeconds, second != lastCountdownSecond {
                lastCountdownSecond = second
                if !silently { BrewFeedback.countdownTick() }
            }
        }
    }

    private func activityState() -> BrewActivityAttributes.ContentState {
        let now = Date()
        let current = currentElapsed(at: now)
        let next = nextStepIndex
        return BrewActivityAttributes.ContentState(
            timerStart: now.addingTimeInterval(-current),
            frozenElapsed: phase == .running ? nil : current,
            stateDate: now,
            currentTitle: phase == .finished ? "抽出完了" : (currentStepIndex.map(snapshot.title(for:)) ?? "準備中"),
            currentDetail: phase == .finished ? "おつかれさまでした" : (currentStepIndex.map(snapshot.detail(for:)) ?? ""),
            nextTitle: phase == .finished ? nil : next.map(snapshot.title(for:)),
            nextDetail: phase == .finished ? nil : next.map(snapshot.detail(for:)),
            nextStepDate: phase == .finished ? nil : next.map { now.addingTimeInterval(Double(steps[$0].startSeconds) - current) },
            isFinished: phase == .finished
        )
    }
}

/// 記録画面で入力中の内容
struct LogDraft: Equatable {
    var rating = 0
    var memo = ""
    /// 評価項目名 → 点数
    var scores: [String: Int] = [:]

    /// 評価・味・メモのどれかを入力したか
    var hasInput: Bool {
        rating > 0
            || scores.values.contains { $0 > 0 }
            || !memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@Observable
final class AppState {
    var session: BrewSession?

    func startBrew(_ recipe: Recipe) {
        session?.discard()
        session = BrewSession(recipe: recipe)
    }

    func closeSession() {
        session?.discard()
        session = nil
    }
}
