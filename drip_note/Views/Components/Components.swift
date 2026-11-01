//
//  Components.swift
//  画面をまたいで使う小さな View
//

import SwiftUI

/// ステップ一覧の1行
struct StepRowView: View {
    let snapshot: RecipeSnapshot
    let index: Int
    var isCurrent = false
    var isDone = false

    var body: some View {
        let step = snapshot.steps[index]
        HStack(spacing: 12) {
            Text(Fmt.mmss(Double(step.startSeconds)))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            Image(systemName: step.kind.symbol)
                .foregroundStyle(step.kind == .finish ? Color.green : Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.title(for: index))
                    .font(.body.weight(isCurrent ? .bold : .regular))
                if step.kind.hasPour {
                    Text(snapshot.detail(for: index))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !step.memo.isEmpty {
                    Text(step.memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .opacity(isDone ? 0.45 : 1)
    }
}

/// 星による5段階評価
struct StarRatingView: View {
    @Binding var rating: Int
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    rating = (rating == value) ? 0 : value
                } label: {
                    Image(systemName: value <= rating ? "star.fill" : "star")
                        .font(.system(size: size))
                        .foregroundStyle(value <= rating ? Color.orange : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(value)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("評価")
        .accessibilityValue(rating == 0 ? "未評価" : "\(rating)")
    }
}

/// 表示専用の星
struct StarsText: View {
    let rating: Int

    var body: some View {
        if rating == 0 {
            Text("未評価").font(.caption).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 1) {
                ForEach(1...5, id: \.self) { value in
                    Image(systemName: value <= rating ? "star.fill" : "star")
                }
            }
            .font(.caption)
            .foregroundStyle(.orange)
            .accessibilityLabel("評価 \(rating)")
        }
    }
}

/// 味の評価項目ごとの 1〜5 の点数
struct ScoreSelector: View {
    let name: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { score in
                    Button {
                        value = (value == score) ? 0 : score
                    } label: {
                        Circle()
                            .fill(score <= value ? Color.accentColor : Color.secondary.opacity(0.2))
                            .frame(width: 24, height: 24)
                            .overlay(Text("\(score)").font(.caption2).foregroundStyle(score <= value ? .white : .secondary))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(value == 0 ? "未評価" : "\(value)")
    }
}

/// 数値入力欄（単位つき）
///
/// 入力欄を行いっぱいに広げると、数字の左側の空きをタップしたときにカーソルが先頭に入ってしまう。
/// そのため入力欄は数字の幅だけにし、行のほかの場所をタップしたらコードからフォーカスする
/// （コードからフォーカスすると、カーソルは末尾に入る）。
struct NumberField: View {
    let title: String
    @Binding var value: Double
    let unit: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Spacer(minLength: 8)
            TextField(title, value: $value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .fixedSize()
                .frame(minWidth: 32, alignment: .trailing)
            Text(unit).foregroundStyle(.secondary)
        }
        .frame(minHeight: 36)
        .contentShape(Rectangle())
        .onTapGesture {
            // 余白タップでキーボードを閉じる処理と同時に走るため、その後にフォーカスする
            DispatchQueue.main.async { isFocused = true }
        }
    }
}

/// 1行のテキスト入力欄。タップできる範囲を行の高さいっぱいに広げている
struct FormTextField: View {
    let title: String
    @Binding var text: String

    init(_ title: String, text: Binding<String>) {
        self.title = title
        self._text = text
    }

    var body: some View {
        TextField(title, text: $text)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
    }
}
