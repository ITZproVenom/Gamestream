// The web client consumes clientStreamingConfigOverrides from the answer to
// /configuration. Session request bodies must pass through untouched, and a
// missing override section must never be invented.

const fs = require('fs');
const vm = require('vm');

const posted = [];
const requests = [];
let configurationAnswer = '{}';

class FakeResponse {
    constructor(body, init) {
        init = init || {};
        this._body = String(body === undefined ? '' : body);
        this.status = init.status === undefined ? 200 : init.status;
        this.statusText = init.statusText || '';
        this.headers = init.headers || { 'content-type': 'application/json' };
        this.ok = this.status >= 200 && this.status < 300;
    }
    clone() { return new FakeResponse(this._body, this); }
    text() { return Promise.resolve(this._body); }
}

const sandbox = {
    window: {
        navigator: {},
        performance: { now: () => 1 },
        addEventListener: () => {},
    },
    performance: { now: () => 1 },
    Promise, Object, JSON, Array, String, Number, Boolean, Error, Date, Math,
    Response: FakeResponse,
    setTimeout: (fn, ms) => setTimeout(fn, ms),
    clearTimeout: (id) => clearTimeout(id),
};
sandbox.navigator = sandbox.window.navigator;
sandbox.window.Response = FakeResponse;
sandbox.window.webkit = {
    messageHandlers: { gamestream: { postMessage: (p) => posted.push(p) } }
};

vm.createContext(sandbox);
sandbox.window.fetch = function (input, init) {
    const url = typeof input === 'string' ? input : input.url;
    requests.push({ url, init });
    const body = /\/configuration(?:[?#]|$)/i.test(url) ? configurationAnswer : '{}';
    return Promise.resolve(new FakeResponse(body));
};
sandbox.window.XMLHttpRequest = class {
    open() {} setRequestHeader() {} send() { throw new Error('unexpected XHR'); }
};

vm.runInContext(fs.readFileSync(process.argv[2], 'utf8'), sandbox);

function check(name, ok, detail) {
    console.log((ok ? 'ok   ' : 'FAIL ') + name + (detail ? '  -> ' + detail : ''));
    if (!ok) process.exitCode = 1;
}

function report(state) {
    return posted.find(p => p.state === state);
}

(async function () {
    sandbox.window.__gsWantTouch = true;
    sandbox.window.__gsPreferHEVC = true;
    configurationAnswer = JSON.stringify({
        clientStreamingConfigOverrides: {
            videoConfiguration: {
                enableHevc: false, useSoftwareRendering: true, decoderType: 1,
                existingVideoField: 'preserved'
            },
            inputConfiguration: {
                enableTouchInput: false, maxTouchPoints: 2, enableGamepadInput: true
            },
            audioConfiguration: { useHardwareAudioDecoding: false }
        },
        unrelated: { preserved: true }
    });

    const response = await sandbox.window.fetch(
        'https://play.xbox.com/configuration?device=web', { method: 'GET' }
    );
    const parsed = JSON.parse(await response.text());
    const overrides = parsed.clientStreamingConfigOverrides;
    const video = overrides.videoConfiguration;
    const input = overrides.inputConfiguration;
    const audio = overrides.audioConfiguration;

    // This is the regression guard: a request-only implementation passes the
    // old tests but cannot change this parsed response.
    check('configuration is changed in the /configuration answer',
          video.enableHevc === true && input.enableTouchInput === true
          && audio.useHardwareAudioDecoding === true, JSON.stringify(overrides));
    check('HEVC and automatic decoding are asked for',
          video.enableHevc === true && video.decoderType === 4, JSON.stringify(video));
    check('software rendering is off', video.useSoftwareRendering === false);
    check('touch and ten touch points are asked for',
          input.enableTouchInput === true && input.maxTouchPoints === 10, JSON.stringify(input));
    check('hardware audio decoding is always asked for',
          audio.useHardwareAudioDecoding === true, JSON.stringify(audio));
    check('known and unrelated fields are preserved',
          video.existingVideoField === 'preserved' && input.enableGamepadInput === true
          && parsed.unrelated.preserved === true);

    const changed = report('configuration changed');
    check('the changed answer is reported', !!changed, changed ? changed.detail : 'nothing reported');
    check('the report names the /configuration answer',
          changed && changed.detail.indexOf('/configuration answer') !== -1
          && changed.detail.indexOf('https://play.xbox.com/configuration?device=web') !== -1,
          changed ? changed.detail : '');

    // No configuration is fabricated when the answer omits the override or
    // one of its children. Only the audio object supplied here may change.
    configurationAnswer = JSON.stringify({
        clientStreamingConfigOverrides: {
            audioConfiguration: { useHardwareAudioDecoding: false }
        }
    });
    const partialResponse = await sandbox.window.fetch('https://play.xbox.com/configuration');
    const partial = JSON.parse(await partialResponse.text());
    check('missing video and input configurations are not invented',
          partial.clientStreamingConfigOverrides.videoConfiguration === undefined
          && partial.clientStreamingConfigOverrides.inputConfiguration === undefined,
          JSON.stringify(partial));
    check('an existing audio-only configuration is still changed',
          partial.clientStreamingConfigOverrides.audioConfiguration.useHardwareAudioDecoding === true);

    const noOverridesBody = JSON.stringify({ videoConfiguration: { enableHevc: false } });
    configurationAnswer = noOverridesBody;
    const absentResponse = await sandbox.window.fetch('https://play.xbox.com/configuration');
    check('an absent clientStreamingConfigOverrides is not invented',
          await absentResponse.text() === noOverridesBody);
    check('an unchanged answer is visible in the log',
          !!report('configuration unchanged'));

    // The old request-body path must stay removed even when a session request
    // happens to contain fields with the same names.
    const sessionBody = JSON.stringify({
        offeringId: 'xcloud',
        data: {
            videoConfiguration: { enableHevc: false, useSoftwareRendering: true, decoderType: 1 },
            inputConfiguration: { enableTouchInput: false, maxTouchPoints: 2 },
            audioConfiguration: { useHardwareAudioDecoding: false }
        }
    });
    await sandbox.window.fetch('https://xhome.gssv-play-prod.xboxlive.com/v2/sessions/abc', {
        method: 'POST', body: sessionBody
    });
    const sessionRequest = requests.find(r => r.url.indexOf('/v2/sessions/abc') !== -1);
    check('session request bodies pass through byte-for-byte',
          sessionRequest && sessionRequest.init.body === sessionBody,
          sessionRequest && sessionRequest.init.body);

    sandbox.window.__gsPreferHEVC = false;
    sandbox.window.__gsWantTouch = false;
    configurationAnswer = JSON.stringify({ clientStreamingConfigOverrides: {
        videoConfiguration: { enableHevc: false, useSoftwareRendering: true, decoderType: 1 },
        inputConfiguration: { enableTouchInput: false, maxTouchPoints: 2 },
        audioConfiguration: { useHardwareAudioDecoding: false }
    } });
    const disabledResponse = await sandbox.window.fetch('https://play.xbox.com/configuration');
    const disabled = JSON.parse(await disabledResponse.text()).clientStreamingConfigOverrides;
    check('touch and HEVC are not forced when not wanted',
          disabled.videoConfiguration.enableHevc === false
          && disabled.videoConfiguration.decoderType === 1
          && disabled.inputConfiguration.enableTouchInput === false
          && disabled.inputConfiguration.maxTouchPoints === 2);
    check('audio hardware decoding does not depend on touch or HEVC',
          disabled.audioConfiguration.useHardwareAudioDecoding === true);
})();
