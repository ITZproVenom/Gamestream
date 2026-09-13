import SwiftUI

@main
struct GameStreamApp: App {
    @StateObject private var session = SessionStore()
    @State private var showIntro = !OnboardingStore.hasCompletedIntro

    var body: some Scene {
        WindowGroup {
            Group {
                if showIntro {
                    IntroView {
                        withAnimation(.easeInOut(duration: 0.45)) {
                            showIntro = false
                        }
                    }
                } else if !session.isSignedIn {
                    WelcomeView()
                } else {
                    RootView()
                }
            }
            .environmentObject(session)
            .preferredColorScheme(.dark)
            .animation(.easeInOut(duration: 0.35), value: session.isSignedIn)
            .animation(.easeInOut(duration: 0.35), value: showIntro)
        }
    }
}
