//
//  KeyboardSupport.swift
//  テキスト入力の操作感をアプリ全体で整える
//
//  - 入力欄以外の場所をタップしたら、キーボードをしまう
//

import SwiftUI
import UIKit

enum KeyboardSupport {
    private static var isInstalled = false

    /// アプリ起動時に1回だけ呼ぶ
    static func install() {
        guard !isInstalled else { return }
        isInstalled = true
        installTapToDismiss()
    }

    /// キーボードをしまう
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// キーボードを閉じて入力中の値を確定させてから、処理を実行する。
    /// 数値の入力欄はキーボードを閉じた時点で値が確定するため、保存ボタンではこれを使う
    static func commitEditing(then action: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.async { action() }
    }

    // MARK: 余白タップでキーボードをしまう

    private static func installTapToDismiss() {
        // シーンの接続を待ってからウインドウに付ける
        DispatchQueue.main.async {
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
            for window in windows where !(window.gestureRecognizers ?? []).contains(where: { $0 is DismissKeyboardTapGesture }) {
                window.addGestureRecognizer(DismissKeyboardTapGesture())
            }
        }
    }
}

/// 入力欄以外へのタップでキーボードをしまう。ほかのボタンなどの操作は邪魔しない
private final class DismissKeyboardTapGesture: UITapGestureRecognizer, UIGestureRecognizerDelegate {
    init() {
        super.init(target: nil, action: nil)
        addTarget(self, action: #selector(handleTap))
        cancelsTouchesInView = false
        delegate = self
    }

    @objc private func handleTap() {
        view?.endEditing(true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // 入力欄そのもの（またはその内部）へのタップでは閉じない
        var view = touch.view
        while let current = view {
            if current is UITextField || current is UITextView { return false }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
