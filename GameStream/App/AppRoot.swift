import SwiftUI

/// Clean-slate application root: onboarding → Microsoft auth (locked) → AppShell.
/// Launch loading stays above the app while catalog data initializes.
struct AppRoot: View {
    @ObservedObject var session: SessionStore
    @ObservedObject var appearance: AppearanceStore
    @State private var showIntro = !OnboardingStore.hasCompletedIntro
    @State private var showingMicrosoftLogin = false
    @State private var didBootstrap = false
    @State private var showOpeningIntro = true
    @State private var catalogReady = false

    var body: some View {
        ZStack {
            Group {
                if session.isSignedIn {
                    AppShell()
                } else if showIntro {
                    OnboardingIntroView {
                        OnboardingStore.markIntroCompleted()
                        withAnimation(.easeInOut(duration: 0.45)) {
                            showIntro = false
                        }
                    }
                } else {
                    OnboardingWelcomeView {
                        DiagnosticsStore.shared.record(event: "login_started", feature: "auth")
                        showingMicrosoftLogin = true
                    }
                }
            }

            if showOpeningIntro {
                OpeningIntroView(isReady: catalogReady) {
                    withAnimation(.easeInOut(duration: 0.32)) {
                        showOpeningIntro = false
                    }
                }
                .zIndex(100)
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
                            Button("Close") {
                                DiagnosticsStore.shared.record(
                                    event: "login_failed",
                                    feature: "auth",
                                    properties: ["reason": "dismissed"],
                                    errorCategory: "user_dismissed"
                                )
                                showingMicrosoftLogin = false
                            }
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .environmentObject(session)
        }
        .onAppear { bootstrapOnce() }
        .onChange(of: session.isSignedIn) { _, signedIn in
            if signedIn {
                showingMicrosoftLogin = false
            }
        }
        .animation(.easeInOut(duration: 0.35), value: session.isSignedIn)
        .animation(.easeInOut(duration: 0.35), value: showIntro)
    }

    private func bootstrapOnce() {
        guard !didBootstrap else { return }
        didBootstrap = true
        DiagnosticsStore.shared.noteAppLaunch()
        if session.isStreaming {
            session.exitStreamToHub()
        }
        CloudCatalogService.refreshIfNeeded {
            Task { @MainActor in
                catalogReady = true
            }
        }
        session.revalidatePersistedLogin()
    }
}
