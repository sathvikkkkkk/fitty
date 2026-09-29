import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.onboarded {
                MainTabs()
            } else {
                OnboardingView()
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.teal)
        .sheet(isPresented: Binding(
            get: { model.journalPromptDay != nil },
            set: { if !$0 { model.journalPromptDay = nil } }
        )) {
            if let dayKey = model.journalPromptDay {
                JournalPromptSheet(dayKey: dayKey)
            }
        }
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Today", systemImage: "gauge.with.needle") }
            FitnessView()
                .tabItem { Label("Fitness", systemImage: "figure.run") }
            NutritionView()
                .tabItem { Label("Nutrition", systemImage: "fork.knife") }
            CoachView()
                .tabItem { Label("Coach", systemImage: "sparkles") }
            SettingsView()
                .tabItem { Label("More", systemImage: "ellipsis") }
        }
        .toolbarBackground(Theme.bg, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
