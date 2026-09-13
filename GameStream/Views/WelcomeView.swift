import SwiftUI

struct WelcomeView: View {
    var onSignIn: () -> Void

    var body: some View {
        ZStack {
            AnimatedBackground()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                VStack(spacing: 16) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 48, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .accessibilityHidden(true)

                    Text("GameStream")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text("Welcome")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("Sign in with Microsoft to open GameHub, Xbox Cloud Gaming, and Better xCloud.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding(26)
                .frame(maxWidth: 520)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(.horizontal, 24)

                Button(action: onSignIn) {
                    HStack(spacing: 10) {
                        Image(systemName: "person.badge.key.fill")
                        Text("Sign in with Microsoft")
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.glassProminent)
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .frame(maxWidth: 520)
                .accessibilityLabel("Sign in with Microsoft")

                Text("Uses Microsoft’s real sign-in page. GameStream never stores your password.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
                    .padding(.top, 14)

                Spacer()
            }
        }
    }
}
