import SwiftUI

@main
struct GameStreamApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var appearance = AppearanceStore.shared
    @State private var showIntro = !OnboardingStore.hasCompletedIntro
    @State private var showingMicrosoftLogin = false

    var body: some Scene {
        WindowGroup {
            Group {
                if session.isSignedIn {
                    RootView()
                } else if showIntro {
                    IntroView {
                        // Get Started only dismisses intro. It never signs the user in.
                        OnboardingStore.markIntroCompleted()
                        withAnimation(.easeInOut(duration: 0.45)) {
                            showIntro = false
                        }
                    }
                } else {
                    WelcomeView {
                        showingMicrosoftLogin = true
                    }
                }
            }
            .environmentObject(session)
            .preferredColorScheme(appearance.mode.colorScheme)
            .tint(appearance.accent.tint)
            .sheet(isPresented: $showingMicrosoftLogin) {
                NavigationStack {
                    SignInWebView()
                        .navigationTitle("Microsoft account")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { showingMicrosoftLogin = false }
                            }
                        }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(false)
                .environmentObject(session)
            }
            .onAppear {
                session.revalidatePersistedLogin()
                CloudCatalogService.refreshIfNeeded()
            }
            .onChange(of: session.isSignedIn) { _, signedIn in
                if signedIn { showingMicrosoftLogin = false }
            }
            .animation(.easeInOut(duration: 0.35), value: session.isSignedIn)
            .animation(.easeInOut(duration: 0.35), value: showIntro)
            .animation(.easeInOut(duration: 0.35), value: appearance.mode)
            .animation(.easeInOut(duration: 0.35), value: appearance.accent)
        }
    }
}
