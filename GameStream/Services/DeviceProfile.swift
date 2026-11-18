import Foundation

/// The device the app says it is.
///
/// Xbox's cloud decides what it offers from the account, the region and
/// the title, and most of that is the service's business. What the client
/// does decide is what the *site* hands back: the pages ask for their
/// catalogue with the user agent of whatever is asking, and the same
/// applies to the app's own requests.
///
/// A television is a different client from a desktop browser, and the
/// service sometimes answers them differently. The same profiles the
/// enhancement script offers are used here, so a title that will not appear
/// for one profile can be asked for with another.
enum DeviceProfile: String, CaseIterable, Identifiable, Sendable {
    case windows
    case smartTV
    case tizenTV
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .windows: return "Windows PC"
        case .smartTV: return "Smart TV"
        case .tizenTV: return "Tizen TV"
        case .custom: return "Custom"
        }
    }

    var detail: String {
        switch self {
        case .windows:
            return "What a desktop browser on Windows sends. The usual choice."
        case .smartTV:
            return "A television. The service sometimes answers a television differently."
        case .tizenTV:
            return "A Tizen television, the kind a Samsung or LG makes."
        case .custom:
            return "Anything you type. Some clients are told to send something else."
        }
    }

    /// The user agent for this profile.
    ///
    /// The television profiles are the ones the enhancement script uses, so
    /// the app and the script agree on what the page says it is.
    func userAgent(custom: String = "") -> String {
        switch self {
        case .windows:
            return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                + "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        case .smartTV:
            return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                + "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Smart-TV"
        case .tizenTV:
            return "Mozilla/5.0 (SMART-TV; LINUX; Tizen 7.0) AppleWebKit/537.36 "
                + "(KHTML, like Gecko) 140.0.3485.54/7.0 TV Safari/537.36 "
                + "FC4A1DA2-711C-4E9C-BC7F-047AF8A672EA"
        case .custom:
            return custom.isEmpty
                ? "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                    + "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
                : custom
        }
    }
}
