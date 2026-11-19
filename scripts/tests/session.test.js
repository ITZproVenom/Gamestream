// A test harness for the session-settings script: a fake session request,
// and a check that the fields the app asks for are the fields that end up
// in the request - with and without the touch controls wanted.

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

(async function () {
    sandbox.window.__gsWantTouch = true;
    sandbox.window.__gsPreferHEVC = true;
    sandbox.window.__gsResolution = "720p";
    sandbox.window.__gsMaxBitrateKbps = 5000000;
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

    sandbox.window.__gsWantTouch = false;
    sent = null;
    await sandbox.window.fetch("https://xhome.gssv-play-prod.xboxlive.com/v2/sessions/abc", {
        method: "POST", body: sessionBody
    });
    const second = JSON.parse(String(sent || "{}"));
    const v2 = (second.data || {}).videoConfiguration || {};
    check("without touch, HEVC is still asked for", v2.enableHevc === true, JSON.stringify(v2));
    check("without touch, the resolution is still asked for", v2.resolution === "720p");
    const i2 = (second.data || {}).inputConfiguration;
    check("without touch, no touch fields are added",
          !i2 || i2.enableTouchInput === undefined, JSON.stringify(i2));

    // 3. The play request carries the resolution, as the client that tier
    //    calls for.
    sent = null;
    await sandbox.window.fetch("https://xhome.gssv-play-prod.xboxlive.com/v2/sessions/home/play", {
        method: "POST", body: JSON.stringify({ offeringId: "xcloud", settings: {} })
    });
    const play = JSON.parse(String(sent || "{}"));
    check("the play request asks for the resolution", play.settings && play.settings.osName === "android",
          JSON.stringify(play.settings));
    check("the session fields are left out of the play request",
          !play.videoConfiguration && !play.inputConfiguration, JSON.stringify(play));

    sent = null;
    await sandbox.window.fetch("https://browser.events.data.microsoft.com/OneCollector/1.0/", {
        method: "POST", body: '{"name":"something"}'
    });
    check("an unrelated body is left alone", String(sent || "").indexOf("enableHevc") === -1);
})();
