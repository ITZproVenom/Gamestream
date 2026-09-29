import Foundation

/// The second step towards a native player: asking Xbox Cloud Gaming for a
/// real session instead of letting the website do it.
///
/// `XCloudAPI` gets us a cloud-gaming token. This type spends it. The service
/// treats a session as a small state machine hanging off a path it hands back,
/// so the shape of the work is: ask for a session, poll until the queue lets
/// go of it, read where the server lives, then either negotiate media or give
/// the session back.
///
/// Nothing here decodes video: this is the HTTP half of a session, kept apart
/// from the peer connection that supplies the payloads its negotiation calls
/// carry. Every call is
/// made with the signed-in account's own token.
///
/// A provisioned session occupies one of the account's cloud slots, so
/// `release` is not optional politeness — anything that provisions must give
/// the session back, including on the failure paths.
actor XCloudSession {
    static let shared = XCloudSession()

    struct Failure: LocalizedError {
        let step: String
        let detail: String
        var errorDescription: String? { "\(step): \(detail)" }
    }

    /// A session handle. `path` is service-chosen and already absolute
    /// relative to the region host, so it is never built by hand here.
    struct Handle: Sendable {
        var baseURI: String
        var path: String
        var url: URL? { URL(string: baseURI + path) }
    }

    /// Where a session is in the queue. The service uses a wide vocabulary of
    /// state strings and adds to it, so the raw value is kept and the cases
    /// are only a reading of it.
    struct State: Sendable {
        var raw: String
        var detail: String?
        var queuePosition: Int?
        var estimatedWaitSeconds: Int?

        var isReady: Bool {
            let value = raw.lowercased()
            return value == "provisioned" || value == "readytoconnect"
        }

        var isTerminal: Bool {
            let value = raw.lowercased()
            return value == "failed" || value == "canceled" || value == "cancelled"
        }
    }

    /// The reachable address of the machine running the game.
    struct ServerDetails: Sendable {
        var ipV4: String?
        var portV4: Int?
        var ipV6: String?
        var portV6: Int?

        var summary: String {
            var parts: [String] = []
            if let ipV4 { parts.append("IPv4 \(ipV4)\(portV4.map { ":\($0)" } ?? "")") }
            if let ipV6 { parts.append("IPv6 available") }
            return parts.isEmpty ? "no address returned" : parts.joined(separator: ", ")
        }
    }

    // MARK: - Provisioning

    /// What the cloud service knows about one title.
    ///
    /// The store and the cloud service do not use the same identifier. A
    /// game page carries a display-catalogue ProductId, while a session is
    /// asked for by the cloud service's own titleId, and only this lookup
    /// relates the two.
    struct TitleInfo: Sendable {
        var titleId: String
        var name: String?
        var supportsTouch: Bool
        var supportsMouseKeyboard: Bool
    }

    /// Translates a store ProductId into the titleId a session needs.
    func titleInfo(productId: String, login: XCloudAPI.Login) async throws -> TitleInfo {
        guard let base = preferredRegion(of: login)?.baseURI, !base.isEmpty,
              let url = URL(string: base + "/v2/titles") else {
            throw Failure(step: "title", detail: "the account has no usable region")
        }
        let (data, _) = try await send(
            request(url: url, method: "POST", token: login.gsToken,
                    body: ["alternateIds": [productId], "alternateIdType": "productId"]),
            step: "title"
        )
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = object["results"] as? [[String: Any]],
              let first = results.first else {
            throw Failure(step: "title", detail: "the service returned no title for \(productId)")
        }
        guard let titleId = first["titleId"] as? String, !titleId.isEmpty else {
            throw Failure(step: "title",
                          detail: "the service knows \(productId) but gave it no title id, "
                                + "which usually means it cannot be streamed to this account")
        }
        let details = first["details"] as? [String: Any]
        let inputs = details?["supportedInputTypes"] as? [String] ?? []
        let info = TitleInfo(
            titleId: titleId,
            name: details?["productTitle"] as? String,
            supportsTouch: details?["hasTouchSupport"] as? Bool ?? false,
            supportsMouseKeyboard: inputs.contains("MKB") || inputs.contains("Keyboard")
        )
        note("title: \(productId) is title \(titleId)"
             + (info.name.map { " (\($0))" } ?? ""))
        return info
    }

    /// Asks the region for a session for one title.
    ///
    /// The settings block describes the client to the service. The values are
    /// a plain description of what this app is and can do; the service uses
    /// them to pick a transport and a keyboard layout, not to gate access.
    func provision(login: XCloudAPI.Login,
                   titleId: String,
                   region: XCloudAPI.Region? = nil,
                   osName: String = "windows") async throws -> Handle {
        let endpoint = region ?? preferredRegion(of: login)
        guard let base = endpoint?.baseURI, !base.isEmpty else {
            note("provision: the account has no usable region", level: .error)
            throw Failure(step: "provision", detail: "the account has no usable region")
        }
        note("provision: asking \(endpoint?.name ?? "?") (\(base)) for title \(titleId) as \(osName)")
        guard let url = URL(string: base + "/v5/sessions/cloud/play") else {
            throw Failure(step: "provision", detail: "the region returned an unusable address")
        }

        let body: [String: Any] = [
            "titleId": titleId,
            "systemUpdateGroup": "",
            "serverId": "",
            "fallbackRegionNames": login.fallbackRegionNames,
            "clientSessionId": UUID().uuidString.lowercased(),
            "settings": [
                // The service checks this string against a list. Anything it
                // does not recognise is refused outright, which is why this
                // is the site's exact value rather than a tidier one.
                "nanoVersion": "V3;WebrtcTransport.dll",
                "enableTextToSpeech": false,
                "magnifier": false,
                "highContrast": 0,
                "locale": Locale.current.identifier.replacingOccurrences(of: "_", with: "-"),
                // We do exchange ICE over /ice, but so does the site with
                // this set to false: the flag selects a different transport
                // negotiation, not whether candidates are traded.
                "useIceConnection": false,
                "timezoneOffsetMinutes": TimeZone.current.secondsFromGMT() / 60,
                "sdkType": "web",
                "osName": osName,
                "enableOptionalDataCollection": false
            ]
        ]

        // The service reads the ceiling of what it will send from the device
        // description, not from the SDP: an unrecognised platform is offered
        // a phone-sized stream. `osName` is the knob that actually moves it.
        var post = request(url: url, method: "POST", token: login.gsToken, body: body)
        post.setValue(Self.deviceInfo(osName: osName), forHTTPHeaderField: "x-ms-device-info")
        let (data, http) = try await send(post, step: "provision")
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(step: "provision", detail: "HTTP \(http.statusCode) with no readable body")
        }
        guard let path = object["sessionPath"] as? String, !path.isEmpty else {
            let reason = (object["errorDetails"] as? [String: Any])?["message"] as? String
            note("provision: no session path. Response keys: "
                 + object.keys.sorted().joined(separator: ", "), level: .error)
            throw Failure(step: "provision",
                          detail: reason ?? "no session path in the response (HTTP \(http.statusCode))")
        }
        note("provision: granted \(path)")
        return Handle(baseURI: base, path: path)
    }

    /// The platform name the service recognises for a wanted resolution.
    /// These are the service's own buckets, not ours: it has no iOS bucket,
    /// and an unknown one lands in the smallest.
    static func osName(forResolution preference: String) -> String {
        switch preference {
        case "720p": return "android"
        default: return "windows"
        }
    }

    /// The device description that accompanies a session request. It has to
    /// agree with `osName`, or the service trusts neither.
    private static func deviceInfo(osName: String) -> String {
        let info: [String: Any] = [
            "appInfo": ["env": [
                "clientAppId": Bundle.main.bundleIdentifier ?? "gamestream",
                "clientAppType": "native",
                "clientAppVersion": AppInfo.shortVersion,
                "clientSdkVersion": "10.3.7",
                "httpEnvironment": "prod",
                "sdkInstallId": ""
            ]],
            "dev": [
                "os": ["name": osName, "ver": "22631.2715", "platform": "desktop"],
                "hw": ["make": "Microsoft", "model": "unknown", "sdktype": "web"],
                "browser": ["browserName": "chrome", "browserVersion": "140.0.3485.54"],
                "displayInfo": [
                    "dimensions": ["widthInPixels": 1920, "heightInPixels": 1080],
                    "pixelDensity": ["dpiX": 1, "dpiY": 1]
                ]
            ]
        ]
        let data = (try? JSONSerialization.data(withJSONObject: info)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Reads one session's current state.
    func state(of handle: Handle, token: String) async throws -> State {
        guard let url = URL(string: handle.baseURI + handle.path + "/state") else {
            throw Failure(step: "state", detail: "unusable session address")
        }
        let (data, _) = try await send(request(url: url, method: "GET", token: token), step: "state")
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(step: "state", detail: "the response was not an object")
        }
        let waiting = object["waitTime"] as? [String: Any]
        return State(
            raw: (object["state"] as? String) ?? "Unknown",
            detail: object["detailedSessionState"] as? String
                ?? (object["errorDetails"] as? [String: Any])?["message"] as? String,
            queuePosition: waiting?["position"] as? Int,
            estimatedWaitSeconds: waiting?["estimatedTotalWaitTimeInSeconds"] as? Int
        )
    }

    /// Polls until the session is ready, fails, or the deadline passes.
    ///
    /// The interval is deliberately unhurried: a queued session can sit for
    /// minutes and polling it faster does not move it up.
    func waitUntilReady(_ handle: Handle,
                        token: String,
                        timeout: TimeInterval = 120,
                        onState: (@Sendable (State) -> Void)? = nil) async throws -> State {
        let deadline = Date().addingTimeInterval(timeout)
        var last = State(raw: "Unknown", detail: nil, queuePosition: nil, estimatedWaitSeconds: nil)
        while Date() < deadline {
            last = try await state(of: handle, token: token)
            note("state: \(last.raw)"
                 + (last.detail.map { " (\($0))" } ?? "")
                 + (last.queuePosition.map { " queue \($0)" } ?? ""))
            onState?(last)
            if last.isReady { return last }
            if last.isTerminal {
                throw Failure(step: "provision",
                              detail: last.detail.map { "\(last.raw) — \($0)" } ?? last.raw)
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { throw CancellationError() }
        }
        throw Failure(step: "provision", detail: "still \(last.raw) after \(Int(timeout))s")
    }

    /// Reads the connection details of a ready session.
    func serverDetails(for handle: Handle, token: String) async throws -> ServerDetails {
        guard let url = URL(string: handle.baseURI + handle.path + "/configuration") else {
            throw Failure(step: "configuration", detail: "unusable session address")
        }
        let (data, _) = try await send(request(url: url, method: "GET", token: token),
                                       step: "configuration")
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(step: "configuration", detail: "the response was not an object")
        }
        // The details arrive as JSON inside a JSON string more often than not.
        var server = object["serverDetails"] as? [String: Any]
        if server == nil, let text = object["serverDetails"] as? String,
           let nested = text.data(using: .utf8) {
            server = try? JSONSerialization.jsonObject(with: nested) as? [String: Any]
        }
        guard let server else {
            throw Failure(step: "configuration", detail: "no server details in the response")
        }
        return ServerDetails(
            ipV4: server["ipV4Address"] as? String ?? server["ipAddress"] as? String,
            portV4: server["ipV4Port"] as? Int ?? server["port"] as? Int,
            ipV6: server["ipV6Address"] as? String,
            portV6: server["ipV6Port"] as? Int
        )
    }

    /// Keeps an idle session from being reclaimed while it is being set up.
    @discardableResult
    func keepAlive(_ handle: Handle, token: String) async -> Bool {
        guard let url = URL(string: handle.baseURI + handle.path + "/keepalive") else { return false }
        let result = try? await send(request(url: url, method: "POST", token: token, body: [:]),
                                     step: "keepalive")
        return result != nil
    }

    /// Gives the session back. Called on every exit path, including errors.
    @discardableResult
    func release(_ handle: Handle, token: String) async -> Bool {
        guard let url = handle.url else { return false }
        let result = try? await send(request(url: url, method: "DELETE", token: token),
                                     step: "release")
        return result != nil
    }

    // MARK: - Media negotiation

    /// Hands the service our SDP offer and reads back its answer.
    func exchangeOffer(_ sdp: String, on handle: Handle, token: String) async throws -> String {
        guard let url = URL(string: handle.baseURI + handle.path + "/sdp") else {
            throw Failure(step: "sdp", detail: "unusable session address")
        }
        let payload: [String: Any] = [
            "messageType": "offer",
            "sdp": sdp,
            "configuration": [
                "containerizeVideo": false,
                "requestedH264Profile": 2,
                "chatConfiguration": [
                    "bytesPerSample": 2,
                    "expectedClipDurationMs": 20,
                    "format": ["codec": "opus", "params": "musicband"],
                    "numChannels": 1,
                    "sampleFrequencyHz": 24000
                ]
            ]
        ]
        _ = try await send(request(url: url, method: "POST", token: token, body: payload),
                           step: "sdp")
        return try await pollExchange(url: url, token: token, step: "sdp")
    }

    /// Hands over our ICE candidates and reads back the service's.
    func exchangeCandidates(_ candidates: [[String: Any]],
                            on handle: Handle,
                            token: String) async throws -> String {
        guard let url = URL(string: handle.baseURI + handle.path + "/ice") else {
            throw Failure(step: "ice", detail: "unusable session address")
        }
        let encoded = String(
            data: try JSONSerialization.data(withJSONObject: candidates),
            encoding: .utf8
        ) ?? "[]"
        _ = try await send(
            request(url: url, method: "POST", token: token,
                    body: ["messageType": "iceCandidate", "candidate": encoded]),
            step: "ice"
        )
        return try await pollExchange(url: url, token: token, step: "ice")
    }

    /// Both negotiation endpoints answer asynchronously: the POST is only the
    /// handoff, and the reply appears on a later GET.
    private func pollExchange(url: URL, token: String, step: String) async throws -> String {
        for _ in 0..<20 {
            let (data, http) = try await send(request(url: url, method: "GET", token: token),
                                              step: step)
            if http.statusCode == 200,
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let body = object["exchangeResponse"] as? String, !body.isEmpty {
                return body
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { throw CancellationError() }
        }
        throw Failure(step: step, detail: "the service never answered")
    }

    // MARK: - Verification

    /// Provisions a session, reports how far it got, and always gives it
    /// back. This is how we find out whether the native path is real without
    /// having a player to point at it.
    func probe(login: XCloudAPI.Login,
               productId: String,
               onProgress: @Sendable @escaping (String) -> Void) async -> String {
        var handle: Handle?
        defer {
            if let handle {
                let token = login.gsToken
                Task.detached { _ = await XCloudSession.shared.release(handle, token: token) }
            }
        }
        do {
            onProgress("Looking up the cloud title…")
            let title = try await titleInfo(productId: productId, login: login)
            onProgress("Asking for a session…")
            let created = try await provision(login: login, titleId: title.titleId)
            handle = created

            var lines = ["\(productId) is cloud title \(title.titleId).", "Session granted."]
            let ready = try await waitUntilReady(created, token: login.gsToken) { state in
                if let position = state.queuePosition {
                    onProgress("Queued at position \(position)…")
                } else {
                    onProgress("\(state.raw)…")
                }
            }
            lines.append("Reached \(ready.raw).")

            onProgress("Reading the server address…")
            let server = try await serverDetails(for: created, token: login.gsToken)
            lines.append("Server: \(server.summary).")
            lines.append("Released the session. The native player negotiates media "
                         + "against a session like this one.")
            return lines.joined(separator: " ")
        } catch let failure as Failure {
            return "Native session failed at \(failure.step) — \(failure.detail)."
        } catch is CancellationError {
            return "Cancelled."
        } catch {
            return "Native session failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Plumbing

    private func preferredRegion(of login: XCloudAPI.Login) -> XCloudAPI.Region? {
        login.regions.first(where: \.isDefault) ?? login.regions.first
    }

    private func request(url: URL,
                         method: String,
                         token: String,
                         body: [String: Any]? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.correlationVector(), forHTTPHeaderField: "MS-CV")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func send(_ request: URLRequest, step: String) async throws -> (Data, HTTPURLResponse) {
        let where_ = (request.httpMethod ?? "GET") + " " + (request.url?.path ?? "?")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            note("\(step): \(where_) could not be reached: \(error.localizedDescription)", level: .error)
            throw Failure(step: step, detail: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            note("\(step): \(where_) answered with no HTTP response", level: .error)
            throw Failure(step: step, detail: "no HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            // The body of a rejection is the only place the service says why,
            // so it belongs in the error rather than being thrown away.
            let reason = Self.readableBody(data)
            note("\(step): \(where_) -> HTTP \(http.statusCode)"
                 + (reason.isEmpty ? "" : " \(reason)"), level: .error)
            throw Failure(step: step,
                          detail: "HTTP \(http.statusCode)" + (reason.isEmpty ? "" : " — \(reason)"))
        }
        note("\(step): \(where_) -> HTTP \(http.statusCode), \(data.count) bytes")
        return (data, http)
    }

    /// A short, readable version of a response body for an error message.
    /// Long bodies are trimmed: the useful part of a service rejection is at
    /// the front, and a failure card has to stay readable.
    private static func readableBody(_ data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let details = object["errorDetails"] as? [String: Any]
            if let message = details?["message"] as? String ?? object["message"] as? String
                ?? object["error"] as? String {
                return message
            }
        }
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty { return "" }
        return text.count > 300 ? String(text.prefix(300)) + "…" : text
    }

    /// The session layer used to log nothing at all, so a failed native
    /// stream left no trace in Diagnostics and the export was useless for
    /// working out what went wrong. Every step now records itself under the
    /// `native` category.
    private nonisolated func note(_ message: String, level: AppLog.Level = .debug) {
        Task { @MainActor in
            if level == .error {
                AppLog.shared.error("native", message)
            } else {
                AppLog.shared.debug("native", message)
            }
        }
    }

    /// Microsoft's services want a correlation vector on every request and
    /// reject some calls without one. Only the shape matters to us.
    private static func correlationVector() -> String {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        let seed = String((0..<16).map { _ in alphabet.randomElement()! })
        return seed + ".0"
    }
}
