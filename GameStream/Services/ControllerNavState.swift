import Foundation
import Combine

/// One-shot events routed from `ControllerManager` (joysticks / A) into the
/// currently visible in-content UI (game grids). `token` increments on every
/// send so repeated identical actions still trigger `.onChange`.
@MainActor
final class ControllerNavState: ObservableObject {
    static let shared = ControllerNavState()

    @Published private(set) var token = 0
    @Published private(set) var action: ControllerGameNav?

    func send(_ action: ControllerGameNav) {
        self.action = action
        token &+= 1
    }
}

enum ControllerGameNav {
    case left, right, up, down
    case activate
}