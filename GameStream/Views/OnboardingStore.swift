import Foundation

enum OnboardingStore {
    static let introKey = "GameStream.introCompleted.v1"

    static var hasCompletedIntro: Bool {
        UserDefaults.standard.bool(forKey: introKey)
    }

    static func markIntroCompleted() {
        UserDefaults.standard.set(true, forKey: introKey)
    }
}
