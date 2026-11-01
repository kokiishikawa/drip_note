//
//  drip_noteApp.swift
//  drip_note
//
//  Created by koki on 2026/11/01.
//

import SwiftData
import SwiftUI
import UserNotifications

@main
struct drip_noteApp: App {
    @State private var appState = AppState()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
        .modelContainer(for: [Recipe.self, RecipeStep.self, BrewLog.self, TasteScore.self, TasteAttribute.self])
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var appState = appState
        TabView {
            Tab("レシピ", systemImage: "list.bullet.rectangle") {
                RecipeListView()
            }
            Tab("ログ", systemImage: "book.closed") {
                BrewLogListView()
            }
            Tab("設定", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .fullScreenCover(item: $appState.session) { session in
            BrewTimerView(session: session)
        }
        .onAppear {
            KeyboardSupport.install()
        }
        .task {
            SeedData.seedIfNeeded(context)
            await LiveActivityController.endAll()
        }
        .onChange(of: scenePhase) { _, newPhase in
            appState.session?.handleScenePhase(newPhase)
        }
    }
}

#Preview {
    RootView()
        .previewEnvironment()
}
