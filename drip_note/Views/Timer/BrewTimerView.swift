//
//  BrewTimerView.swift
//  抽出タイマー画面。円形のリングを中心に、必要な情報だけをシンプルに見せる
//
//  - リング: 今のステップの進み具合（次のステップまでの時間）
//  - リングの中央: 目標の累計湯量（注ぐステップ）または残り時間（待つステップ）
//  - リングの下: 経過時間、ステップの進み具合の点、次のステップ
//

import SwiftUI

struct BrewTimerView: View {
    let session: BrewSession
    @Environment(AppState.self) private var appState
    @State private var showLogEditor = false
    @State private var showSteps = false
    @State private var confirmClose = false
    @State private var confirmDiscardLog = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// iPad など横幅の広い画面では、リングと文字を大きくする
    private var isRegular: Bool { horizontalSizeClass == .regular }
    private var scale: CGFloat { isRegular ? 1.35 : 1 }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                // 横向き（横長）のときは、左にリング・右に情報とボタンを並べる
                if geometry.size.width > geometry.size.height * 1.15 {
                    HStack(spacing: isRegular ? 56 : 24) {
                        ring
                            .padding(isRegular ? 32 : 12)
                        VStack(spacing: 0) {
                            Spacer(minLength: 8)
                            belowRing
                            Spacer(minLength: 24)
                            controls
                                .padding(.bottom, 12)
                        }
                        .frame(maxWidth: 440)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        Spacer(minLength: 8)
                        ring
                            .padding(.horizontal, 36)
                        Spacer(minLength: 24)
                        belowRing
                        Spacer(minLength: 24)
                        controls
                            .padding(.bottom, 12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal)
            // 余白も含めた画面全体でスワイプを受け付ける（ボタンのタップはそのまま反応する）
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(stepSwipeGesture, isEnabled: session.canSeek)
            .navigationTitle(session.snapshot.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる", systemImage: "xmark") {
                        switch session.phase {
                        case .ready:
                            appState.closeSession()
                        case .finished:
                            // 記録画面から戻ってきたとき。「記録しない」と同じく、入力があるときだけ確認する
                            if session.logDraft.hasInput {
                                confirmDiscardLog = true
                            } else {
                                appState.closeSession()
                            }
                        case .running, .paused:
                            confirmClose = true
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("ステップ一覧", systemImage: "list.bullet") { showSteps = true }
                }
            }
            .confirmationDialog("抽出を中止しますか？", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("中止して閉じる", role: .destructive) { appState.closeSession() }
            } message: {
                Text("タイマーは破棄され、ログは保存されません。")
            }
            .alert("記録せずに閉じますか？", isPresented: $confirmDiscardLog) {
                Button("キャンセル", role: .cancel) {}
                Button("記録しない", role: .destructive) { appState.closeSession() }
            } message: {
                Text("入力した評価やメモは保存されません。")
            }
            .sheet(isPresented: $showSteps) { stepsSheet }
            .navigationDestination(isPresented: $showLogEditor) {
                BrewLogEditorView(mode: .new(session))
            }
            .onChange(of: session.phase) { _, phase in
                if phase == .finished { showLogEditor = true }
            }
            .task {
                // 抽出を始める前に、バックグラウンド用の通知の許可をもらっておく
                await BrewNotificationScheduler.requestAuthorization()
            }
        }
        // 下スワイプで閉じるとき、画面ごと指に合わせて下げる
        .background(Color(.systemBackground))
        .offset(y: dismissOffset)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { screenHeight = $0 }
        // 下げたときに、下にある一覧が見えるようにする
        .presentationBackground(.clear)
    }

    // MARK: 状態

    private var snapshot: RecipeSnapshot { session.snapshot }

    private var currentStep: StepSnapshot? {
        session.currentStepIndex.map { snapshot.steps[$0] }
    }

    /// 次のステップの直前（カウントダウン中）かどうか
    private var isCountingDown: Bool {
        guard session.phase == .running, let remaining = session.timeToNextStep else { return false }
        return remaining <= Double(AppSettings.countdownSeconds)
    }

    private var tint: Color {
        switch session.phase {
        case .finished: .green
        case .paused: .secondary
        default: isCountingDown ? .orange : .coffee
        }
    }

    private var ringProgress: Double {
        switch session.phase {
        case .ready: 0
        case .finished: 1
        case .running, .paused: session.currentStepProgress
        }
    }

    // MARK: リング

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.07), lineWidth: 14)
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: session.currentStepIndex)
            // 中身だけをスワイプで左右にスライドさせる
            ringCenter
                .padding(36)
                .id(session.currentStepIndex)
                .transition(.push(from: swipeForward ? .trailing : .leading))
                .offset(x: dragOffset)
                .clipShape(Circle())
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 340 * scale)
        .animation(.easeInOut(duration: 0.25), value: tint)
        .accessibilityElement(children: .combine)
        .accessibilityAdjustableAction { direction in
            // VoiceOver では上下スワイプでステップを移動する
            switch direction {
            case .increment: changeStep(forward: true)
            case .decrement: changeStep(forward: false)
            @unknown default: break
            }
        }
    }

    // MARK: スワイプでステップを移動

    /// 直前の移動が「次へ」だったか（スライドの向きに使う）
    @State private var swipeForward = true
    /// 指に合わせて中身を少しだけ動かす（横スワイプ中のみ）
    @State private var dragOffset: CGFloat = 0
    /// 1回のスワイプの向き。動かし始めの向きで決め、指を離すまで変えない
    @State private var dragAxis: DragAxis?

    private enum DragAxis { case horizontal, vertical }

    /// 左右: ステップの移動（開始前・一時停止中）。左スワイプで次、右スワイプで前
    /// 下: 画面を閉じる（開始前のみ）
    private var stepSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                let width = value.translation.width
                let height = value.translation.height
                if dragAxis == nil {
                    dragAxis = abs(width) > abs(height) ? .horizontal : .vertical
                }
                switch dragAxis {
                case .horizontal:
                    // 移動できない方向へは、引っぱったときに抵抗を感じるようにする
                    let canMove = width < 0 ? session.canGoToNextStep : session.canGoToPreviousStep
                    dragOffset = width * (canMove ? 0.35 : 0.12)
                case .vertical:
                    guard session.phase == .ready else { return }
                    dismissOffset = max(0, height)
                case nil:
                    break
                }
            }
            .onEnded { value in
                let axis = dragAxis
                dragAxis = nil
                switch axis {
                case .horizontal:
                    dragOffset = 0
                    let width = value.translation.width
                    let predicted = value.predictedEndTranslation.width
                    if width < -50 || predicted < -120 {
                        changeStep(forward: true)
                    } else if width > 50 || predicted > 120 {
                        changeStep(forward: false)
                    }
                case .vertical:
                    if dismissOffset > 0 { finishDismissDrag(value) }
                case nil:
                    break
                }
            }
    }

    // MARK: 下スワイプで閉じる（開始前のみ）

    @State private var dismissOffset: CGFloat = 0
    @State private var screenHeight: CGFloat = 1000

    private func finishDismissDrag(_ value: DragGesture.Value) {
        // 軽く閉じられるよう、少し下げるか、短くても下へ払えば閉じる
        let shouldDismiss = value.translation.height > 80
            || value.predictedEndTranslation.height > 180
            || value.velocity.height > 450
        guard shouldDismiss else {
            withAnimation(.spring(duration: 0.3)) { dismissOffset = 0 }
            return
        }
        // 画面の下まで送り出してから、アニメーションなしで閉じる（二重に動かないように）
        withAnimation(.easeOut(duration: 0.18)) {
            dismissOffset = screenHeight
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { appState.closeSession() }
        }
    }

    private func changeStep(forward: Bool) {
        swipeForward = forward
        var moved = false
        withAnimation(.spring(duration: 0.35)) {
            moved = forward ? session.goToNextStep() : session.goToPreviousStep()
        }
        if moved, AppSettings.vibrationEnabled {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    @ViewBuilder
    private var ringCenter: some View {
        VStack(spacing: 6) {
            switch session.phase {
            case .ready:
                if let index = session.currentStepIndex {
                    // シークで開始位置を選んでいるとき
                    caption("\(Fmt.mmss(session.elapsed)) から開始")
                    if snapshot.steps[index].kind.hasPour {
                        bigValue(Fmt.number(snapshot.cumulativeWater(through: index)), unit: "g")
                    } else {
                        bigValue(Fmt.mmss(session.elapsed), unit: nil)
                    }
                    Text(snapshot.title(for: index))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    caption("READY")
                    bigValue(Fmt.number(snapshot.waterGrams), unit: "g")
                    Text("豆 \(Fmt.grams(snapshot.beanGrams)) · \(Fmt.number(snapshot.temperature))℃")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if session.canSeek {
                        Text("左右にスワイプでステップを移動")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                }

            case .finished:
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.green)
                bigValue(Fmt.mmss(session.elapsed), unit: nil)
                Text("抽出完了")
                    .font(.callout)
                    .foregroundStyle(.secondary)

            case .running, .paused:
                if let index = session.currentStepIndex, let step = currentStep {
                    caption(session.phase == .paused ? "一時停止中" : snapshot.title(for: index))
                    if step.kind.hasPour {
                        // 注ぐステップ: 目標の累計湯量を大きく
                        bigValue(Fmt.number(snapshot.cumulativeWater(through: index)), unit: "g")
                        Text("+\(Fmt.grams(step.pourGrams))")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        // 待つステップ: 残り時間を大きく
                        bigValue(Fmt.mmss((session.timeToNextStep ?? 0).rounded(.up)), unit: nil)
                        Text(step.kind.label)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if step.kind.hasPour, let remaining = session.timeToNextStep {
                        Text(Fmt.mmss(remaining.rounded(.up)))
                            .font(.title3.weight(.medium).monospacedDigit())
                            .foregroundStyle(isCountingDown ? Color.orange : Color.secondary)
                            .padding(.top, 4)
                            .accessibilityLabel("次のステップまで \(Fmt.mmss(remaining.rounded(.up)))")
                    }
                }
            }
        }
        .multilineTextAlignment(.center)
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .tracking(1.5)
            .foregroundStyle(tint)
    }

    private func bigValue(_ value: String, unit: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(.system(size: 80 * scale, weight: .thin, design: .rounded))
                .contentTransition(.numericText())
            if let unit {
                Text(unit)
                    .font(.system(size: 28 * scale, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
    }

    // MARK: リングの下

    private var belowRing: some View {
        VStack(spacing: 18) {
            // 経過時間
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.mmss(session.elapsed))
                    .font(.system(size: 48 * scale, weight: .light, design: .rounded))
                    .foregroundStyle(.primary)
                if let total = snapshot.totalSeconds {
                    Text("/ \(Fmt.mmss(Double(total)))")
                        .font(.system(size: 24 * scale, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("経過時間 \(Fmt.mmss(session.elapsed))")

            stepDots

            // 次のステップ（またはメモ）
            Group {
                if session.phase != .finished, let next = session.nextStepIndex {
                    HStack(spacing: 8) {
                        Text("次")
                            .foregroundStyle(.secondary)
                        Text(snapshot.title(for: next))
                            .fontWeight(.semibold)
                        if snapshot.steps[next].kind.hasPour {
                            Text("\(Fmt.grams(snapshot.steps[next].pourGrams)) → 計\(Fmt.grams(snapshot.cumulativeWater(through: next)))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout.monospacedDigit())
                } else {
                    Text(" ").font(.callout)
                }
            }

            if let memo = currentStep?.memo, !memo.isEmpty, session.phase != .finished {
                Text(memo)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
    }

    /// ステップの進み具合を点で表す（完了ステップは除く）
    private var stepDots: some View {
        let indices = snapshot.steps.indices.filter { snapshot.steps[$0].kind != .finish }
        let current = session.phase == .finished ? Int.max : (session.currentStepIndex ?? -1)
        return HStack(spacing: 10) {
            ForEach(indices, id: \.self) { index in
                Circle()
                    .fill(index <= current ? tint : Color.primary.opacity(0.12))
                    .frame(width: index == current ? 10 : 7, height: index == current ? 10 : 7)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.currentStepIndex)
        .accessibilityHidden(true)
    }

    // MARK: 操作ボタン

    @ViewBuilder
    private var controls: some View {
        switch session.phase {
        case .ready:
            if session.elapsed > 0 {
                // スワイプで開始位置を動かしたときは、最初に戻すボタンも並べる
                HStack(spacing: 48) {
                    CircleButton(title: "最初から", systemImage: "arrow.counterclockwise", style: .secondary) {
                        swipeForward = false
                        withAnimation(.spring(duration: 0.35)) { session.seek(to: 0) }
                    }
                    CircleButton(title: "スタート", systemImage: "play.fill", style: .primary) { session.start() }
                }
            } else {
                CircleButton(title: "スタート", systemImage: "play.fill", style: .primary) { session.start() }
            }
        case .running:
            HStack(spacing: 48) {
                CircleButton(title: "終了", systemImage: "stop.fill", style: .secondary) { session.finish() }
                CircleButton(title: "一時停止", systemImage: "pause.fill", style: .primary) { session.pause() }
            }
        case .paused:
            HStack(spacing: 32) {
                CircleButton(title: "リセット", systemImage: "arrow.counterclockwise", style: .secondary) { session.reset() }
                CircleButton(title: "再開", systemImage: "play.fill", style: .primary) { session.resume() }
                CircleButton(title: "終了", systemImage: "stop.fill", style: .secondary) { session.finish() }
            }
        case .finished:
            CircleButton(title: "記録する", systemImage: "square.and.pencil", style: .primary) { showLogEditor = true }
        }
    }

    // MARK: ステップ一覧

    private var stepsSheet: some View {
        NavigationStack {
            List {
                ForEach(snapshot.steps.indices, id: \.self) { index in
                    StepRowView(
                        snapshot: snapshot,
                        index: index,
                        isCurrent: index == session.currentStepIndex,
                        isDone: (session.currentStepIndex ?? -1) > index
                    )
                }
            }
            .navigationTitle("ステップ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("閉じる") { showSteps = false }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 丸い操作ボタン（ラベルはボタンの下）
private struct CircleButton: View {
    enum Style { case primary, secondary }

    let title: String
    let systemImage: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: style == .primary ? 26 : 20, weight: .semibold))
                    .frame(width: style == .primary ? 76 : 60, height: style == .primary ? 76 : 60)
                    .foregroundStyle(style == .primary ? Color.white : Color.primary)
                    .background(
                        Circle().fill(style == .primary ? Color.coffee : Color.primary.opacity(0.08))
                    )
                    // 大きさの違うボタンを並べてもラベルの高さが揃うようにする
                    .frame(height: 76)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

extension Color {
    /// アプリのテーマカラー（コーヒー色）
    static let coffee = Color(red: 0.69, green: 0.47, blue: 0.31)
}

#Preview("開始前") {
    BrewTimerView(session: BrewSession(recipe: PreviewData.recipe))
        .previewEnvironment()
}

#Preview("抽出中") {
    let session = BrewSession(recipe: PreviewData.recipe)
    BrewTimerView(session: session)
        .previewEnvironment()
        .onAppear { session.start() }
}
