import SwiftUI

/// Clean-slate application root: onboarding → Microsoft auth (locked) → AppShell.
struct AppRoot: View {
    @ObservedObject var session: SessionStore
    @ObservedObject var appearance: AppearanceStore
    @State private var showIntro = !OnboardingStore.hasCompletedIntro
    @State private var showingMicrosoftLogin = false
    @State private var didBootstrap = false

    var body: some View {
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
            .environmentObject(session)
        }
        .onAppear { bootstrapOnce() }
        .onChange(of: session.isSignedIn) { _, signedIn in
            if signedIn { showingMicrosoftLogin = false }
        }
        .animation(.easeInOut(duration: 0.35), value: session.isSignedIn)
        .animation(.easeInOut(duration: 0.35), value: showIntro)
    }

    private func bootstrapOnce() {
        guard !didBootstrap else { return }
        didBootstrap = true
        if session.isStreaming {
            session.exitStreamToHub()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            CloudCatalogService.refreshIfNeeded()
        }
        session.revalidatePersistedLogin()
    }
}
