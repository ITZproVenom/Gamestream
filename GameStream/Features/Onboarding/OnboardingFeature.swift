import SwiftUI

struct OnboardingIntroView: View {
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 28) {
                Spacer()
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("GameStream")
                    .font(.largeTitle.weight(.bold))
                Text("Xbox Cloud Gaming, rebuilt for Liquid Glass.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.glassProminent)
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
        }
    }
}

struct OnboardingWelcomeView: View {
    let onSignIn: () -> Void

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 24) {
                Spacer()
                Text("Sign in with Microsoft")
                    .font(.title.weight(.bold))
                Text("Your Xbox session powers play, search, and resume. Auth uses the locked WebView core.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                Spacer()
                Button(action: onSignIn) {
                    Label("Microsoft account", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.glassProminent)
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
        }
    }
}
