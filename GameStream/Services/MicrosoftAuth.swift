import Foundation
import WebKit

enum MicrosoftAuth {
    /// Mobile Safari-style login. wreply must be HTTPS + explicit locale so
    /// Akamai is less likely to block the post-login landing (device showed
    /// Access Denied on http://www.xbox.com/en-IN/play?).
    static let loginURL = URL(string: "https://login.live.com/login.srf?wa=wsignin1.0&wp=MBI_SSL&wreply=https%3A%2F%2Fwww.xbox.com%2Fen-US%2Fplay&lc=1033&display=touch")!
    static let playURL = URL(string: "https://www.xbox.com/en-US/play")!

    /// Matches mobile Safari closely enough that Akamai/WAF treats the
    /// embedded WebView like a real browser instead of a bot client.
    static let safariUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"

    static let proofVersion = 2
    static let proofKey = "GameStream.microsoftAuthProof.v2"

    static func isLoginHost(_ raw: String) -> Bool {
        guard let host = URL(string: raw)?.host?.lowercased() else { return false }
        let exactHosts: Set<String> = [
            "login.live.com",
            "login.microsoftonline.com",
            "login.microsoft.com",
            "sisu.xboxlive.com",
            "account.live.com",
            "account.microsoft.com"
        ]
        return exactHosts.contains(host)
    }

    static func isXboxDestination(_ raw: String) -> Bool {
        guard let host = URL(string: raw)?.host?.lowercased() else { return false }
        if isLoginHost(raw) { return false }
        if host == "edgesuite.net" || host.hasSuffix(".edgesuite.net") { return false }
        return host == "xbox.com" || host.hasSuffix(".xbox.com")
            || host == "xboxlive.com" || host.hasSuffix(".xboxlive.com")
    }

    static func isAkamaiDenied(_ raw: String) -> Bool {
        let href = raw.lowercased()
        return href.contains("edgesuite.net")
            || href.contains("errors.edgesuite")
            || href.contains("access denied")
    }

    /// Upgrade http://www.xbox.com/... to https to avoid Akamai denying the HTTP form.
    static func httpsXboxURL(from url: URL) -> URL? {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let host = (comps.host ?? "").lowercased()
        guard host == "xbox.com" || host.hasSuffix(".xbox.com") else { return nil }
        if comps.scheme?.lowercased() == "https" { return nil }
        comps.scheme = "https"
        return comps.url
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
