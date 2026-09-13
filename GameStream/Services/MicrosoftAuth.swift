import Foundation
import WebKit

enum MicrosoftAuth {
    static let loginURL = URL(string: "https://login.live.com/login.srf?wa=wsignin1.0&wp=MBI_SSL&wreply=https%3A%2F%2Fwww.xbox.com%2Fplay&lc=1033")!
    static let playURL = URL(string: "https://www.xbox.com/play")!

    static let proofVersion = 2
    static let proofKey = "GameStream.microsoftAuthProof.v2"

    static func isLoginHost(_ raw: String) -> Bool {
        let href = raw.lowercased()
        return href.contains("login.live.com")
            || href.contains("login.microsoftonline.com")
            || href.contains("login.microsoft.com")
            || href.contains("sisu.xboxlive.com")
    }

    static func isXboxDestination(_ raw: String) -> Bool {
        let href = raw.lowercased()
        if isLoginHost(href) { return false }
        return href.contains("xbox.com") || href.contains("xboxlive.com")
    }

    /// Presence on xbox.com/play is not proof of login.
    static func cookiesIndicateMicrosoftAuth(_ cookies: [HTTPCookie]) -> Bool {
        let authNames: Set<String> = [
            "mspauth", "mspprof", "rpssecauth", "__host-msaauthp",
            "__host-msauth", "xid", "xboxlive", "xbl"
        ]
        for cookie in cookies {
            let name = cookie.name.lowercased()
            let domain = cookie.domain.lowercased()
            let value = cookie.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count > 8 else { continue }
            if authNames.contains(name) { return true }
            if name.contains("mspauth") || name.contains("rpssec") { return true }
            if (domain.contains("login.live.com") || domain.contains("live.com"))
                && (name.contains("auth") || name.contains("token")) {
                return true
            }
            if domain.contains("xboxlive.com") && (name.contains("auth") || name.contains("token") || name.contains("xbl")) {
                return true
            }
        }
        return false
    }

    static func fetchAuthCookies(completion: @escaping ([HTTPCookie]) -> Void) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            completion(cookies)
        }
    }
}
