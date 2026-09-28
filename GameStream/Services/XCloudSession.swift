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

    /// Asks the region for a session for one title.
    ///
    /// The settings block describes the client to the service. The values are
    /// a plain description of what this app is and can do; the service uses
    /// them to pick a transport and a keyboard layout, not to gate access.
    func provision(login: XCloudAPI.Login,
                   titleId: String,
                   region: XCloudAPI.Region? = nil) async throws -> Handle {
        let endpoint = region ?? preferredRegion(of: login)
        guard let base = endpoint?.baseURI, !base.isEmpty else {
            throw Failure(step: "provision", detail: "the account has no usable region")
        }
        guard let url = URL(string: base + "/v5/sessions/cloud/play") else {
            throw Failure(step: "provision", detail: "the region returned an unusable address")
        }

        let body: [String: Any] = [
            "titleId": titleId,
            "systemUpdateGroup": "",
            "serverId": "",
            "fallbackRegionNames": [],
            "settings": [
                "nanoVersion": "V3;RtcTransport",
                "enableTextToSpeech": false,
                "highContrast": 0,
                "locale": Locale.current.identifier.replacingOccurrences(of: "_", with: "-"),
                "useIceConnection": false,
                "timezoneOffsetMinutes": TimeZone.current.secondsFromGMT() / 60,
                "osName": "ios"
            ]
        ]

        let (data, http) = try await send(
            request(url: url, method: "POST", token: login.gsToken, body: body),
            step: "provision"
        )
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(step: "provision", detail: "HTTP \(http.statusCode) with no readable body")
        }
        guard let path = object["sessionPath"] as? String, !path.isEmpty else {
            let reason = (object["errorDetails"] as? [String: Any])?["message"] as? String
            throw Failure(step: "provision",
                          detail: reason ?? "no session path in the response (HTTP \(http.statusCode))")
        }
        return Handle(baseURI: base, path: path)
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
               titleId: String,
               onProgress: @Sendable @escaping (String) -> Void) async -> String {
        var handle: Handle?
        defer {
            if let handle {
                let token = login.gsToken
                Task.detached { _ = await XCloudSession.shared.release(handle, token: token) }
            }
        }
        do {
            onProgress("Asking for a session…")
            let created = try await provision(login: login, titleId: titleId)
            handle = created

            var lines = ["Session granted."]
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
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure(step: step, detail: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw Failure(step: step, detail: "no HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw Failure(step: step, detail: "HTTP \(http.statusCode)")
        }
        return (data, http)
    }

    /// Microsoft's services want a correlation vector on every request and
    /// reject some calls without one. Only the shape matters to us.
    private static func correlationVector() -> String {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        let seed = String((0..<16).map { _ in alphabet.randomElement()! })
        return seed + ".0"
    }
}
