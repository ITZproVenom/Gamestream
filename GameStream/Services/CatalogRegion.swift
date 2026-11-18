import Foundation

/// Which region's catalogue the app asks the cloud for.
///
/// Xbox does not offer every title in every market: the catalogue a
/// player is shown depends on where the request appears to come from. The
/// enhancement script has always been able to answer for another region,
/// by sending the login request with the address of a regional cloud
/// server, and the app can ask for the same thing instead of making the
/// player find the switch in someone else's menu.
///
/// This does not change what the account owns, and it does not unlock
/// anything that is not offered anywhere - a title that no region hosts
/// stays unstreamable. What it changes is which region's *catalogue* the
/// app is shown, and therefore which of the titles that are hosted
/// somewhere can be found.
enum CatalogRegion: String, CaseIterable, Identifiable, Sendable {
    case defaultRegion
    case unitedStates
    case japan
    case korea
    case brazil
    case poland

    var id: String { rawValue }

    var title: String {
        switch self {
        case .defaultRegion: return "Where I am"
        case .unitedStates: return "United States"
        case .japan: return "Japan"
        case .korea: return "South Korea"
        case .brazil: return "Brazil"
        case .poland: return "Poland"
        }
    }

    /// The code the enhancement script uses for the region, and the address
    /// of that region's cloud server that it answers with.
    var bypassCode: String {
        switch self {
        case .defaultRegion: return "off"
        case .unitedStates: return "us"
        case .japan: return "jp"
        case .korea: return "kr"
        case .brazil: return "br"
        case .poland: return "pl"
        }
    }

    /// The continent the region belongs to, which is how the script's own
    /// region setting is written.
    var continent: String {
        switch self {
        case .defaultRegion: return "default"
        case .unitedStates: return "america-north"
        case .brazil: return "america-south"
        case .japan, .korea: return "asia"
        case .poland: return "europe"
        }
    }

    var detail: String {
        switch self {
        case .defaultRegion:
            return "The catalogue for the country the phone is in."
        default:
            return "The catalogue for \(title). Some titles are offered in one "
                + "market and not another."
        }
    }
}
