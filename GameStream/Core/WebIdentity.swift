import Foundation

/// Makes the stream player's JavaScript identity agree with its desktop
/// Chrome user agent.
///
/// The stream webview already sends a Windows Chrome UA and reports
/// `navigator.standalone`, but WKWebView still answers `iPhone` for
/// `navigator.platform`, an Apple `navigator.vendor`, and has no
/// `navigator.userAgentData`. If Xbox's home-screen gate keys on any of those,
/// the page still treats the player as iOS Safari. This aligns them, and
/// reports what the page sees (and any "Add to Home Screen" gate text) to
/// Diagnostics so a failure is explained instead of guessed at.
enum WebIdentity {
    static let script = #"""
    (function() {
        if (window.__gsIdentity) return;
        window.__gsIdentity = true;
        var isTop = window === window.top;

        function post(detail) {
            try {
                window.webkit.messageHandlers.gamestream.postMessage({
                    type: "identity", detail: detail });
            } catch (e) {}
        }
        function define(target, name, value) {
            try {
                Object.defineProperty(target, name, {
                    get: function() { return value; }, configurable: true });
            } catch (e) {}
        }

        define(navigator, "platform", "Win32");
        define(navigator, "vendor", "Google Inc.");
        define(navigator, "standalone", true);

        if (!navigator.userAgentData) {
            var brands = [{ brand: "Chromium", version: "131" },
                          { brand: "Google Chrome", version: "131" },
                          { brand: "Not_A Brand", version: "24" }];
            define(navigator, "userAgentData", {
                brands: brands, mobile: false, platform: "Windows",
                getHighEntropyValues: function() {
                    return Promise.resolve({ brands: brands, mobile: false,
                        platform: "Windows", platformVersion: "15.0.0",
                        architecture: "x86", bitness: "64", model: "",
                        uaFullVersion: "131.0.0.0", fullVersionList: brands });
                },
                toJSON: function() {
                    return { brands: brands, mobile: false, platform: "Windows" };
                }
            });
        }

        function snapshot(stage) {
            var p = [stage, location.host + location.pathname];
            try { p.push("ua=" + navigator.userAgent); } catch (e) {}
            try { p.push("platform=" + navigator.platform); } catch (e) {}
            try { p.push("standalone=" + navigator.standalone); } catch (e) {}
            try { p.push("touch=" + navigator.maxTouchPoints); } catch (e) {}
            post(p.join(" | "));
        }

        if (isTop) {
            snapshot("start");
            var checks = 0, reported = false;
            var timer = setInterval(function() {
                if (++checks > 60 || reported) { clearInterval(timer); return; }
                try {
                    var href = (location.href || "").toLowerCase();
                    if (href.indexOf("/play/") === -1 && href.indexOf("/stream/") === -1
                        && href.indexOf("/products/") === -1) return;
                    var text = (document.body && document.body.innerText) || "";
                    var m = /add to home screen|home screen/i.exec(text);
                    if (!m) return;
                    reported = true;
                    post("home-screen gate text: " + text.slice(
                        Math.max(0, m.index - 80), m.index + 160).replace(/\s+/g, " "));
                    snapshot("gate");
                } catch (e) {}
            }, 1000);
        }
    })();
    """#
}
