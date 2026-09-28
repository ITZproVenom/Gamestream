import Foundation

/// GameStream's own in-page enhancement layer.
///
/// Better xCloud is a capable script, but it is someone else's: its settings
/// live in two stores it chose, its menu is built for a mouse, its stats bar
/// draws over ours, and every upgrade is a chance for a class name we press
/// to disappear. This is the replacement, built on the one hook that actually
/// matters.
///
/// Almost everything worth controlling in a WebRTC stream is decided once, in
/// the session description, before a single frame arrives: which codec is
/// used, which profile, and what bitrate the sender is allowed. So the layer
/// wraps `RTCPeerConnection` before the page can construct one and edits the
/// descriptions on their way through. Everything else — filters, hiding site
/// furniture — is ordinary DOM work layered on top.
///
/// It also reports what the server actually offered, which is the only honest
/// way to answer questions about codecs and HDR: not by adding a switch, but
/// by reading the offer.
enum StreamEnhancer {

    /// What the layer should do, handed over as JSON so the script itself
    /// stays free of string building.
    struct Configuration: Encodable {
        var enabled: Bool
        var preferHEVC: Bool
        var bitrateKbps: Int          // 0 leaves the server's own choice alone
        var sharpness: Int            // 0-5
        var saturation: Int           // percent
        var contrast: Int             // percent
        var brightness: Int           // percent
        var zoom: Int                 // percent, 100 = fit
        var fillScreen: Bool          // crop to fill instead of letterboxing
        var volumeBoost: Int          // percent, 100 = untouched
        var hideTouchControls: Bool
        var hideSiteOverlays: Bool
        var codecProfile: String      // "", "baseline", "main", "high"
        var preferIPv6: Bool
        var blockTracking: Bool
        var skipSplash: Bool
        var deadzone: Int             // percent of stick travel ignored
        var triggerDeadzone: Int      // percent of trigger travel ignored
        var vibrationScale: Int       // percent applied to rumble magnitudes
        var aspectRatio: String       // "", "16:9", "16:10", "18:9", "21:9", "4:3"
        var videoPosition: String     // "center", "top", "bottom"
        var maxFps: Int               // 0 = uncapped
        var resolution: String        // "", "720p", "1080p"
        var preventResolutionDrops: Bool
        var touchMode: String         // "default", "all", "off"
        var touchOpacity: Int         // percent
        var blockSocial: Bool
        var reduceAnimations: Bool
        var hideScrollbars: Bool
        var hideLoadingArt: Bool
        var pollingRate: Int          // milliseconds between gamepad reads
    }

    static func script(_ configuration: Configuration) -> String {
        let json = (try? JSONEncoder().encode(configuration))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "window.__gsEnhanceConfig = \(json);\n" + core
    }

    private static let core = #"""
    (function() {
        if (window.__gsEnhance) return;
        window.__gsEnhance = true;

        var config = window.__gsEnhanceConfig || {};
        // Note what is *not* here: an early return when the layer is
        // switched off. Returning meant __gsEnhanceApply was never defined,
        // so turning the layer back on mid-session did nothing at all and
        // said nothing about it. The hooks are always installed; every
        // effect below asks whether it is enabled.
        function on() { return !!config.enabled; }

        var report = { codecs: [], chosen: null, bitrate: null, notes: [] };
        window.__gsEnhanceReport = report;

        function post(payload) {
            try {
                window.webkit.messageHandlers.gamestream.postMessage(payload);
            } catch (e) {}
        }

        // ---- Session description editing -------------------------------
        //
        // The description is a line-oriented text format. Everything below
        // works on whole lines and leaves anything it does not recognise
        // exactly as it found it: a description this client does not fully
        // understand still has to survive unchanged.

        function videoSection(lines) {
            var start = -1;
            for (var i = 0; i < lines.length; i++) {
                if (lines[i].indexOf("m=video") === 0) { start = i; break; }
            }
            if (start === -1) return null;
            var end = lines.length;
            for (var j = start + 1; j < lines.length; j++) {
                if (lines[j].indexOf("m=") === 0) { end = j; break; }
            }
            return { start: start, end: end };
        }

        /// Every codec the video section offers, as payload type and name.
        function codecsIn(lines, section) {
            var found = [];
            for (var i = section.start; i < section.end; i++) {
                var match = /^a=rtpmap:(\d+)\s+([A-Za-z0-9\-]+)\//.exec(lines[i]);
                if (match) found.push({ payload: match[1], name: match[2] });
            }
            return found;
        }

        /// Moves one codec to the front of the m=video payload list.
        ///
        /// The order of payload types on the m-line is the preference order.
        /// Nothing is removed: a codec the server insists on must still be
        /// available, or the negotiation fails outright instead of falling
        /// back.
        function prefer(lines, section, name) {
            var codecs = codecsIn(lines, section);
            var wanted = [];
            for (var i = 0; i < codecs.length; i++) {
                if (codecs[i].name.toUpperCase() === name.toUpperCase()) {
                    wanted.push(codecs[i].payload);
                }
            }
            if (!wanted.length) return false;

            var parts = lines[section.start].split(" ");
            var head = parts.slice(0, 3);
            var payloads = parts.slice(3);
            var reordered = wanted.slice();
            for (var p = 0; p < payloads.length; p++) {
                if (reordered.indexOf(payloads[p]) === -1) reordered.push(payloads[p]);
            }
            lines[section.start] = head.concat(reordered).join(" ");
            return true;
        }

        /// Sets the session-level bandwidth line for video.
        ///
        /// This is the one place a client can state a bitrate at all. It is a
        /// ceiling the sender agrees to respect, never a floor: asking for
        /// more than the encoder wants to send changes nothing.
        function setBitrate(lines, section, kbps) {
            for (var i = section.start + 1; i < section.end; i++) {
                if (lines[i].indexOf("b=AS:") === 0) {
                    lines[i] = "b=AS:" + kbps;
                    return;
                }
            }
            lines.splice(section.start + 1, 0, "b=AS:" + kbps);
        }

        /// H.264 profiles are distinguished by the first byte of
        /// profile-level-id on the codec's fmtp line, not by the codec name:
        /// 42 is baseline, 4d main, 64 high. Higher profiles compress better
        /// at the same bitrate, which is the whole reason to ask.
        function preferProfile(lines, section, profile) {
            var prefix = profile === "high" ? "64"
                       : profile === "main" ? "4d"
                       : profile === "baseline" ? "42" : null;
            if (!prefix) return false;

            var wanted = [];
            for (var i = section.start; i < section.end; i++) {
                var match = /^a=fmtp:(\d+)\s+(.*)$/.exec(lines[i]);
                if (!match) continue;
                var id = /profile-level-id=([0-9a-fA-F]{6})/.exec(match[2]);
                if (id && id[1].toLowerCase().indexOf(prefix) === 0) wanted.push(match[1]);
            }
            if (!wanted.length) return false;

            var parts = lines[section.start].split(" ");
            var reordered = wanted.slice();
            var payloads = parts.slice(3);
            for (var p = 0; p < payloads.length; p++) {
                if (reordered.indexOf(payloads[p]) === -1) reordered.push(payloads[p]);
            }
            lines[section.start] = parts.slice(0, 3).concat(reordered).join(" ");
            return true;
        }

        /// Puts IPv6 candidates ahead of IPv4 ones. On a network with real
        /// IPv6 this often avoids a layer of carrier NAT; where there is no
        /// IPv6 there is nothing to reorder and nothing changes.
        function preferIPv6Candidates(lines) {
            var sixes = [];
            var rest = [];
            var moved = false;
            for (var i = 0; i < lines.length; i++) {
                if (lines[i].indexOf("a=candidate:") !== 0) { rest.push(lines[i]); continue; }
                if (lines[i].indexOf(":") !== -1 && /\s[0-9a-fA-F]*:[0-9a-fA-F:]+\s/.test(lines[i])) {
                    sixes.push(lines[i]);
                    moved = true;
                } else {
                    rest.push(lines[i]);
                }
            }
            if (!moved) return false;
            // Reinsert the IPv6 candidates at the first candidate position.
            var at = rest.findIndex(function(line) { return line.indexOf("a=candidate:") === 0; });
            if (at < 0) at = rest.length;
            Array.prototype.splice.apply(rest, [at, 0].concat(sixes));
            lines.length = 0;
            Array.prototype.push.apply(lines, rest);
            return true;
        }

        /// Replaces or inserts one `a=` attribute in the video section.
        function setAttribute(lines, section, name, value) {
            var prefix = "a=" + name + ":";
            for (var i = section.start + 1; i < section.end; i++) {
                if (lines[i].indexOf(prefix) === 0) {
                    lines[i] = prefix + value;
                    return;
                }
            }
            lines.splice(section.end, 0, prefix + value);
            section.end++;
        }

        function edit(sdp) {
            if (!on()) return sdp;
            if (typeof sdp !== "string" || !sdp.length) return sdp;
            // Fresh notes per negotiation. Accumulating them across
            // reconnects turned the report into a transcript.
            report.notes = [];
            var lines = sdp.split(/\r\n|\n/);
            var section = videoSection(lines);
            if (!section) return sdp;

            report.codecs = codecsIn(lines, section).map(function(c) { return c.name; })
                .filter(function(name, index, all) { return all.indexOf(name) === index; });

            if (config.preferHEVC) {
                if (prefer(lines, section, "H265")) {
                    report.chosen = "H265";
                    report.notes.push("asked for H.265");
                } else {
                    report.notes.push("H.265 was not offered");
                }
            }
            if (config.codecProfile) {
                if (preferProfile(lines, section, config.codecProfile)) {
                    report.notes.push("asked for H.264 " + config.codecProfile);
                } else {
                    report.notes.push("H.264 " + config.codecProfile + " was not offered");
                }
            }
            if (config.preferIPv6) {
                if (preferIPv6Candidates(lines)) report.notes.push("IPv6 first");
            }
            if (config.maxFps > 0) {
                // Stated as a receiver framerate on the video section. The
                // sender is free to ignore it; when it does not, a lower cap
                // spends the same bitrate on fewer, better frames.
                setAttribute(lines, section, "framerate", String(config.maxFps));
                report.notes.push("asked for " + config.maxFps + " fps");
            }
            if (config.resolution) {
                var size = config.resolution === "720p" ? [1280, 720] : [1920, 1080];
                setAttribute(lines, section, "imageattr",
                             "* send * recv [x=" + size[0] + ",y=" + size[1] + "]");
                report.notes.push("asked for " + config.resolution);
            }
            if (config.bitrateKbps > 0) {
                setBitrate(lines, section, config.bitrateKbps);
                report.bitrate = config.bitrateKbps;
            }
            post({ type: "enhance", codecs: report.codecs.join(", "),
                   notes: report.notes.join("; ") });
            return lines.join("\r\n");
        }

        // ---- The hook ---------------------------------------------------

        var Native = window.RTCPeerConnection;
        if (typeof Native === "function") {
            var Wrapped = function(configuration, constraints) {
                var pc = new Native(configuration, constraints);

                var setLocal = pc.setLocalDescription.bind(pc);
                pc.setLocalDescription = function(description) {
                    try {
                        if (description && description.sdp) {
                            description = {
                                type: description.type,
                                sdp: edit(description.sdp)
                            };
                        }
                    } catch (e) {}
                    return setLocal(description);
                };

                var setRemote = pc.setRemoteDescription.bind(pc);
                pc.setRemoteDescription = function(description) {
                    try {
                        if (description && description.sdp) {
                            var lines = description.sdp.split(/\r\n|\n/);
                            var section = videoSection(lines);
                            if (section) {
                                var names = codecsIn(lines, section).map(function(c) {
                                    return c.name;
                                }).filter(function(n, i, a) { return a.indexOf(n) === i; });
                                post({ type: "enhance",
                                       codecs: names.join(", "),
                                       notes: "server offered" });
                            }
                        }
                    } catch (e) {}
                    return setRemote(description);
                };

                return pc;
            };
            Wrapped.prototype = Native.prototype;
            Wrapped.generateCertificate = Native.generateCertificate;
            window.RTCPeerConnection = Wrapped;
            if (window.webkitRTCPeerConnection) window.webkitRTCPeerConnection = Wrapped;
        }

        // ---- Controller ---------------------------------------------------
        //
        // The page reads pads through the Gamepad API, so a deadzone applied
        // here is applied before the page ever sees the stick. Rescaling the
        // remainder matters as much as the cut: a raw cut leaves a dead step
        // at the edge of the zone where the stick suddenly jumps.

        function shapeAxis(value, cut) {
            if (!cut) return value;
            var magnitude = Math.abs(value);
            if (magnitude <= cut) return 0;
            var scaled = (magnitude - cut) / (1 - cut);
            return value < 0 ? -scaled : scaled;
        }

        function installGamepadShaping() {
            var original = navigator.getGamepads;
            if (typeof original !== "function") return;
            var lastRead = 0;
            var cached = null;
            navigator.getGamepads = function() {
                // A polling floor. The page reads pads every animation frame;
                // on a slow pad that is wasted work, and on a fast one the
                // extra reads are what make input feel current, so this is a
                // choice rather than a default.
                var interval = on() ? (config.pollingRate || 0) : 0;
                if (interval > 0 && cached) {
                    var now = Date.now();
                    if (now - lastRead < interval) return cached;
                    lastRead = now;
                }
                var pads = original.apply(navigator, arguments);
                var stickCut = on() ? (config.deadzone || 0) / 100 : 0;
                var triggerCut = on() ? (config.triggerDeadzone || 0) / 100 : 0;
                if (!stickCut && !triggerCut) { cached = pads; return pads; }

                var shaped = [];
                for (var i = 0; i < pads.length; i++) {
                    var pad = pads[i];
                    if (!pad) { shaped.push(pad); continue; }
                    var axes = Array.prototype.slice.call(pad.axes);
                    for (var a = 0; a < axes.length; a++) {
                        axes[a] = shapeAxis(axes[a], stickCut);
                    }
                    var buttons = Array.prototype.slice.call(pad.buttons);
                    if (triggerCut) {
                        // 6 and 7 are the triggers in the standard mapping.
                        for (var b = 6; b <= 7 && b < buttons.length; b++) {
                            var button = buttons[b];
                            var value = shapeAxis(button.value, triggerCut);
                            buttons[b] = {
                                pressed: value > 0,
                                touched: button.touched,
                                value: value
                            };
                        }
                    }
                    // A plain object: the real Gamepad is read-only, and the
                    // page only ever reads these fields off it.
                    shaped.push({
                        id: pad.id, index: pad.index, connected: pad.connected,
                        mapping: pad.mapping, timestamp: pad.timestamp,
                        axes: axes, buttons: buttons,
                        vibrationActuator: pad.vibrationActuator,
                        hapticActuators: pad.hapticActuators
                    });
                }
                cached = shaped;
                return shaped;
            };
        }

        installGamepadShaping();

        // ---- Network noise --------------------------------------------------

        /// Drops the page's telemetry without touching anything it needs.
        ///
        /// Matched on host, not on a guess about what a URL is for: blocking
        /// by keyword catches real API calls and breaks the player.
        var BLOCKED = [
            "browser.events.data.microsoft.com",
            "mobile.events.data.microsoft.com",
            "dc.services.visualstudio.com",
            "js.monitor.azure.com",
            "google-analytics.com",
            "googletagmanager.com"
        ];

        function blocked(url) {
            if (!on() || !config.blockTracking) return false;
            try {
                var host = new URL(url, location.href).hostname;
                for (var i = 0; i < BLOCKED.length; i++) {
                    if (host === BLOCKED[i] || host.indexOf("." + BLOCKED[i]) !== -1) {
                        return true;
                    }
                }
            } catch (e) {}
            return false;
        }

        function installBlocking() {
            var fetchOriginal = window.fetch;
            if (typeof fetchOriginal === "function") {
                window.fetch = function(input) {
                    var url = typeof input === "string" ? input : (input && input.url);
                    if (url && blocked(url)) {
                        return Promise.resolve(new Response("", { status: 204 }));
                    }
                    return fetchOriginal.apply(window, arguments);
                };
            }
            var openOriginal = XMLHttpRequest.prototype.open;
            XMLHttpRequest.prototype.open = function(method, url) {
                this.__gsBlocked = url && blocked(url);
                return openOriginal.apply(this, arguments);
            };
            var sendOriginal = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.send = function() {
                if (this.__gsBlocked) return;
                return sendOriginal.apply(this, arguments);
            };
            if (navigator.sendBeacon) {
                var beacon = navigator.sendBeacon.bind(navigator);
                navigator.sendBeacon = function(url) {
                    if (blocked(url)) return true;
                    return beacon.apply(navigator, arguments);
                };
            }
        }

        installBlocking();

        // ---- Picture ------------------------------------------------------

        var STYLE_ID = "gamestream-enhance";
        var FILTER_ID = "gamestream-sharpen";

        /// A sharpening convolution, built to the requested strength.
        ///
        /// CSS has no sharpen filter, so this is a real 3x3 kernel in an
        /// inline SVG. The centre weight keeps the sum at one so the picture
        /// does not get brighter as it gets sharper.
        function installSharpen(strength) {
            var existing = document.getElementById(FILTER_ID);
            if (existing && existing.parentNode) existing.parentNode.removeChild(existing);
            if (strength <= 0) return false;

            var edge = -0.12 * strength;
            var centre = 1 - 4 * edge;
            var svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
            svg.setAttribute("id", FILTER_ID);
            svg.setAttribute("width", "0");
            svg.setAttribute("height", "0");
            svg.style.position = "absolute";
            svg.innerHTML =
                '<filter id="gamestream-sharpen-filter" x="0" y="0" width="100%" height="100%">' +
                '<feConvolveMatrix order="3" preserveAlpha="true" kernelMatrix="' +
                '0 ' + edge + ' 0 ' + edge + ' ' + centre + ' ' + edge + ' 0 ' + edge + ' 0' +
                '"/></filter>';
            document.documentElement.appendChild(svg);
            return true;
        }

        /// Raises the stream past the element's own volume ceiling.
        ///
        /// A media element cannot go above 1.0. A gain node can, and it is
        /// built once per element: taking a second source from the same
        /// element is an error that silences it for good.
        var amplified = null;
        var gain = null;
        var audioContext = null;
        function applyVolume(video) {
            var boost = on() ? (config.volumeBoost || 100) / 100 : 1;
            try {
                if (boost <= 1.001) {
                    if (gain) gain.gain.value = 1;
                    return;
                }
                if (amplified !== video) {
                    var Context = window.AudioContext || window.webkitAudioContext;
                    if (!Context) return;
                    // One context for the life of the page. Building a new
                    // one per element leaks them, and iOS allows very few.
                    if (!audioContext) audioContext = new Context();
                    var source = audioContext.createMediaElementSource(video);
                    gain = audioContext.createGain();
                    source.connect(gain);
                    gain.connect(audioContext.destination);
                    amplified = video;
                }
                // Routing a media element through WebAudio moves its audio
                // into the graph. A suspended graph therefore does not mean
                // "no boost", it means silence — so the state is resumed,
                // and resumed again on the next touch if the page had no
                // gesture to spend yet.
                if (audioContext && audioContext.state === "suspended") {
                    audioContext.resume();
                    document.addEventListener("touchend", function once() {
                        document.removeEventListener("touchend", once);
                        if (audioContext) audioContext.resume();
                    });
                }
                if (gain) gain.gain.value = Math.min(boost, 4);
            } catch (e) {}
        }

        function applyPicture() {
            var parts = [];
            if (!on()) {
                installSharpen(0);
                var off = document.getElementById(STYLE_ID);
                if (off && off.parentNode) off.parentNode.removeChild(off);
                var element = document.querySelector("video");
                if (element) applyVolume(element);
                return;
            }
            if (config.saturation && config.saturation !== 100) {
                parts.push("saturate(" + (config.saturation / 100) + ")");
            }
            if (config.contrast && config.contrast !== 100) {
                parts.push("contrast(" + (config.contrast / 100) + ")");
            }
            if (config.brightness && config.brightness !== 100) {
                parts.push("brightness(" + (config.brightness / 100) + ")");
            }
            if (installSharpen(config.sharpness || 0)) {
                parts.push("url(#gamestream-sharpen-filter)");
            }

            var rules = [];
            if (parts.length) {
                rules.push("video { filter: " + parts.join(" ") + " !important; }");
            }
            rules.push("video { object-fit: "
                       + (config.fillScreen ? "cover" : "contain") + " !important; }");

            // A forced ratio is applied to the element, not the picture: the
            // stream arrives at whatever shape the server sends and the box
            // it is drawn into decides what is cropped or padded.
            if (config.aspectRatio) {
                rules.push("video { aspect-ratio: "
                           + config.aspectRatio.replace(":", " / ") + " !important; "
                           + "margin: auto !important; }");
            }
            if (config.videoPosition && config.videoPosition !== "center") {
                rules.push("video { object-position: center "
                           + (config.videoPosition === "top" ? "top" : "bottom")
                           + " !important; }");
            }
            if (config.touchOpacity && config.touchOpacity !== 100) {
                rules.push("#TouchControls, [class*=\"TouchControl\"] { opacity: "
                           + (config.touchOpacity / 100) + " !important; }");
            }
            if (config.reduceAnimations) {
                rules.push("*, *::before, *::after { animation-duration: 0.001s !important; "
                           + "transition-duration: 0.001s !important; }");
            }
            if (config.hideScrollbars) {
                rules.push("::-webkit-scrollbar { display: none !important; }");
            }
            if (config.hideLoadingArt) {
                rules.push("[class*=\"GameArt\"], [class*=\"BackgroundImage\"] "
                           + "{ display: none !important; }");
            }
            if (config.blockSocial) {
                // Whole sections of the site the app does not use and that
                // only cost requests and layout work.
                rules.push("[class*=\"SocialBar\"], [class*=\"FriendsList\"], "
                           + "[class*=\"ChatPanel\"], [class*=\"NewsFeed\"] "
                           + "{ display: none !important; }");
            }
            var zoom = (config.zoom || 100) / 100;
            if (Math.abs(zoom - 1) > 0.001) {
                rules.push("video { transform: scale(" + zoom + ") !important; }");
            }
            if (config.hideTouchControls) {
                rules.push("#TouchControls, [class*=\"TouchControl\"], "
                           + "[class*=\"touch-control\"] { display: none !important; }");
            }
            if (config.hideSiteOverlays) {
                rules.push("#StreamHud { display: none !important; }");
            }
            if (config.skipSplash) {
                // The launch animation and the big piece of key art behind
                // it, both of which only delay the picture.
                rules.push("[class*=\"SplashScreen\"], [class*=\"splash\"], "
                           + "[class*=\"GameArtBackground\"] { display: none !important; }");
            }

            var video = document.querySelector("video");
            if (video) applyVolume(video);

            var style = document.getElementById(STYLE_ID);
            if (!rules.length) {
                if (style && style.parentNode) style.parentNode.removeChild(style);
                return;
            }
            if (!style) {
                style = document.createElement("style");
                style.id = STYLE_ID;
                (document.head || document.documentElement).appendChild(style);
            }
            style.textContent = rules.join("\n");
        }

        /// Reapplied as the page builds itself: the player is created long
        /// after this script runs, and a style added to an empty document
        /// does not survive the page replacing its own head.
        function watch() {
            applyPicture();
            var tries = 0;
            var timer = setInterval(function() {
                tries++;
                if (tries > 40) { clearInterval(timer); return; }
                if (!document.getElementById(STYLE_ID)) applyPicture();
            }, 500);
        }

        if (document.readyState === "loading") {
            document.addEventListener("DOMContentLoaded", watch);
        } else {
            watch();
        }

        /// Lets the app change the picture without reloading the page.
        window.__gsEnhanceApply = function(next) {
            config = next || config;
            window.__gsEnhanceConfig = config;
            applyPicture();
            return "applied";
        };
    })();
    """#
}
