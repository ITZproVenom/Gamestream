import SwiftUI

@main
struct GameStreamApp: App {
    init() {
        // Bounded HTTP cache — posters + catalog without unbounded growth
        URLCache.shared = URLCache(
            memoryCapacity: 24 * 1024 * 1024,
            diskCapacity: 96 * 1024 * 1024,
            diskPath: "gamestream-url-cache"
        )
    }

    // SessionStore is owned by the scene. AppearanceStore is a @MainActor singleton —
    // resolve it from App.body (main actor) and pass it in. Never wrap singletons in
    // @StateObject, never put @ObservedObject on App, and never default-init
    // @ObservedObject with AppearanceStore.shared (that init is not MainActor-isolated).
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            GameStreamRootView(session: session, appearance: AppearanceStore.shared)
        }
    }
}

private struct GameStreamRootView: View {
    @ObservedObject var session: SessionStore
    @ObservedObject var appearance: AppearanceStore
    @State private var showIntro = !OnboardingStore.hasCompletedIntro
    @State private var showingMicrosoftLogin = false
    @State private var didBootstrap = false

    var body: some View {
        Group {
            if session.isSignedIn {
                RootView()
            } else if showIntro {
                IntroView {
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
            bootstrapOnce()
        }
        .onChange(of: session.isSignedIn) { _, signedIn in
            if signedIn { showingMicrosoftLogin = false }
        }
        .animation(.easeInOut(duration: 0.35), value: session.isSignedIn)
        .animation(.easeInOut(duration: 0.35), value: showIntro)
        .animation(.easeInOut(duration: 0.35), value: appearance.mode)
        .animation(.easeInOut(duration: 0.35), value: appearance.accent)
    }

    private func bootstrapOnce() {
        guard !didBootstrap else { return }
        didBootstrap = true
        // Never leave a stuck streaming flag from a previous kill.
        if session.isStreaming {
            session.exitStreamToHub()
        }
        // WebKit cookie store must not initialize during the first SwiftUI frame.
        DispatchQueue.main.async {
            session.revalidatePersistedLogin()
            CloudCatalogService.refreshIfNeeded()
        }
    }
}
