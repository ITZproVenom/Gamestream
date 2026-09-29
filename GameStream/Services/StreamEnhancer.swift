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
        var hideTouchControls: Bool
    }

    static func json(_ configuration: Configuration) -> String {
        (try? JSONEncoder().encode(configuration))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    static func script(_ configuration: Configuration) -> String {
        "window.__gsEnhanceConfig = \(json(configuration));\n" + core
    }

    private static let core = #"""
    (function() {
        if (window.__gsEnhance) return;
        window.__gsEnhance = true;

        var config = window.__gsEnhanceConfig || {};
        if (!config.enabled) return;

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

        function edit(sdp) {
            if (typeof sdp !== "string" || !sdp.length) return sdp;
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
                    report.notes.push("H.265 was not offered by the server");
                }
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

        function applyPicture() {
            var parts = [];
            if (config.saturation && config.saturation !== 100) {
                parts.push("saturate(" + (config.saturation / 100) + ")");
            }
            if (config.contrast && config.contrast !== 100) {
                parts.push("contrast(" + (config.contrast / 100) + ")");
            }
            if (installSharpen(config.sharpness || 0)) {
                parts.push("url(#gamestream-sharpen-filter)");
            }

            var rules = [];
            if (parts.length) {
                rules.push("video { filter: " + parts.join(" ") + " !important; }");
            }
            if (config.hideTouchControls) {
                rules.push("#TouchControls, [class*=\"TouchControl\"], "
                           + "[class*=\"touch-control\"] { display: none !important; }");
            }

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
