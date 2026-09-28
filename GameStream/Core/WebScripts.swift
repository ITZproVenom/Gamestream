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
                    // An expired token is not a session. This path did not
                    // check, so a stale one was reported as signed in and
                    // everything built on it failed later with a 401.
                    var stale = direct && direct.expiration
                        && Date.parse(direct.expiration) <= Date.now();
                    if (direct && usable(direct.token) && !stale) {
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

        // Only changes are worth sending. The interval below exists to catch
        // a route change that fires no event, not to repeat the same page
        // twice a second: posting unconditionally filled the app's log with
        // one identical line every two seconds for the whole session.
        var lastReported = null;

        function report() {
            try {
                var href = location.href || "";
                var kind = classify(href);
                var signature = kind + " " + href;
                if (signature === lastReported) return;
                lastReported = signature;
                window.webkit.messageHandlers.gamestream.postMessage({
                    type: "nav",
                    href: href,
                    kind: kind,
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
        // Said once per distinct message: the dialog stays on screen, and
        // reporting it every poll drove the app's reconnect budget to zero
        // in a few seconds.
        var lastError = "";
        setInterval(function() {
            try {
                var node = document.querySelector('[class*="ErrorScreen"], [class*="error-screen"], [data-testid*="error"]');
                if (!node) { lastError = ""; return; }
                var text = (node.innerText || "").trim();
                if (text.length > 4 && text.length < 400 && text !== lastError) {
                    lastError = text;
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
        // Deliberately narrow, and deliberately silent about the video's own
        // shape. This used to force width, height and object-fit with
        // !important, which quietly beat every picture setting in the
        // player's menu: "fill the screen" and the aspect-ratio picker had
        // nothing to win against. The enhancement layer owns the video box;
        // this only owns the document around it.
        var css = [
            "html, body { background: #000 !important; margin: 0 !important; padding: 0 !important; }",
            "header[role=\"banner\"], footer[role=\"contentinfo\"] { display: none !important; }",
            "video { background: #000 !important; }"
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
        window.RTCPeerConnection.generateCertificate = Native.generateCertificate;

        var previous = {};

        function report(payload) {
            try {
                window.webkit.messageHandlers.gamestream.postMessage(payload);
            } catch (e) {}
        }

        async function sample() {
            // A page that reconnects builds a new connection each time and
            // the old ones are never useful again.
            connections = connections.filter(function(pc) {
                return pc && pc.connectionState !== "closed";
            });
            for (var i = 0; i < connections.length; i++) {
                var pc = connections[i];

                var report_ = null;
                try { report_ = await pc.getStats(); } catch (e) { continue; }

                var video = null, pair = null, codecName = "";
                report_.forEach(function(entry) {
                    if (entry.type === "inbound-rtp" && entry.kind === "video") video = entry;
                    // `nominated` is not always set. A succeeded pair is the
                    // one carrying the media either way, and without this
                    // fallback the round trip reads as zero for the whole
                    // session.
                    if (entry.type === "candidate-pair") {
                        if (entry.nominated) pair = entry;
                        else if (!pair && entry.state === "succeeded") pair = entry;
                    }
                });
                if (!video) continue;

                report_.forEach(function(entry) {
                    if (entry.type === "codec" && video && entry.id === video.codecId) {
                        codecName = (entry.mimeType || "").replace("video/", "");
                    }
                });

                var last = previous[video.id] || null;
                var bitrate = 0;
                // Packet loss is reported by WebRTC as a total for the
                // session. Sent on as-is it only ever grows, so anything
                // judging the connection by it decides the stream is
                // struggling a few minutes in and never changes its mind.
                var lost = 0;
                if (last && video.timestamp > last.timestamp) {
                    var seconds = (video.timestamp - last.timestamp) / 1000;
                    bitrate = Math.max(0, Math.round(
                        ((video.bytesReceived - last.bytesReceived) * 8) / seconds / 1000
                    ));
                    lost = Math.max(0, (video.packetsLost || 0) - (last.packetsLost || 0));
                }
                previous[video.id] = {
                    timestamp: video.timestamp,
                    bytesReceived: video.bytesReceived || 0,
                    packetsLost: video.packetsLost || 0
                };

                report({
                    type: "stats",
                    fps: Math.round(video.framesPerSecond || 0),
                    bitrateKbps: bitrate,
                    rttMs: pair && pair.currentRoundTripTime
                        ? Math.round(pair.currentRoundTripTime * 1000) : 0,
                    jitterMs: video.jitter ? Math.round(video.jitter * 1000) : 0,
                    packetsLost: lost,
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

        /// The site's own HUD button, which is what opens the Xbox guide.
        /// Pressing the real control is the only honest way to open it.
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

        /// The site can leave pointer-events off on the HUD subtree while it
        /// animates, which makes a real control inert.
        function enable(node) {
            while (node && node !== document.body) {
                if (node.style && node.style.pointerEvents === "none") {
                    node.style.pointerEvents = "auto";
                }
                node = node.parentElement;
            }
        }

        window.__gsCommand = function(command) {
            var target = null;

            if (command === "quit") {
                // Ending the session properly is the site's own quit, inside
                // the guide. Closing the player only stops the picture; the
                // session stays open and the next launch resumes into it.
                expandHud();
                var QUIT = "a[class*=QuitGameButton], button[class*=QuitGameButton]";
                var quit = document.querySelector(QUIT);
                if (quit) {
                    enable(quit);
                    if (click(quit)) {
                        note(command, "pressed " + describe(quit));
                        return true;
                    }
                }
                // The guide has to open before its quit button exists, and
                // it opens with an animation. Looking for the button in the
                // same breath as opening the guide always found nothing, so
                // quitting fell through to the "no control found" report
                // while the guide sat open on screen.
                var guide = guideButton();
                if (guide) { enable(guide); click(guide); }
                var tries = 0;
                var timer = setInterval(function() {
                    tries++;
                    var found = document.querySelector(QUIT);
                    if (found && visible(found)) {
                        clearInterval(timer);
                        enable(found);
                        note(command, click(found)
                            ? "pressed " + describe(found)
                            : "found the quit control but could not press it");
                        return;
                    }
                    if (tries > 12) {
                        clearInterval(timer);
                        note(command, "the guide did not offer a quit control");
                    }
                }, 150);
                return true;
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
            note(command, "no match; visible controls: " + candidates.join(" | "));
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
}
