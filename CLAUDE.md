# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 概要

Drip Note: ハンドドリップのレシピをステップ単位で記録し、タイマーとして実行する iOS / iPadOS アプリ（SwiftUI + SwiftData + ActivityKit）。要求定義は `docs/requirements.md`。コンセプトは「記録したレシピを、タイマーとしてわかりやすく実行できること」。

## ビルド・実行

`xcode-select` が Command Line Tools を向いているため、`DEVELOPER_DIR` の指定が必要。

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# ビルド（アプリと Widget Extension の両方がビルドされる）
xcodebuild -project drip_note.xcodeproj -scheme drip_note \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error|warning: [^M]|BUILD"

# シミュレーターで起動（BUNDLE: koki.drip-note）
xcrun simctl install <SIM_ID> <DerivedData>/Build/Products/Debug-iphonesimulator/drip_note.app
xcrun simctl launch <SIM_ID> koki.drip-note
xcrun simctl io <SIM_ID> screenshot out.png
```

- テストターゲットと lint の設定はない。確認はビルドと、シミュレーターのスクリーンショットで行う。
- `xcrun simctl` も `DEVELOPER_DIR` の指定がないと動かない。
- iPad の確認には `name=iPad Pro 11-inch (M5)` を指定する。
- `simctl` ではタップ操作ができない。タイマー画面などを撮りたいときは、`RootView` の `.task` に起動引数（例：`-debugStartTimer`）で `appState.startBrew(...)` を呼ぶコードを**一時的に**入れて `simctl launch <SIM_ID> koki.drip-note -debugStartTimer` で開き、確認が終わったら必ず削除する。ユーザーが同じシミュレーターを操作中のことがあるので、邪魔になりそうなら使っていない端末（iPad など）で確認する。
- SourceKit が「No such module 'UIKit'」「Cannot find 'Recipe' in scope」などのエラーを出すが、インデックスが追いついていないだけ。`xcodebuild` が通れば問題ない。
- 各画面に `#Preview` がある。`.previewEnvironment()`（`drip_note/Previews/PreviewData.swift`）で、メモリ上のサンプルデータと `AppState` を渡す。

## プロジェクト構成の要点

- **フォルダ同期グループ（objectVersion 77）**：フォルダにファイルを置くだけでターゲットに含まれる。pbxproj の編集は不要。
  - `drip_note/` → アプリ
  - `drip_noteWidget/` → Widget Extension（Live Activity）。`Info.plist` は membershipExceptions でリソースから除外している
  - `Shared/` → **両方のターゲット**に含まれる（`BrewActivityAttributes`、書式ヘルパー `Fmt`）
- アプリのターゲットは `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`、Widget は既定のまま。両方で使う型や、Codable / Sendable にする値型は `nonisolated struct` / `nonisolated enum` にする（`RecipeSnapshot`、`StepKind`、`Fmt` など）。
- デプロイターゲットは iOS 26.5。開発言語は `ja`（iOS 標準のボタンを日本語で表示するため）。

## アーキテクチャ

### データ
- `Models/Models.swift`：SwiftData の `Recipe` / `RecipeStep` / `BrewLog` / `TasteScore` / `TasteAttribute`。将来 CloudKit で同期するため、全プロパティにデフォルト値をつけ、リレーションは Optional にし、unique 制約は使わない。
- `Models/RecipeSnapshot.swift`：レシピの値をそのまま持つ構造体。**編集中の下書き・タイマーの実行・ログへの保存**のすべてで、モデルではなくこれを使う。
  - 編集画面は snapshot を編集し、保存時に `Recipe.apply(_:)` でステップを作り直す。
  - `BrewLog` は抽出した時点の snapshot を JSON（`recipeSnapshotData`）で保存する。あとでレシピを編集してもログは変わらない。
  - ステップ名（「2投目」）、累計湯量、比率（「15倍」）の表示ロジックはここにある。比率は時間に見えるので `1:15` 表記を使わない。
- ステップの時刻は「抽出開始からの開始時刻（秒）」で持つ。`.finish` ステップの時刻でタイマーが自動で終わる。
- `Recipe.isFavorite`：お気に入り。一覧では上に固定して表示する（`SortDescriptor` は Bool で並べ替えられないので、`displayedRecipes` で並べ替えている）。お気に入りだけを表示する絞り込みの状態は `@AppStorage("recipeList.favoritesOnly")` に保存する。お気に入りを切り替えても `updatedAt` は更新しない。
- 味の評価項目（`TasteAttribute`）はユーザーが自由に作れる。`TasteScore` は項目名をコピーして持つので、項目を削除・改名してもログに残る。

### タイマー（`Brewing/`）
- `BrewSession`（@Observable）がタイマーの本体。`AppState.session` を `RootView` が `fullScreenCover` で表示する。
- 経過時間はカウントを積み上げず、`zeroDate`（経過時間 0 にあたる時刻）との差で計算する。50ms ごとの tick でステップの切り替えとカウントダウンを判定する。
- バックグラウンドでは iOS がアプリを止めるので、次のように対応している（`handleScenePhase`）：
  - バックグラウンドに入ったら、残りのステップを**ローカル通知で予約**する。前面に戻ったら取り消す。
  - `beginBackgroundTask` で止められるまでの短い間は、Live Activity の更新を続ける。
  - Live Activity では `Text(timerInterval:)` / `.timer` スタイルを使い、OS が時間をカウントする。ステップ名はアプリが止まると更新できないので、`staleDate` を過ぎたら案内文を出す。
- 音はシステムサウンド（マナーモードで自動的に無音になる）、振動はハプティクスで別に鳴らす。マナーモード中は振動だけになる、という要件をこの組み合わせで満たしている。
- シーク（ステップの移動）は**開始前と一時停止中だけ**できる。`goToNextStep` / `goToPreviousStep` がステップの開始時刻へ移動する。

### 画面
- テーマカラーは `Color.coffee`（`BrewTimerView.swift` で定義）。`AccentColor` アセットは未設定のままなので、一覧の ▶ ボタンなどは標準の青になっている。
- 設定値は `UserDefaults` に保存する。キーは `SettingsKey`、ビュー以外からの読み出しは `AppSettings`（どちらも `Brewing/BrewServices.swift`）。
- タイマー画面（`Views/Timer/BrewTimerView.swift`）：円形のリングを中心にしたシンプルなデザイン。左スワイプで次のステップ、右スワイプで前のステップ、開始前は下スワイプで閉じる。スワイプは画面全体で受け付ける。1つの `DragGesture` で扱い、動かし始めの向きで横か縦かを決めて（`dragAxis`）、指を離すまで切り替えない。下スワイプで閉じる動きは、`fullScreenCover` に `.presentationBackground(.clear)` を付け、画面ごと `offset` で下げて実現している。横長の画面では左右2列のレイアウトになり、iPad（regular）では `scale` で拡大する。
- レシピとログの一覧は `NavigationSplitView`（iPad では2列）。表示中のモデルを削除すると落ちるので、選択を外してから次のランループで削除する。
- `Views/Components/KeyboardSupport.swift`：ウインドウに付けたジェスチャーで、余白をタップしたらキーボードをしまう。数値の入力欄（`TextField(value:format:)`）はキーボードを閉じた時点で値が確定するので、保存ボタンは `KeyboardSupport.commitEditing(then:)` を通す。
- 抽出後の記録画面は、タイマー画面の `NavigationStack` に push される。入力内容は `BrewSession.logDraft` に持つので、左端スワイプでタイマー画面に戻っても消えない。「記録しない」と、抽出完了画面の ✕ は、`logDraft.hasInput` のときだけ確認のアラートを出す。
- `Views/Components/NavigationSupport.swift` で `UINavigationController` を拡張し、`navigationBarBackButtonHidden` を使った画面でも戻るスワイプを有効にしている（アプリ全体に効く）。
- `NumberField` は、入力欄を数字の幅だけにし、行のほかの場所をタップしたら `FocusState` でフォーカスする（右寄せの入力欄の空きをタップすると、カーソルが先頭に入ってしまうため）。

## 作業の進め方（ユーザーの希望）

- やりとりは日本語で行う。UI の文言もすべて日本語にする。
- 仕様があいまいな機能は、実装の前に仕様を説明して確認をとる。
- git の操作（コミットなど）は、指示があったときだけ行う。コミットメッセージに AI の著作表記（Co-Authored-By など）は入れない。
- テキスト入力のカーソル位置は iOS 標準の動きにする（以前、末尾に固定する案は取りやめた）。
- キーボードの上に「完了」ボタンは付けない。
