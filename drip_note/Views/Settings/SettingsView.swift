//
//  SettingsView.swift
//

import SwiftData
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.soundEnabled) private var soundEnabled = true
    @AppStorage(SettingsKey.vibrationEnabled) private var vibrationEnabled = true
    @AppStorage(SettingsKey.countdownSeconds) private var countdownSeconds = 3

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("音", isOn: $soundEnabled)
                    Toggle("振動", isOn: $vibrationEnabled)
                    Picker("ステップ前のカウントダウン", selection: $countdownSeconds) {
                        Text("なし").tag(0)
                        Text("3秒前").tag(3)
                        Text("5秒前").tag(5)
                    }
                } header: {
                    Text("タイマーの通知")
                } footer: {
                    Text("マナーモード中は音を出さず、振動だけで知らせます。\nアプリがバックグラウンドにあるときは、iPhone の通知で知らせます。通知の音をオフにすると、通知の振動も鳴りません。")
                }

                Section("味の評価") {
                    NavigationLink("評価項目を編集") {
                        TasteAttributeListView()
                    }
                }

                Section {
                    LabeledContent("Live Activity", value: LiveActivityController.isEnabled ? "有効" : "無効")
                    Button("iPhone の設定を開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } header: {
                    Text("ロック画面と Dynamic Island")
                } footer: {
                    Text("Live Activity と通知は、iPhone の設定アプリから許可できます。")
                }
            }
            .navigationTitle("設定")
        }
    }
}

struct TasteAttributeListView: View {
    @Query(sort: \TasteAttribute.sortOrder) private var attributes: [TasteAttribute]
    @Environment(\.modelContext) private var context
    @State private var isAdding = false
    @State private var renaming: TasteAttribute?
    @State private var nameInput = ""

    var body: some View {
        List {
            Section {
                ForEach(attributes) { attribute in
                    Button(attribute.name) {
                        nameInput = attribute.name
                        renaming = attribute
                    }
                    .tint(.primary)
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(attributes[index]) }
                }
                .onMove(perform: move)
            } footer: {
                Text("項目名をタップすると名前を変えられます。削除しても、これまでのログの評価は残ります。")
            }
        }
        .navigationTitle("味の評価項目")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("追加", systemImage: "plus") {
                    nameInput = ""
                    isAdding = true
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .alert("評価項目を追加", isPresented: $isAdding) {
            TextField("例: 香り", text: $nameInput)
            Button("キャンセル", role: .cancel) {}
            Button("追加") { add() }
        }
        .alert("名前を変更", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("項目名", text: $nameInput)
            Button("キャンセル", role: .cancel) {}
            Button("変更") {
                let name = nameInput.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { renaming?.name = name }
            }
        }
    }

    private func add() {
        let name = nameInput.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let order = (attributes.map(\.sortOrder).max() ?? -1) + 1
        context.insert(TasteAttribute(name: name, sortOrder: order))
    }

    private func move(from source: IndexSet, to destination: Int) {
        var items = attributes
        items.move(fromOffsets: source, toOffset: destination)
        for (index, item) in items.enumerated() {
            item.sortOrder = index
        }
    }
}

#Preview("設定") {
    SettingsView()
        .previewEnvironment()
}

#Preview("評価項目") {
    NavigationStack {
        TasteAttributeListView()
    }
    .previewEnvironment()
}
