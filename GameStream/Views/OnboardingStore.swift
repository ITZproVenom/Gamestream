import Foundation

enum OnboardingStore {
    static let introKey = "GameStream.introCompleted.v1"
    private static let legacyKeys = [
        "GameStream.introCompleted",
        "GameStream.introCompleted.v1"
    ]

    static var hasCompletedIntro: Bool {
        let defaults = UserDefaults.standard
        return legacyKeys.contains { defaults.bool(forKey: $0) }
    }

    static func markIntroCompleted() {
        UserDefaults.standard.set(true, forKey: introKey)
        UserDefaults.standard.set(true, forKey: "GameStream.introCompleted")
    }
}
