//
//  NavigationSupport.swift
//  「戻る」ボタンを隠した画面でも、左端からのスワイプで戻れるようにする
//
//  SwiftUI で navigationBarBackButtonHidden を使うと、戻るスワイプも一緒に無効になる。
//  記録画面は「戻る」ボタンの代わりに「記録しない」を置いているが、スワイプでは戻れるようにしたいので、
//  ナビゲーションの戻るジェスチャーを、前の画面があるときは常に有効にする。
//

import UIKit

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // 一番最初の画面では戻れない
        viewControllers.count > 1
    }
}
