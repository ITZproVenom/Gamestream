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

    // SessionStore is owned by the scene. AppearanceStore is a process-wide singleton —
    // never wrap singletons in @StateObject (that pattern crashes on launch).
    @StateObject private var session = SessionStore()
    @ObservedObject private var appearance = AppearanceStore.shared
    @State private var showIntro = !OnboardingStore.hasCompletedIntro
    @State private var showingMicrosoftLogin = false
    @State private var didBootstrap = false

    var body: some Scene {
        WindowGroup {
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
    }

    private func bootstrapOnce() {
        guard !didBootstrap else { return }
        didBootstrap = true
        // Never leave a stuck streaming flag from a previous kill.
        if session.isStreaming {
            session.exitStreamToHub()
        }
        session.revalidatePersistedLogin()
        // Defer network/catalog so the first frame never races secondary services.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            CloudCatalogService.refreshIfNeeded()
        }
    }
}
