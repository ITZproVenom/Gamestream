import Foundation

extension SessionStore {
    func syncPlayActivity(streaming: Bool) {
        if streaming, let game = currentGame {
            PlayActivityStore.shared.begin(id: game.id, title: game.title, slug: game.slug)
        } else if !streaming {
            PlayActivityStore.shared.end()
        }
    }
}
