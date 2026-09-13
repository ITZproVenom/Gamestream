import SwiftUI

@main
struct GameStreamApp: App {
    @StateObject private var session = SessionStore()
    @State private var showIntro = !OnboardingStore.hasCompletedIntro
    @State private var showingMicrosoftLogin = false

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
            .preferredColorScheme(.dark)
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
            .onChange(of: session.isSignedIn) { _, signedIn in
                if signedIn { showingMicrosoftLogin = false }
            }
            .animation(.easeInOut(duration: 0.35), value: session.isSignedIn)
            .animation(.easeInOut(duration: 0.35), value: showIntro)
        }
    }
}
