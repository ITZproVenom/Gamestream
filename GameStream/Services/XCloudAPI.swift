import Foundation

/// The first step towards a native player: talking to Xbox Cloud Gaming
/// directly instead of driving the website.
///
/// This is the first step: it exchanges the account's XSTS token for a
/// cloud-gaming token and reads back the regional endpoints the account may
/// use. `XCloudSession` spends that token, and `NativeStreamPeer` negotiates
/// media against the session it provisions.
///
/// Everything here uses the signed-in account's own token, the same one the
/// website uses in the browser.
actor XCloudAPI {
    static let shared = XCloudAPI()

    struct Failure: LocalizedError {
        let step: String
        let detail: String
        var errorDescription: String? { "\(step): \(detail)" }
    }

    struct Login: Sendable {
        var gsToken: String
        var regions: [Region]
        var durationSeconds: Double

        /// The regions the service may move the session to if the chosen one
        /// cannot take it, in its own priority order. The default region and
        /// anything marked -1 are left out, which is what the site does.
        var fallbackRegionNames: [String] {
            regions
                .filter { !$0.isDefault && $0.fallbackPriority >= 0 }
                .sorted { $0.fallbackPriority < $1.fallbackPriority }
                .map(\.name)
        }
    }

    struct Region: Sendable {
        var name: String
        var baseURI: String
        var isDefault: Bool
        /// Where this region sits in the service's own fallback order.
        /// -1 means "never fall back to me".
        var fallbackPriority: Int
    }

    private static let loginURL = URL(
        string: "https://xgpuweb.gssv-play-prod.xboxlive.com/v2/login/user"
    )!

    /// Exchanges the XSTS token for a cloud-gaming token and the list of
    /// regional endpoints the account may use.
    func login(xstsToken: String) async throws -> Login {
        var request = URLRequest(url: Self.loginURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "token": xstsToken,
            "offeringId": "xgpuweb"
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Failure(step: "login", detail: "no HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            // The status code alone does not distinguish "your token expired"
            // from "this account has no cloud gaming", and those need
            // different answers from the person reading the message.
            let body = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let reason = body.isEmpty ? "" : " — " + String(body.prefix(200))
            await MainActor.run {
                AppLog.shared.error("native", "login: HTTP \(http.statusCode)\(reason)")
            }
            throw Failure(step: "login",
                          detail: http.statusCode == 401 || http.statusCode == 403
                              ? "the account was refused cloud gaming (HTTP "
                                + "\(http.statusCode))\(reason)"
                              : "HTTP \(http.statusCode)\(reason)")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(step: "login", detail: "the response was not an object")
        }
        guard let gsToken = object["gsToken"] as? String, !gsToken.isEmpty else {
            throw Failure(step: "login", detail: "no gsToken in the response")
        }

        let regions = (object["offeringSettings"] as? [String: Any])
            .flatMap { $0["regions"] as? [[String: Any]] } ?? []
        let parsed = regions.compactMap { entry -> Region? in
            guard let name = entry["name"] as? String,
                  let base = entry["baseUri"] as? String else { return nil }
            return Region(name: name,
                          baseURI: base,
                          isDefault: entry["isDefault"] as? Bool ?? false,
                          fallbackPriority: entry["fallbackPriority"] as? Int ?? -1)
        }

        let login = Login(
            gsToken: gsToken,
            regions: parsed,
            durationSeconds: (object["durationInSeconds"] as? Double) ?? 0
        )
        // The connection check has no business timing the website's CDN once
        // the account's own streaming region is known.
        if let region = parsed.first(where: \.isDefault) ?? parsed.first {
            let base = region.baseURI
            let name = region.name
            await MainActor.run {
                NetworkCheck.shared.rememberRegion(baseURI: base)
                AppLog.shared.info("native", "cloud token for region \(name)")
            }
        }
        return login
    }

    /// A human-readable account of how far a native session can currently
    /// get. This is the honest way to find out whether the rest is feasible
    /// before writing a WebRTC client against an endpoint that may refuse us.
    func probe(xstsToken: String) async -> String {
        do {
            let login = try await login(xstsToken: xstsToken)
            var lines = ["Cloud-gaming token obtained."]
            if login.durationSeconds > 0 {
                lines.append("Valid for \(Int(login.durationSeconds / 60)) minutes.")
            }
            if login.regions.isEmpty {
                lines.append("No regions were returned.")
            } else {
                let names = login.regions.map { region in
                    region.name + (region.isDefault ? " (default)" : "")
                }
                lines.append("Regions: \(names.joined(separator: ", ")).")
            }
            lines.append("Session provisioning and the native WebRTC player are "
                         + "built; the bolt button on a game's page uses them.")
            return lines.joined(separator: " ")
        } catch let failure as Failure {
            return "Native access failed at \(failure.step) — \(failure.detail)."
        } catch {
            return "Native access failed: \(error.localizedDescription)"
        }
    }
}
