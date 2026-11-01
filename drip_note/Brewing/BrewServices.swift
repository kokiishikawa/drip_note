//
//  BrewServices.swift
//  設定・音と振動・ローカル通知・Live Activity
//

import ActivityKit
import AudioToolbox
import Foundation
import UIKit
import UserNotifications

// MARK: - 設定

enum SettingsKey {
    static let soundEnabled = "settings.soundEnabled"
    static let vibrationEnabled = "settings.vibrationEnabled"
    static let countdownSeconds = "settings.countdownSeconds"
}

enum AppSettings {
    static var soundEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.soundEnabled) as? Bool ?? true
    }

    static var vibrationEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.vibrationEnabled) as? Bool ?? true
    }

    static var countdownSeconds: Int {
        UserDefaults.standard.object(forKey: SettingsKey.countdownSeconds) as? Int ?? 3
    }
}

// MARK: - 音と振動（アプリが前面にあるとき）

/// システムサウンドはマナーモードで自動的に無音になる。振動は別に鳴らすので、
/// マナーモード中は振動だけで知らせることになる
enum BrewFeedback {
    private static let tickSound: SystemSoundID = 1057
    private static let stepSound: SystemSoundID = 1007
    private static let finishSound: SystemSoundID = 1025

    static func countdownTick() {
        if AppSettings.soundEnabled { AudioServicesPlaySystemSound(tickSound) }
        if AppSettings.vibrationEnabled { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    }

    static func stepChanged() {
        if AppSettings.soundEnabled { AudioServicesPlaySystemSound(stepSound) }
        if AppSettings.vibrationEnabled { AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }
    }

    static func finished() {
        if AppSettings.soundEnabled { AudioServicesPlaySystemSound(finishSound) }
        if AppSettings.vibrationEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }
}

// MARK: - ローカル通知（アプリがバックグラウンドのとき）

enum BrewNotificationScheduler {
    private static let prefix = "brew.step."
    private static let maxSteps = 100

    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// 現在の経過時間から、残りのステップの通知を予約する
    static func schedule(snapshot: RecipeSnapshot, elapsed: Double) {
        cancelAll()
        let center = UNUserNotificationCenter.current()
        for (index, step) in snapshot.steps.enumerated().prefix(maxSteps) {
            let interval = Double(step.startSeconds) - elapsed
            guard interval > 0.5 else { continue }

            let content = UNMutableNotificationContent()
            content.title = step.kind == .finish ? "抽出完了" : snapshot.title(for: index)
            content.body = step.memo.isEmpty ? snapshot.detail(for: index) : "\(snapshot.detail(for: index))\n\(step.memo)"
            // 通知音はマナーモード中は振動のみになる
            content.sound = AppSettings.soundEnabled ? .default : nil
            content.interruptionLevel = .active

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.add(UNNotificationRequest(identifier: prefix + "\(index)", content: content, trigger: trigger))
        }
    }

    static func cancelAll() {
        let ids = (0..<maxSteps).map { prefix + "\($0)" }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
}

/// アプリが前面にあるときは通知バナーを出さない（アプリ内で音と振動を鳴らすため）
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }
}

// MARK: - Live Activity

final class LiveActivityController {
    private var activity: Activity<BrewActivityAttributes>?

    static var isEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(recipe: RecipeSnapshot, state: BrewActivityAttributes.ContentState) {
        guard Self.isEnabled else { return }
        end(immediately: true)
        let attributes = BrewActivityAttributes(recipeName: recipe.name, summary: recipe.summary)
        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: Self.staleDate(for: state)),
            pushType: nil
        )
    }

    func update(_ state: BrewActivityAttributes.ContentState) {
        guard let activity else { return }
        let content = ActivityContent(state: state, staleDate: Self.staleDate(for: state))
        Task { await activity.update(content) }
    }

    func end(finalState: BrewActivityAttributes.ContentState? = nil, immediately: Bool) {
        guard let activity else { return }
        self.activity = nil
        let content = finalState.map { ActivityContent(state: $0, staleDate: nil) }
        let policy: ActivityUIDismissalPolicy = immediately ? .immediate : .after(Date().addingTimeInterval(5 * 60))
        Task { await activity.end(content, dismissalPolicy: policy) }
    }

    /// 前回の起動で残った Live Activity を終了する
    static func endAll() async {
        for activity in Activity<BrewActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// 次のステップの時刻を過ぎたら古い情報とみなす
    private static func staleDate(for state: BrewActivityAttributes.ContentState) -> Date? {
        guard state.frozenElapsed == nil else { return nil }
        return state.nextStepDate?.addingTimeInterval(1)
    }
}
