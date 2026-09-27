import Foundation

/// Every piece of JavaScript GameStream puts into an Xbox page.
///
/// Keeping them in one file makes it obvious which scripts run in which
/// context. In 1.x the stream-isolation CSS was injected into *every* xbox.com
/// page, including the plain browser, which set `overflow: hidden` on the
/// document and hid anything whose class merely contained "header" — that is
/// why the Xbox site could not be scrolled and looked broken.
enum WebScripts {

    // MARK: - Authentication

    /// Reads the real streaming credential out of the page's own storage.
    ///
    /// xbox.com/play does not decide you are signed in from cookies. After the
    /// site's `/auth/msa?...loggedIn` round trip it stores XSTS tokens in
    /// localStorage, and the one that matters for cloud gaming is the token
    /// whose relying party is `gssv.xboxlive.com`. If that token is absent or
    /// expired, the player will bounce to a sign-in page no matter how many
    /// Microsoft cookies exist. Checking for it directly is the difference
    /// between "we think you're signed in" and "you can actually stream".
    static let authProbeJS = #"""
    (function() {
        var out = { signedIn: false, gamertag: "", source: "", expires: "", error: "" };

        function usable(token) {
            return typeof token === "string" && token.length > 20;
        }

        // The XSTS token itself carries the gamertag in its display claims,
        // which is the only place it appears once the site stores tokens under
        // Auth.User.* keys. Without this the app showed "Xbox account".
        function fromClaims(data) {
            if (!data || typeof data !== "object") return "";
            var claims = data.displayClaims || data.DisplayClaims;
            var xui = claims && (claims.xui || claims.Xui || claims.XUI);
            if (xui && xui.length) {
                var entry = xui[0] || {};
                var tag = entry.gtg || entry.Gtg || entry.gamertag || entry.umg;
                if (typeof tag === "string" && tag.length) return tag;
            }
            return "";
        }

        function readGamertag(info) {
            if (!info || typeof info !== "object") return "";
            var candidates = [info.gamertag, info.Gamertag, info.displayName,
                              info.DisplayName, info.uniqueModernGamertag];
            if (info.profile) {
                candidates.push(info.profile.gamertag, info.profile.displayName);
            }
            for (var i = 0; i < candidates.length; i++) {
                if (typeof candidates[i] === "string" && candidates[i].length) {
                    return candidates[i];
                }
            }
            return "";
        }

        try {
            // Fast path: the shape the Xbox web app writes today.
            try {
                var raw = localStorage.getItem("xboxcom_xbl_user_info");
                if (raw) {
                    var info = JSON.parse(raw);
                    out.gamertag = readGamertag(info);
                    var direct = info && info.tokens && info.tokens["http://gssv.xboxlive.com/"];
                    if (direct && usable(direct.token)) {
                        out.signedIn = true;
                        out.source = "xboxcom_xbl_user_info";
                        out.expires = direct.expiration || "";
                        if (!out.gamertag) out.gamertag = fromClaims(direct);
                    }
                }
            } catch (e) {}

            // Fallback: the per-user token cache, which survives shape changes.
            if (!out.signedIn) {
                var now = Date.now();
                for (var i = 0; i < localStorage.length; i++) {
                    var key = localStorage.key(i);
                    if (!key || key.indexOf("Auth.User.") !== 0) continue;

                    var user = null;
                    try { user = JSON.parse(localStorage.getItem(key)); } catch (e) { continue; }
                    if (!user || !user.tokens || !user.tokens.length) continue;

                    if (!out.gamertag) out.gamertag = readGamertag(user);

                    for (var j = 0; j < user.tokens.length; j++) {
                        var entry = user.tokens[j];
                        if (!entry || !entry.relyingParty) continue;
                        if (entry.relyingParty.indexOf("gssv.xboxlive.com") === -1) continue;

                        var data = entry.tokenData || {};
                        if (!usable(data.token)) continue;

                        var expires = data.expiration ? Date.parse(data.expiration) : 0;
                        if (expires && expires <= now) continue;

                        out.signedIn = true;
                        out.source = key;
                        out.expires = data.expiration || "";
                        if (!out.gamertag) out.gamertag = fromClaims(data) || fromClaims(entry);
                        break;
                    }
                    if (out.signedIn) break;
                }
            }
            // Last resort: the claim is written somewhere in storage even when
            // the containing shape is one this build has never seen.
            if (out.signedIn && !out.gamertag) {
                for (var k = 0; k < localStorage.length; k++) {
                    var anyKey = localStorage.key(k);
                    if (!anyKey) continue;
                    var value = localStorage.getItem(anyKey) || "";
                    var found = /"(?:gtg|Gtg|gamertag)"\s*:\s*"([^"]{1,32})"/.exec(value);
                    if (found) { out.gamertag = found[1]; break; }
                }
            }
        } catch (e) {
            out.error = String(e);
        }

        return JSON.stringify(out);
    })();
    """#

    // MARK: - Navigation reporting

    /// Tells the app which page the webview is on, including SPA route changes
    /// that never fire a navigation delegate callback.
    static let navigationBridgeJS = #"""
    (function() {
        if (window.__gsNav) return;
        window.__gsNav = true;

        function classify(href) {
            var value = (href || "").toLowerCase();
            if (value.indexOf("/auth/msa") !== -1) return "auth";
            if (value.indexOf("login.live.com") !== -1) return "login";
            if (value.indexOf("login.microsoftonline.com") !== -1) return "login";
            // A launch URL is the request to stream; /play/games is only the
            // store page for a title and must not count as streaming.
            if (value.indexOf("/play/launch") !== -1) return "launch";
            if (value.indexOf("/play/games") !== -1) return "store";
            if (value.indexOf("/play") !== -1) return "play";
            return "other";
        }

        function report() {
            try {
                window.webkit.messageHandlers.gamestream.postMessage({
                    type: "nav",
                    href: location.href || "",
                    kind: classify(location.href),
                    title: document.title || "",
                    hasVideo: !!document.querySelector("video")
                });
            } catch (e) {}
        }

        report();

        ["pushState", "replaceState"].forEach(function(name) {
            var original = history[name];
            if (typeof original !== "function") return;
            history[name] = function() {
                var result = original.apply(this, arguments);
                setTimeout(report, 60);
                return result;
            };
        });

        window.addEventListener("popstate", function() { setTimeout(report, 60); });
        window.addEventListener("hashchange", function() { setTimeout(report, 60); });
        setInterval(report, 2000);
    })();
    """#

    /// Reports when the stream's <video> element actually starts playing.
    ///
    /// This is the only trustworthy "the game is on screen" signal. 1.x hid its
    /// loading overlay on the first URL message instead, so the overlay
    /// disappeared the moment the launch page loaded and the user stared at a
    /// black screen while the session was still negotiating.
    static let streamStateJS = #"""
    (function() {
        if (window.__gsStreamState) return;
        window.__gsStreamState = true;

        var announced = false;

        function post(type, extra) {
            try {
                var payload = extra || {};
                payload.type = type;
                window.webkit.messageHandlers.gamestream.postMessage(payload);
            } catch (e) {}
        }

        function watch(video) {
            if (!video || video.__gsWatched) return;
            video.__gsWatched = true;

            video.addEventListener("playing", function() {
                if (announced) return;
                announced = true;
                post("streamPlaying", {
                    width: video.videoWidth || 0,
                    height: video.videoHeight || 0
                });
            });
            video.addEventListener("error", function() {
                post("streamError", { message: "The video element reported an error." });
            });
        }

        function scan() {
            var videos = document.querySelectorAll("video");
            for (var i = 0; i < videos.length; i++) {
                watch(videos[i]);
                if (!announced && !videos[i].paused && videos[i].readyState >= 3) {
                    announced = true;
                    post("streamPlaying", {
                        width: videos[i].videoWidth || 0,
                        height: videos[i].videoHeight || 0
                    });
                }
            }
        }

        scan();
        setInterval(scan, 700);

        // Surface the site's own error dialogs instead of leaving a black screen.
        setInterval(function() {
            try {
                var node = document.querySelector('[class*="ErrorScreen"], [class*="error-screen"], [data-testid*="error"]');
                if (!node) return;
                var text = (node.innerText || "").trim();
                if (text.length > 4 && text.length < 400) {
                    post("streamError", { message: text });
                }
            } catch (e) {}
        }, 1500);
    })();
    """#

    // MARK: - Stream presentation

    /// Hides site chrome, but only on a launch page and only what is safe.
    ///
    /// The 1.x version matched `[class*="header"]`, `[class*="banner"]` and
    /// `[class*="social"]` and forced `overflow: hidden` on every xbox.com
    /// page. That removed real interface elements and made the site
    /// unscrollable. This version scopes itself to the launch route and touches
    /// only the document chrome around the player.
    static let streamChromeJS = #"""
    (function() {
        if (window.__gsChrome) return;
        window.__gsChrome = true;

        var STYLE_ID = "gamestream-stream-chrome";
        var css = [
            "html, body { background: #000 !important; margin: 0 !important; padding: 0 !important; }",
            "body { overflow: hidden !important; }",
            "header[role=\"banner\"], footer[role=\"contentinfo\"], nav[aria-label] { display: none !important; }",
            "video { width: 100% !important; height: 100% !important; object-fit: contain !important; background: #000 !important; }"
        ].join("\n");

        function onLaunchPage() {
            var href = (location.href || "").toLowerCase();
            return href.indexOf("/play/launch") !== -1;
        }

        function apply() {
            var existing = document.getElementById(STYLE_ID);
            if (!onLaunchPage()) {
                if (existing && existing.parentNode) existing.parentNode.removeChild(existing);
                return;
            }
            if (!existing) {
                existing = document.createElement("style");
                existing.id = STYLE_ID;
                (document.head || document.documentElement).appendChild(existing);
            }
            if (existing.textContent !== css) existing.textContent = css;
        }

        apply();
        setInterval(apply, 1200);
    })();
    """#

    /// Restyles Better xCloud's own web interface to match the app.
    ///
    /// Better xCloud is a userscript: its menus are HTML rendered inside the
    /// player, so none of the native Liquid Glass work reaches them. It does
    /// however read every button colour, font and control height from CSS
    /// custom properties, so its whole interface can be re-skinned from the
    /// outside without touching or forking the script. Panels get the same
    /// translucent blur, radii and hairline border as the native cards, and
    /// buttons pick up the accent colour chosen in Settings.
    static func betterXCloudSkinJS(accentRGB: String) -> String {
        let css = """
        :root, body {
            --bx-primary-button-rgb: \(accentRGB);
            --bx-primary-button-hover-rgb: \(accentRGB);
            --bx-primary-button-active-rgb: \(accentRGB);
            --bx-primary-button-disabled-rgb: 120,120,128;
            --bx-default-button-rgb: 118,118,128;
            --bx-normal-font: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
            --bx-title-font: -apple-system, BlinkMacSystemFont, "SF Pro Display", system-ui, sans-serif;
            --bx-title-font-semibold: -apple-system, BlinkMacSystemFont, "SF Pro Display", system-ui, sans-serif;
            --bx-monospaced-font: ui-monospace, "SF Mono", Menlo, monospace;
            --bx-button-height: 40px;
        }

        /* Panels: the glass equivalent of the app's cards. */
        .bx-settings-dialog,
        .bx-centered-dialog,
        .bx-navigation-dialog,
        .bx-key-binding-dialog,
        .bx-game-bar-container,
        .bx-stream-settings-selection {
            background-color: rgba(18, 18, 20, 0.62) !important;
            -webkit-backdrop-filter: saturate(170%) blur(30px) !important;
            backdrop-filter: saturate(170%) blur(30px) !important;
            border: 1px solid rgba(255, 255, 255, 0.14) !important;
            border-radius: 22px !important;
            box-shadow: 0 20px 52px rgba(0, 0, 0, 0.5) !important;
            color: #fff !important;
        }

        .bx-settings-tabs {
            background-color: rgba(255, 255, 255, 0.07) !important;
            border-radius: 18px !important;
        }

        .bx-settings-row {
            border-radius: 14px !important;
            border-bottom-color: rgba(255, 255, 255, 0.08) !important;
        }

        /* Controls: capsules and soft rectangles, as in the native interface. */
        .bx-button {
            border-radius: 999px !important;
            font-weight: 600 !important;
            transition: transform 0.15s ease, filter 0.15s ease !important;
        }
        .bx-button:active { transform: scale(0.97) !important; }

        .bx-select,
        .bx-number-stepper,
        .bx-dual-number-stepper,
        .bx-binding-button {
            border-radius: 12px !important;
            background-color: rgba(255, 255, 255, 0.1) !important;
            border: 1px solid rgba(255, 255, 255, 0.12) !important;
        }

        .bx-focusable:focus,
        .bx-focusable:focus-visible {
            outline: 2px solid rgb(\(accentRGB)) !important;
            outline-offset: 2px !important;
            border-radius: 12px !important;
        }

        /* Read-outs that sit over the video. */
        .bx-stats-bar {
            background-color: rgba(0, 0, 0, 0.42) !important;
            -webkit-backdrop-filter: blur(22px) !important;
            backdrop-filter: blur(22px) !important;
            border-radius: 16px !important;
            border: 1px solid rgba(255, 255, 255, 0.1) !important;
            font-variant-numeric: tabular-nums !important;
            padding: 6px 12px !important;
        }
        .bx-stats-bar label { color: rgba(255, 255, 255, 0.6) !important; }

        .bx-toast {
            background-color: rgba(18, 18, 20, 0.7) !important;
            -webkit-backdrop-filter: blur(26px) !important;
            backdrop-filter: blur(26px) !important;
            border-radius: 18px !important;
            border: 1px solid rgba(255, 255, 255, 0.14) !important;
        }

        .bx-game-bar-container { padding: 4px !important; }
        """

        return #"""
        (function() {
            if (window.__gsSkin) return;
            window.__gsSkin = true;

            var ID = "gamestream-bx-skin";
            var CSS = "__CSS__";

            function apply() {
                var node = document.getElementById(ID);
                if (!node) {
                    node = document.createElement("style");
                    node.id = ID;
                    node.textContent = CSS;
                    (document.head || document.documentElement).appendChild(node);
                    return;
                }
                // Better xCloud rebuilds <head> on some navigations, and the
                // element has to be last to win against its own stylesheet.
                if (node.parentNode && node.parentNode.lastChild !== node) {
                    node.parentNode.appendChild(node);
                }
            }

            apply();
            if (document.readyState === "loading") {
                document.addEventListener("DOMContentLoaded", apply);
            }
            setInterval(apply, 1500);
        })();
        """#.replacingOccurrences(of: "__CSS__", with: Self.escapedForJS(css))
    }

    /// A CSS payload safe to embed in a JavaScript string literal.
    private static func escapedForJS(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Presses the site's own Play button on a launch page.
    ///
    /// 1.x clicked anything labelled "play", "ok", "continue" or "start"
    /// anywhere on xbox.com every 600 ms for 45 seconds, which meant it pressed
    /// unrelated buttons on browse pages. This only runs on a launch URL, only
    /// matches the launch prompts exactly, stops as soon as video is playing,
    /// and gives up after a bounded number of attempts.
    static let autoStartJS = #"""
    (function() {
        if (window.__gsAutoStart) return;
        window.__gsAutoStart = true;

        var LABELS = ["play", "play now", "play with ads", "resume", "continue playing"];
        var attempts = 0;
        var maxAttempts = 40;      // ~30 seconds at 750 ms

        var timer = setInterval(function() {
            try {
                attempts++;
                if (attempts > maxAttempts) { clearInterval(timer); return; }

                if ((location.href || "").toLowerCase().indexOf("/play/launch") === -1) return;

                var videos = document.querySelectorAll("video");
                for (var i = 0; i < videos.length; i++) {
                    if (!videos[i].paused && videos[i].readyState >= 3) {
                        clearInterval(timer);
                        return;
                    }
                }

                var nodes = document.querySelectorAll('button, [role="button"]');
                for (var j = 0; j < nodes.length; j++) {
                    var node = nodes[j];
                    if (node.disabled) continue;
                    var text = (node.innerText || node.textContent ||
                                node.getAttribute("aria-label") || "").trim().toLowerCase();
                    if (!text) continue;
                    if (LABELS.indexOf(text) === -1) continue;
                    node.click();
                    try {
                        window.webkit.messageHandlers.gamestream.postMessage({
                            type: "autoStart", label: text
                        });
                    } catch (e) {}
                    return;
                }
            } catch (e) {}
        }, 750);
    })();
    """#

    // MARK: - Better xCloud preferences

    /// Writes Better xCloud preferences before the script boots.
    static func betterXCloudPrefsJS(_ preferences: [String: String]) -> String {
        let assignments = preferences.map { key, value in
            "data[\(jsString(key))] = \(jsString(value));"
        }.joined(separator: "\n            ")

        return """
        (function() {
            try {
                if ((location.host || "").indexOf("xbox.com") === -1) return;
                var storageKey = "BetterXcloud";
                var data = {};
                try { data = JSON.parse(localStorage.getItem(storageKey) || "{}") || {}; } catch (e) { data = {}; }
                \(assignments)
                localStorage.setItem(storageKey, JSON.stringify(data));
            } catch (e) {}
        })();
        """
    }

    /// JSON is a subset of JavaScript literals, so this is a safe way to embed
    /// arbitrary user-visible values without hand-rolling escape rules.
    private static func jsString(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [value], options: [])
        guard let data, var text = String(data: data, encoding: .utf8) else { return "\"\"" }
        text.removeFirst()
        text.removeLast()
        return text
    }
}
