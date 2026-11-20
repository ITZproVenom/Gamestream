// A test harness for the session-settings script: a fake session request,
// and a check that the fields the app asks for are the fields that end up
// in the request - with and without the touch controls wanted.
//
// The rule that decides which request is a session is based on where the
// request is going. A request that merely mentions a session field - a
// telemetry upload, for instance - must be left alone, and the log must
// name the address of the request that was changed.

const fs = require('fs');
const vm = require('vm');

const posted = [];

const sessionBody = JSON.stringify({
    offeringId: "xcloud",
    data: {
        titleId: "9NNFG8BQRCXL",
        inputConfiguration: { enableGamepadInput: true, sensorInputPollingRateInHz: 60 },
        videoConfiguration: { enableHevc: false, useSoftwareRendering: true, decoderType: 1 },
        audioConfiguration: { useHardwareAudioDecoding: false }
    }
});

const sandbox = {
    window: {
        navigator: {},
        performance: { now: () => 1 },
        addEventListener: () => {},
    },
    performance: { now: () => 1 },
    Promise, Object, JSON, Array, String, Number, Boolean, Error, Date, Math,
    setTimeout: (fn, ms) => setTimeout(fn, ms),
    clearTimeout: (id) => clearTimeout(id),
};
sandbox.navigator = sandbox.window.navigator;
sandbox.window.webkit = {
    messageHandlers: { gamestream: { postMessage: (p) => posted.push(p) } }
};

vm.createContext(sandbox);
let sent = null;
sandbox.window.fetch = function (input, init) {
    sent = (init && init.body !== undefined) ? init.body : (input && input._body);
    return Promise.resolve({ ok: true, clone: function () { return this; },
                            text: function () { return Promise.resolve("{}"); } });
};
sandbox.window.XMLHttpRequest = class {
    constructor() { this.responseType = ""; this.responseText = ""; }
    open() {} setRequestHeader() {} send(b) { sent = b; }
    addEventListener() {}
};

vm.runInContext(fs.readFileSync(process.argv[2], "utf8"), sandbox);

function check(name, ok, detail) {
    console.log((ok ? "ok   " : "FAIL ") + name + (detail ? "  -> " + detail : ""));
    if (!ok) process.exitCode = 1;
}

function sessionReport() {
    return posted.find(p => p.state && p.state.indexOf("session") === 0);
}

(async function () {
    sandbox.window.__gsWantTouch = true;
    sandbox.window.__gsPreferHEVC = true;
    await sandbox.window.fetch("https://xhome.gssv-play-prod.xboxlive.com/v2/sessions/abc", {
        method: "POST", body: sessionBody
    });
    check("the request body was sent", !!sent);
    const parsed = JSON.parse(String(sent || "{}"));
    const video = (parsed.data || {}).videoConfiguration || {};
    const input = (parsed.data || {}).inputConfiguration || {};
    check("HEVC is asked for", video.enableHevc === true, JSON.stringify(video));
    check("the GPU is asked to draw it", video.useSoftwareRendering === false);
    check("software decoding is not", video.decoderType === 4, String(video.decoderType));
    check("the sound is decoded in hardware",
          ((parsed.data || {}).audioConfiguration || {}).useHardwareAudioDecoding === true);
    // The resolution and the bitrate are NOT fields of the session's
    // configuration: sending them made the service answer with "Something
    // went wrong" and the whole launch failed.
    check("the resolution is not put in the session", video.resolution === undefined, String(video.resolution));
    check("the bitrate is not put in the session", video.maxBitrateMbps === undefined, String(video.maxBitrateMbps));
    check("touch is asked for", input.enableTouchInput === true, JSON.stringify(input));
    check("the touch points are asked for", input.maxTouchPoints >= 10, String(input.maxTouchPoints));

    // The wrapper around the configuration must not be given one of its
    // own: the service has no such field and refuses the session.
    check("no configuration is added to the wrapper", parsed.videoConfiguration === undefined,
          JSON.stringify(parsed.videoConfiguration));
    check("no input configuration is added to the wrapper", parsed.inputConfiguration === undefined,
          JSON.stringify(parsed.inputConfiguration));
    check("the offering is left alone", parsed.offeringId === "xcloud", String(parsed.offeringId));

    // The log has to say which request was changed, so a wrong guess is
    // visible the next time.
    const report = sessionReport();
    check("the session change is reported", !!report, report ? report.detail : "nothing reported");
    check("the report names the request", report && report.detail.indexOf("/v2/sessions/abc") !== -1,
          report ? report.detail : "");

    sandbox.window.__gsWantTouch = false;
    sent = null;
    await sandbox.window.fetch("https://xhome.gssv-play-prod.xboxlive.com/v2/sessions/abc", {
        method: "POST", body: sessionBody
    });
    const second = JSON.parse(String(sent || "{}"));
    const v2 = (second.data || {}).videoConfiguration || {};
    check("without touch, HEVC is still asked for", v2.enableHevc === true, JSON.stringify(v2));
    const i2 = (second.data || {}).inputConfiguration;
    check("without touch, no touch fields are added",
          !i2 || i2.enableTouchInput === undefined, JSON.stringify(i2));

    // 3. The play request is the one that creates the session. The app
    //    does not say what it is in it: the site sends its own osName and
    //    the service has to see that.
    sent = null;
    await sandbox.window.fetch("https://xhome.gssv-play-prod.xboxlive.com/v2/sessions/home/play", {
        method: "POST", body: JSON.stringify({ offeringId: "xcloud", settings: { osName: "chrome" } })
    });
    const play = JSON.parse(String(sent || "{}"));
    check("the play request is left as the site sent it",
          play.settings && play.settings.osName === "chrome", JSON.stringify(play.settings));
    check("no configuration is added to the play request",
          !play.videoConfiguration && !play.inputConfiguration, JSON.stringify(play));

    // 4. A telemetry upload that quotes a session field is not a session.
    sent = null;
    await sandbox.window.fetch("https://browser.events.data.microsoft.com/OneCollector/1.0/", {
        method: "POST",
        body: JSON.stringify({ name: "session",
                               data: { videoConfiguration: { enableHevc: false, decoderType: 1 } } })
    });
    const telemetry = JSON.parse(String(sent || "{}"));
    check("a telemetry upload is left alone",
          telemetry.data.videoConfiguration.enableHevc === false
          && telemetry.data.videoConfiguration.decoderType === 1,
          JSON.stringify(telemetry.data.videoConfiguration));

    // 5. A request to the service that is not about a session is left
    //    alone too.
    sent = null;
    await sandbox.window.fetch("https://xhome.gssv-play-prod.xboxlive.com/v2/login/user", {
        method: "POST", body: JSON.stringify({ videoConfiguration: { enableHevc: false } })
    });
    const login = JSON.parse(String(sent || "{}"));
    check("a request that is not a session is left alone",
          login.videoConfiguration.enableHevc === false, JSON.stringify(login.videoConfiguration));

    // 6. An unrelated body is left alone.
    sent = null;
    await sandbox.window.fetch("https://browser.events.data.microsoft.com/OneCollector/1.0/", {
        method: "POST", body: '{"name":"something"}'
    });
    check("an unrelated body is left alone", String(sent || "").indexOf("enableHevc") === -1);
})();
