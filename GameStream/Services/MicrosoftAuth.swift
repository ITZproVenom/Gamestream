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

    /// True only when a real xbox.com / xboxlive.com SESSION cookie is present
    /// (RPSTAuth, XBL3, XBLX, xid, ...). That is what makes xbox.com treat the
    /// WebView as signed in. login.live.com cookies alone are NOT sufficient —
    /// without this the player webview lands "not logged in" and dumps the user
    /// to the store/sign-in page.
    static func cookiesIndicateXboxSession(_ cookies: [HTTPCookie]) -> Bool {
        for cookie in cookies {
            let name = cookie.name.lowercased()
            let domain = cookie.domain.lowercased()
            let value = cookie.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count > 8 else { continue }
            let onXbox = domain.contains("xbox.com") || domain.contains("xboxlive.com")
            guard onXbox else { continue }
            if ["rpstauth", "xbl3", "xblx", "xid", "xbl", "xbox-auth-token"].contains(name) {
                return true
            }
            if name.hasPrefix("rpst") || name.contains("xbl") || name.contains("xid") {
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
