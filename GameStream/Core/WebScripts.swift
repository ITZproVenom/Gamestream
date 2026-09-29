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
                        // The value itself, for the native client. It is kept
                        // in memory only and never written to disk or logged.
                        out.token = direct.token;
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
                        out.token = data.token;
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
        // Deliberately narrow. The previous version hid every
        // nav[aria-label] and clipped the body, which also hid the stream
        // menu that Better xCloud adds its button to and clipped its
        // dialogs — that is why its menu "would not open".
        var css = [
            "html, body { background: #000 !important; margin: 0 !important; padding: 0 !important; }",
            "header[role=\"banner\"], footer[role=\"contentinfo\"] { display: none !important; }",
            "video { width: 100% !important; height: 100% !important; object-fit: contain !important; background: #000 !important; }",
            // Nothing belonging to the enhancement may be clipped or buried.
            "[class^=\"bx-\"], [class*=\" bx-\"], [id^=\"bx-\"] { overflow: visible !important; }",
            ".bx-settings-dialog, .bx-centered-dialog, .bx-navigation-dialog, .bx-key-binding-dialog { z-index: 2147483000 !important; }",
            "#bx-game-bar { z-index: 2147482000 !important; }",
            // The script disables pointer events on its in-stream button
            // while the HUD fades, and only restores them when the HUD
            // reports left: 0px. In this webview that condition often never
            // holds, so the button stays present and untappable. Forcing it
            // back is scoped to that one button's subtree, which sits inside
            // a HUD that is itself unclickable while hidden.
            "[title=\"Better xCloud\"], [title=\"Better xCloud\"] * { pointer-events: auto !important; }",
            // The same applies to everything the script opens. Its dialogs
            // inherit that dead state, so the menu could be opened and read
            // but not used: no control answered a press and the list would
            // not scroll. Scoped to dialogs, which exist only while one is
            // open, so nothing here can reach the game's own touches.
            ".bx-dialog, .bx-dialog *, .bx-settings-dialog, .bx-settings-dialog *, .bx-centered-dialog, .bx-centered-dialog *, .bx-navigation-dialog, .bx-navigation-dialog *, .bx-key-binding-dialog, .bx-key-binding-dialog * { pointer-events: auto !important; }",
            // A dialog that cannot scroll is unusable on a phone in
            // landscape, where the list is taller than the screen.
            ".bx-dialog, .bx-settings-dialog, .bx-centered-dialog, .bx-navigation-dialog { max-height: 92vh !important; overflow-y: auto !important; -webkit-overflow-scrolling: touch !important; touch-action: pan-y !important; }",
            // The site's own HUD is redundant now that the app has its own,
            // and it overlaps it. Hidden with opacity rather than display so
            // the elements keep their layout and still answer a programmatic
            // click: quit and the guide are driven by pressing the real
            // controls, and display:none would be a behaviour change on a
            // path that already works.
            "#StreamHud { opacity: 0 !important; pointer-events: none !important; }",
            "#bx-game-bar { display: none !important; }",
            // Better xCloud's own stats bar duplicates the app's, in a
            // different place and a different font, over the game.
            ".bx-stats-bar { display: none !important; }",
            // Its dialog dims the stream behind a blurred overlay. When the
            // overlay outlives the dialog the game is left permanently
            // frosted, which only a reconnect used to clear. The blur is
            // removed outright so a stale overlay is at worst invisible.
            ".bx-dialog-overlay { backdrop-filter: none !important; -webkit-backdrop-filter: none !important; background: rgba(0,0,0,0.4) !important; }"
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

        /// The dimming layer behind the enhancement menu outlives it.
        ///
        /// Closing the menu with the app's own button already swept this up,
        /// but closing it with the script's own close button did not, and
        /// the game was left dimmed until the stream was restarted. Hidden
        /// rather than removed, and cleared again the moment a dialog is
        /// genuinely open, so the script keeps control of its own element.
        function sweepOverlay() {
            if (!onLaunchPage()) return;
            var dialogs = document.querySelectorAll(
                ".bx-settings-dialog, .bx-navigation-dialog, .bx-centered-dialog, .bx-key-binding-dialog"
            );
            var open = false;
            for (var d = 0; d < dialogs.length; d++) {
                var node = dialogs[d];
                if (node.classList.contains("bx-gone")) continue;
                var box = node.getBoundingClientRect();
                if (box.width > 8 && box.height > 8) { open = true; break; }
            }
            var overlays = document.querySelectorAll(".bx-dialog-overlay");
            for (var i = 0; i < overlays.length; i++) {
                var overlay = overlays[i];
                if (open) {
                    if (overlay.style.display === "none") {
                        overlay.style.display = "";
                        overlay.style.pointerEvents = "";
                    }
                } else if (overlay.style.display !== "none") {
                    overlay.style.display = "none";
                    overlay.style.pointerEvents = "none";
                }
            }
        }

        function tick() {
            apply();
            sweepOverlay();
        }

        tick();
        setInterval(tick, 500);
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

    /// Reports the real WebRTC numbers to the app once a second.
    ///
    /// The figures come from the peer connection itself rather than from
    /// scraping somebody else's overlay, so the native HUD keeps working
    /// regardless of what the enhancement script does with its own stats bar.
    static let streamStatsJS = #"""
    (function() {
        if (window.__gsStats) return;
        window.__gsStats = true;

        var connections = [];
        var Native = window.RTCPeerConnection;
        if (!Native) return;

        window.RTCPeerConnection = function() {
            var pc = new Native(arguments[0], arguments[1]);
            connections.push(pc);
            return pc;
        };
        window.RTCPeerConnection.prototype = Native.prototype;

        var previous = {};

        function report(payload) {
            try {
                window.webkit.messageHandlers.gamestream.postMessage(payload);
            } catch (e) {}
        }

        async function sample() {
            for (var i = 0; i < connections.length; i++) {
                var pc = connections[i];
                if (!pc || pc.connectionState === "closed") continue;

                var report_ = null;
                try { report_ = await pc.getStats(); } catch (e) { continue; }

                var video = null, pair = null, codecName = "";
                report_.forEach(function(entry) {
                    if (entry.type === "inbound-rtp" && entry.kind === "video") video = entry;
                    if (entry.type === "candidate-pair" && entry.nominated) pair = entry;
                });
                if (!video) continue;

                report_.forEach(function(entry) {
                    if (entry.type === "codec" && video && entry.id === video.codecId) {
                        codecName = (entry.mimeType || "").replace("video/", "");
                    }
                });

                var last = previous[video.id] || null;
                var bitrate = 0;
                if (last && video.timestamp > last.timestamp) {
                    var seconds = (video.timestamp - last.timestamp) / 1000;
                    bitrate = Math.max(0, Math.round(
                        ((video.bytesReceived - last.bytesReceived) * 8) / seconds / 1000
                    ));
                }
                previous[video.id] = {
                    timestamp: video.timestamp,
                    bytesReceived: video.bytesReceived || 0
                };

                report({
                    type: "stats",
                    fps: Math.round(video.framesPerSecond || 0),
                    bitrateKbps: bitrate,
                    rttMs: pair && pair.currentRoundTripTime
                        ? Math.round(pair.currentRoundTripTime * 1000) : 0,
                    jitterMs: video.jitter ? Math.round(video.jitter * 1000) : 0,
                    packetsLost: video.packetsLost || 0,
                    framesDropped: video.framesDropped || 0,
                    decodeMs: video.totalDecodeTime && video.framesDecoded
                        ? Math.round((video.totalDecodeTime / video.framesDecoded) * 1000)
                        : 0,
                    width: video.frameWidth || 0,
                    height: video.frameHeight || 0,
                    codec: codecName
                });
                return;
            }
        }

        setInterval(sample, 1000);
    })();
    """#

    /// Native HUD buttons, carried out inside the page.
    ///
    /// The enhancement's menu and the Xbox guide are the site's own controls,
    /// so the only honest way to press them from a native button is to find
    /// and click them. Every attempt reports what it matched, so a failure
    /// shows up in Diagnostics instead of looking like a dead button.
    static let streamCommandsJS = #"""
    (function() {
        if (window.__gsCommands) return;
        window.__gsCommands = true;

        function note(command, detail) {
            try {
                window.webkit.messageHandlers.gamestream.postMessage({
                    type: "command", command: command, detail: detail
                });
            } catch (e) {}
        }

        function visible(node) {
            if (!node) return false;
            var box = node.getBoundingClientRect();
            if (box.width < 4 || box.height < 4) return false;
            var style = window.getComputedStyle(node);
            return style.visibility !== "hidden" && style.display !== "none";
        }

        function click(node) {
            try {
                node.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true }));
                node.dispatchEvent(new PointerEvent("pointerup", { bubbles: true }));
                node.click();
                return true;
            } catch (e) { return false; }
        }

        function describe(node) {
            var label = node.getAttribute("aria-label") || (node.textContent || "").trim();
            return (node.tagName || "?").toLowerCase() + " \"" + label.slice(0, 40) + "\"";
        }

        function match(selectors, pattern) {
            for (var i = 0; i < selectors.length; i++) {
                var found = document.querySelectorAll(selectors[i]);
                for (var j = 0; j < found.length; j++) {
                    if (visible(found[j])) return found[j];
                }
            }
            if (!pattern) return null;
            var buttons = document.querySelectorAll("button, [role=\"button\"]");
            for (var k = 0; k < buttons.length; k++) {
                var node = buttons[k];
                var text = ((node.getAttribute("aria-label") || "") + " "
                            + (node.textContent || "")).toLowerCase();
                if (pattern.test(text) && visible(node)) return node;
            }
            return null;
        }

        /// Better xCloud is not wrapped in a closure: its top-level classes
        /// live in the page's global lexical scope, so the settings dialog can
        /// be opened by the same call its own button makes —
        /// `SettingsDialog.getInstance().show()`. Pressing the cloned HUD
        /// button was never reliable: the script sets pointer-events: none on
        /// it during the HUD fade and only restores it when the HUD finishes
        /// at exactly left: 0px, so the element is frequently inert.
        function openBxSettings() {
            try {
                var grip = document.querySelector("#StreamHud button[class^=GripHandle]");
                if (grip && grip.ariaExpanded === "true") {
                    grip.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true }));
                    grip.click();
                }
            } catch (e) {}

            try {
                if (typeof SettingsDialog !== "undefined"
                    && SettingsDialog.getInstance) {
                    SettingsDialog.getInstance().show();
                    return "SettingsDialog.show(), " + reveal();
                }
            } catch (e) {
                return "SettingsDialog threw: " + e;
            }
            return null;
        }

        /// If the dialog exists but cannot be seen, make it seen.
        ///
        /// Better xCloud hides it with a `bx-gone` class and shows it by
        /// removing that class. Anything that leaves it hidden — its own
        /// stylesheet failing to load, or a restyle of ours interfering —
        /// produces a button that appears to do nothing at all.
        function reveal() {
            var node = document.querySelector(".bx-navigation-dialog");
            if (!node) return dialogState();

            var before = dialogState();
            var style = window.getComputedStyle(node);
            var box = node.getBoundingClientRect();
            var hidden = style.display === "none"
                || style.visibility === "hidden"
                || parseFloat(style.opacity) < 0.05
                || box.width < 8 || box.height < 8;
            if (!hidden) return before;

            node.classList.remove("bx-gone");
            node.style.setProperty("display", "flex", "important");
            node.style.setProperty("visibility", "visible", "important");
            node.style.setProperty("opacity", "1", "important");
            node.style.setProperty("pointer-events", "auto", "important");
            if (box.width < 8 || box.height < 8) {
                node.style.setProperty("position", "fixed", "important");
                node.style.setProperty("inset", "0", "important");
                node.style.setProperty("z-index", "9999", "important");
            }
            return "was hidden (" + before + "), forced visible: " + dialogState();
        }

        /// "Nothing happened" covers two very different faults: the dialog was
        /// never created, or it was created and cannot be seen. Only the page
        /// can tell them apart, so it reports which.
        function dialogState() {
            var node = document.querySelector(".bx-navigation-dialog");
            if (!node) return "no .bx-navigation-dialog in the document";
            var style = window.getComputedStyle(node);
            var box = node.getBoundingClientRect();
            return "dialog class=\"" + node.className + "\""
                + " display=" + style.display
                + " visibility=" + style.visibility
                + " opacity=" + style.opacity
                + " z=" + style.zIndex
                + " rect=" + Math.round(box.left) + "," + Math.round(box.top)
                + " " + Math.round(box.width) + "x" + Math.round(box.height);
        }

        /// The site's own HUD button, which is what opens the Xbox guide.
        /// Better xCloud finds it the same way, and clones it for itself.
        function guideButton() {
            var hud = document.querySelector("#StreamHud");
            if (!hud) return null;
            var wrapper = hud.querySelector("div[class^=HUDButton]");
            if (!wrapper) return null;
            return wrapper.querySelector("button") || wrapper;
        }

        function expandHud() {
            var grip = document.querySelector("#StreamHud button[class^=GripHandle]");
            if (!grip || grip.ariaExpanded === "true") return;
            grip.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true }));
            grip.click();
        }

        /// Better xCloud can leave pointer-events off on the HUD subtree.
        function enable(node) {
            while (node && node !== document.body) {
                if (node.style && node.style.pointerEvents === "none") {
                    node.style.pointerEvents = "auto";
                }
                node = node.parentElement;
            }
        }

        /// Closes the enhancement's dialog and clears what it leaves behind.
        ///
        /// Tapping outside the dialog dismisses it visually but can leave the
        /// dimming overlay in the document. That overlay swallows every touch
        /// meant for the game, which reads as a frozen, frosted picture that
        /// only a reconnect clears.
        function closeBxSettings() {
            try {
                if (typeof SettingsDialog !== "undefined" && SettingsDialog.getInstance) {
                    var dialog = SettingsDialog.getInstance();
                    if (dialog && dialog.hide) dialog.hide();
                }
            } catch (e) {}
            return sweepOverlays();
        }

        /// Removes any dimming overlay that no longer has a dialog to dim.
        function sweepOverlays() {
            var removed = 0;
            var dialogs = document.querySelectorAll(
                ".bx-settings-dialog, .bx-navigation-dialog, .bx-centered-dialog, .bx-key-binding-dialog"
            );
            var open = false;
            for (var d = 0; d < dialogs.length; d++) {
                var node = dialogs[d];
                if (node.classList.contains("bx-gone")) continue;
                var box = node.getBoundingClientRect();
                if (box.width > 8 && box.height > 8) { open = true; break; }
            }
            if (open) return "a dialog is still open";

            var overlays = document.querySelectorAll(".bx-dialog-overlay");
            for (var i = 0; i < overlays.length; i++) {
                if (overlays[i].parentNode) {
                    overlays[i].parentNode.removeChild(overlays[i]);
                    removed++;
                }
            }
            // Anything the script blurred directly, unblurred.
            var blurred = document.querySelectorAll("[style*=\"blur\"]");
            for (var b = 0; b < blurred.length; b++) {
                blurred[b].style.removeProperty("filter");
                blurred[b].style.removeProperty("-webkit-filter");
                blurred[b].style.removeProperty("backdrop-filter");
            }
            return removed ? ("cleared " + removed + " stale overlay(s)") : "nothing to clear";
        }

        // A dialog dismissed by tapping outside never routes through our
        // close command, so the sweep also runs on a slow timer. It is a
        // cheap query and only acts when there is nothing open.
        setInterval(function() {
            try {
                if (document.querySelector(".bx-dialog-overlay")) sweepOverlays();
            } catch (e) {}
        }, 1000);

        window.__gsCommand = function(command) {
            var target = null;

            if (command === "bxMenu") {
                var how = openBxSettings();
                if (how) {
                    note(command, "opened via " + how);
                    return true;
                }
                // Only if the script is not loaded at all.
                target = match([
                    "[title=\"Better xCloud\"]",
                    "button[title*=\"Better xCloud\" i]",
                    ".bx-header-settings-button"
                ], /better\s*xcloud/);
                enable(target);
            } else if (command === "bxClose") {
                note(command, closeBxSettings());
                return true;
            } else if (command === "quit") {
                // Ending the session properly is the site's own quit, inside
                // the guide. Closing the player only stops the picture; the
                // session stays open and the next launch resumes into it.
                expandHud();
                var quit = document.querySelector("a[class*=QuitGameButton], button[class*=QuitGameButton]");
                if (!quit) {
                    var guide = guideButton();
                    if (guide) { click(guide); }
                    quit = document.querySelector("a[class*=QuitGameButton], button[class*=QuitGameButton]");
                }
                target = quit;
                enable(target);
            } else if (command === "guide") {
                expandHud();
                target = guideButton();
                enable(target);
                if (!target) {
                    target = match([
                        "button[aria-label*=\"guide\" i]",
                        "button[class*=\"GuideButton\"]"
                    ], /xbox guide|open guide|guide menu|nexus/);
                }
            }

            if (target && click(target)) {
                note(command, "pressed " + describe(target));
                return true;
            }

            // A dead button with no explanation is what made this hard to
            // fix the first time. Report what the page is actually offering.
            var candidates = [];
            var all = document.querySelectorAll("button, [role=\"button\"], [title]");
            for (var i = 0; i < all.length && candidates.length < 8; i++) {
                if (!visible(all[i])) continue;
                var cls = (all[i].className || "").toString().slice(0, 30);
                candidates.push(describe(all[i]) + " ." + cls);
            }
            note(command, "no match; bx="
                 + (typeof SettingsDialog !== "undefined" ? "loaded" : "absent")
                 + "; visible controls: " + candidates.join(" | "));
            return false;
        };
    })();
    """#

    /// Captures the decoded video frame itself, at its own resolution.
    ///
    /// Snapshotting the web view returns what the phone is showing: the frame
    /// scaled down to a few hundred points, with the touch controls, the
    /// site's HUD and any overlay drawn on top. Reading the `<video>` element
    /// into a canvas returns the frame the decoder produced — 1920x1080 when
    /// that is what is being streamed — with nothing over it.
    ///
    /// WebRTC video does not taint a canvas, so the pixels can be read back.
    static let captureJS = #"""
    (function() {
        if (window.__gsCapture) return;

        function biggestVideo() {
            var videos = document.querySelectorAll("video");
            var best = null;
            for (var i = 0; i < videos.length; i++) {
                var v = videos[i];
                if (!v.videoWidth || !v.videoHeight) continue;
                if (!best || v.videoWidth * v.videoHeight > best.videoWidth * best.videoHeight) {
                    best = v;
                }
            }
            return best;
        }

        function grab(video) {
            var canvas = document.createElement("canvas");
            canvas.width = video.videoWidth;
            canvas.height = video.videoHeight;
            var context = canvas.getContext("2d", { alpha: false });
            context.imageSmoothingEnabled = false;
            context.drawImage(video, 0, 0, canvas.width, canvas.height);
            // PNG: the frame has already been through one lossy encoder on
            // the way here, and adding a second one for no reason would be
            // the only avoidable quality loss in the whole path.
            return {
                data: canvas.toDataURL("image/png"),
                width: canvas.width,
                height: canvas.height
            };
        }

        /// Collects several consecutive frames and makes one image out of
        /// them.
        ///
        /// The bitrate cannot be raised on demand -- the encoder is on the
        /// server and decides for itself -- but the picture is not equally
        /// bad in every frame. Two things are true of a heavily compressed
        /// stream, and both can be used:
        ///
        ///  * On a scene that is holding still, the encoder keeps refining
        ///    the same picture, and the quantisation noise it leaves is
        ///    different in each frame. Averaging several frames of the same
        ///    still scene cancels much of that noise and recovers real
        ///    detail. This is the only genuine quality gain available here.
        ///  * On a scene that is moving, averaging would smear it, so the
        ///    sharpest single frame is used instead. Frames right after a
        ///    keyframe carry far more detail than the ones between, and
        ///    sharpness is a good proxy for catching one.
        ///
        /// Which of the two applies is decided by measuring how much the
        /// frames actually differ, not by asking the user.
        function stack(video, frames) {
            var width = video.videoWidth;
            var height = video.videoHeight;
            if (!frames.length) return null;

            // Cheap motion measure on a coarse grid: full-resolution
            // comparison of several 1080p frames is far too slow here.
            var step = Math.max(1, Math.floor(width / 160)) * 4;
            var moved = 0;
            var first = frames[0];
            for (var f = 1; f < frames.length; f++) {
                var other = frames[f];
                var total = 0;
                var samples = 0;
                for (var i = 0; i < first.length; i += step) {
                    total += Math.abs(first[i] - other[i]);
                    samples++;
                }
                if (samples) moved = Math.max(moved, total / samples);
            }

            var canvas = document.createElement("canvas");
            canvas.width = width;
            canvas.height = height;
            var context = canvas.getContext("2d", { alpha: false });
            var output = context.createImageData(width, height);
            var out = output.data;

            // Roughly a tenth of a level of average movement. Above this the
            // scene is not still and averaging would ghost.
            if (moved > 2.5) {
                var sharpest = 0;
                var best = -1;
                for (var g = 0; g < frames.length; g++) {
                    var data = frames[g];
                    var energy = 0;
                    for (var p = 4; p < data.length - 4; p += step) {
                        var d = data[p] - data[p - 4];
                        energy += d * d;
                    }
                    if (energy > best) { best = energy; sharpest = g; }
                }
                out.set(frames[sharpest]);
                context.putImageData(output, 0, 0);
                return {
                    data: canvas.toDataURL("image/png"),
                    width: width,
                    height: height,
                    method: "sharpest of " + frames.length
                };
            }

            var count = frames.length;
            for (var q = 0; q < out.length; q += 4) {
                var r = 0, g2 = 0, b = 0;
                for (var k = 0; k < count; k++) {
                    var frame = frames[k];
                    r += frame[q];
                    g2 += frame[q + 1];
                    b += frame[q + 2];
                }
                out[q] = r / count;
                out[q + 1] = g2 / count;
                out[q + 2] = b / count;
                out[q + 3] = 255;
            }
            context.putImageData(output, 0, 0);
            return {
                data: canvas.toDataURL("image/png"),
                width: width,
                height: height,
                method: "averaged " + count + " still frames"
            };
        }

        /// Grabs `count` presented frames in a row, then stacks them.
        function captureStacked(video, count, resolve) {
            var reader = document.createElement("canvas");
            reader.width = video.videoWidth;
            reader.height = video.videoHeight;
            var context = reader.getContext("2d", { alpha: false, willReadFrequently: true });
            var frames = [];

            function next() {
                if (frames.length >= count) {
                    try {
                        resolve(stack(video, frames) || { error: "nothing was captured" });
                    } catch (e) {
                        resolve({ error: String(e) });
                    }
                    return;
                }
                try {
                    context.drawImage(video, 0, 0, reader.width, reader.height);
                    frames.push(context.getImageData(0, 0, reader.width, reader.height).data);
                } catch (e) {
                    resolve({ error: String(e) });
                    return;
                }
                if (typeof video.requestVideoFrameCallback === "function") {
                    video.requestVideoFrameCallback(next);
                } else {
                    setTimeout(next, 20);
                }
            }
            next();
        }

        /// Resolves with the next presented frame where possible, so the
        /// capture is a real frame rather than whatever the element happens
        /// to be holding between them.
        window.__gsCapture = function(options) {
            return new Promise(function(resolve) {
                var video = biggestVideo();
                if (!video) {
                    resolve({ error: "no video is playing" });
                    return;
                }

                var stackFrames = options && options.stack ? options.stack : 0;
                if (stackFrames > 1) {
                    captureStacked(video, Math.min(stackFrames, 8), resolve);
                    return;
                }

                function done() {
                    try {
                        resolve(grab(video));
                    } catch (e) {
                        resolve({ error: String(e) });
                    }
                }

                if (typeof video.requestVideoFrameCallback === "function") {
                    var settled = false;
                    video.requestVideoFrameCallback(function() {
                        if (settled) return;
                        settled = true;
                        done();
                    });
                    // Do not hang if the stream is paused or stalled.
                    setTimeout(function() {
                        if (settled) return;
                        settled = true;
                        done();
                    }, 250);
                } else {
                    done();
                }
            });
        };
    })();
    """#

    /// Presses the site's own Play button on a launch page.
    ///
    /// 1.x clicked anything labelled "play", "ok", "continue" or "start"
    /// anywhere on xbox.com every 600 ms for 45 seconds, which meant it pressed
    /// unrelated buttons on browse pages. This only runs on a launch URL, only
    /// matches the launch prompts exactly, stops as soon as video is playing,
    /// and gives up after a bounded number of attempts.
    /// Records the stream from the media the page is already receiving.
    ///
    /// Screen capture records the glass, so the app's own controls and the
    /// site's on-screen pad were burnt into every clip, and the only way
    /// around that was to hide them from the player as well. Recording the
    /// incoming media instead separates the two completely: the clip is the
    /// game and its sound, and everything drawn over it stays on screen for
    /// the person holding the phone.
    static let clipJS = #"""
    (function() {
        if (window.__gsClipReady) return;
        window.__gsClipReady = true;

        var recorder = null;
        var sequence = 0;

        function post(payload) {
            try { window.webkit.messageHandlers.gamestream.postMessage(payload); } catch (e) {}
        }

        /// What the peer connection handed the page, kept by the enhancement
        /// layer because it is the only place that sees the track arrive.
        function source() {
            try {
                var media = window.__gsMediaStream;
                if (media && media.getVideoTracks && media.getVideoTracks().length) {
                    return media;
                }
            } catch (e) {}
            return null;
        }

        /// Only MP4. A WebM clip cannot be added to Photos, so producing one
        /// would mean recording something nobody can keep.
        function container() {
            var candidates = ["video/mp4;codecs=avc1.42E01E,mp4a.40.2",
                              "video/mp4;codecs=avc1",
                              "video/mp4"];
            for (var i = 0; i < candidates.length; i++) {
                try {
                    if (window.MediaRecorder && MediaRecorder.isTypeSupported(candidates[i])) {
                        return candidates[i];
                    }
                } catch (e) {}
            }
            return null;
        }

        window.__gsClipAvailable = function() {
            return !!(window.MediaRecorder && container() && source());
        };

        window.__gsClipStart = function(bitrate) {
            if (recorder) return false;
            var media = source();
            var type = container();
            if (!media || !type) return false;
            try {
                recorder = new MediaRecorder(media, {
                    mimeType: type,
                    videoBitsPerSecond: bitrate || 8000000
                });
            } catch (e) {
                recorder = null;
                return false;
            }
            sequence = 0;
            recorder.ondataavailable = function(event) {
                if (!event.data || !event.data.size) return;
                // Numbered here rather than on the way out: turning a blob
                // into text is asynchronous and finishes out of order.
                var index = sequence++;
                var reader = new FileReader();
                reader.onloadend = function() {
                    var text = String(reader.result || "");
                    var comma = text.indexOf(",");
                    post({ type: "clipChunk", index: index,
                           data: comma >= 0 ? text.slice(comma + 1) : "" });
                };
                reader.readAsDataURL(event.data);
            };
            recorder.onstop = function() {
                recorder = null;
                post({ type: "clipEnd" });
            };
            recorder.onerror = function() {
                recorder = null;
                post({ type: "clipFailed", message: "the page stopped recording" });
            };
            // A timeslice keeps the clip flowing out of the page rather than
            // piling up in its memory until the end, which is the difference
            // between a long clip and the app being reclaimed mid-recording.
            recorder.start(1000);
            return true;
        };

        window.__gsClipStop = function() {
            if (!recorder) return false;
            try {
                recorder.stop();
            } catch (e) {
                recorder = null;
                post({ type: "clipEnd" });
            }
            return true;
        };
    })();
    """#

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
    static func betterXCloudPrefsJS(global: [String: String],
                                    stream: [String: String]) -> String {
        func assignments(_ values: [String: String]) -> String {
            values.map { key, value in
                "data[\(jsString(key))] = \(jsString(value));"
            }.joined(separator: "\n                    ")
        }

        return """
        (function() {
            try {
                if ((location.host || "").indexOf("xbox.com") === -1) return;

                function write(storageKey, apply) {
                    var data = {};
                    try {
                        data = JSON.parse(localStorage.getItem(storageKey) || "{}") || {};
                    } catch (e) { data = {}; }
                    apply(data);
                    localStorage.setItem(storageKey, JSON.stringify(data));
                }

                write("BetterXcloud", function(data) {
                    \(assignments(global))
                });
                write("BetterXcloud.Stream", function(data) {
                    \(assignments(stream))
                });
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
