// A test harness for the cloud-servers script: a fake page, a fake
// sign-in answer with three servers in it, and a check that the script
// reports the servers, narrows the answer to the chosen one, sends the
// client the app says it is, and reports the queue.

const fs = require('fs');
const vm = require('vm');

const posted = [];
let lastHeaders = null;
let lastBody = null;

const regions = [
    { name: "WestUs", displayName: "United States", baseUri: "https://wus.core.gssv-play-prod.xboxlive.com", isDefault: true },
    { name: "JapanEast", displayName: "Japan", baseUri: "https://jpe.core.gssv-play-prod.xboxlive.com" },
    { name: "NewZealand", displayName: "New Zealand", baseUri: "https://nznz.core.gssv-play-prod.xboxlive.com" }
];

const signInBody = JSON.stringify({
    gsToken: "token",
    offeringSettings: { regions: regions }
});

class FakeHeaders {
    constructor(map) { this.map = map || {}; }
    entries() { return Object.entries(this.map); }
}

class FakeResponse {
    constructor(body) {
        this.body = true;
        this.ok = true;
        this.status = 200;
        this.statusText = "OK";
        this.headers = new FakeHeaders({ "content-type": "application/json" });
        this._body = body;
    }
    clone() { return new FakeResponse(this._body); }
    text() { return Promise.resolve(this._body); }
}

const sandbox = {
    window: {
        location: { host: "play.xbox.com" },
        navigator: {},
        webkit: { messageHandlers: { gamestream: { postMessage: (p) => posted.push(p) } } },
    },
    Headers: FakeHeaders,
    Response: FakeResponse,
    Request: class {
        constructor(input, init) {
            this.url = (input && input.url) || "";
            this.method = (init && init.method) || (input && input.method) || "GET";
            this._body = init && init.body !== undefined ? init.body : (input && input._body);
            this.headers = (init && init.headers) || {};
        }
        clone() {
            const copy = new sandbox.Request(this.url, { method: this.method, body: this._body, headers: this.headers });
            copy.clone = () => new sandbox.Request(this.url, { method: this.method, body: this._body, headers: this.headers });
            return copy;
        }
        text() { return Promise.resolve(this._body); }
    },
    XMLHttpRequest: class {
        constructor() { this.responseType = ""; this.responseText = ""; this._listeners = {}; }
        open(m, u) { this.method = m; this.url = u; }
        setRequestHeader(n, v) { (this.headers = this.headers || {})[n] = v; }
        send(b) { this.body = b; lastBody = b; return undefined; }
        addEventListener(name, fn) { (this._listeners[name] = this._listeners[name] || []).push(fn); }
        fire(name) { (this._listeners[name] || []).forEach(fn => fn({})); }
    },
    webkit: { messageHandlers: { gamestream: { postMessage: (p) => posted.push(p) } } },
    Promise, Object, JSON, Array, String, Number, parseInt, Error, Date,
};
sandbox.fetch = function (input, init) {
    lastHeaders = (init && init.headers) || (input && input.headers) || null;
    lastBody = (init && init.body !== undefined) ? init.body : (input && input._body);
    const url = (typeof input === "string") ? input : (input && input.url) || "";
    if (url.indexOf("/login/user") !== -1) return Promise.resolve(new FakeResponse(signInBody));
    if (url.indexOf("/sessions") !== -1) {
        return Promise.resolve(new FakeResponse(JSON.stringify({
            provisioningEstimatedWaitTimeInSeconds: 42, region: "WestUs"
        })));
    }
    return Promise.resolve(new FakeResponse("{}"));
};
sandbox.window.fetch = sandbox.fetch;

vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(process.argv[2], "utf8"), sandbox);

function check(name, ok, detail) {
    console.log((ok ? "ok   " : "FAIL ") + name + (detail ? "  -> " + detail : ""));
    if (!ok) process.exitCode = 1;
}

(async function () {
    // 1. The servers are reported.
    await sandbox.window.fetch("https://xhome.gssv-play-prod.xboxlive.com/v2/login/user", { method: "POST", body: "{}" });
    const servers = posted.find(p => p.type === "cloudServers");
    check("the servers are reported", !!servers, servers ? servers.regions.length + " servers" : "nothing reported");
    check("all three servers arrive", servers && servers.regions.length === 3);

    // 2. The client the app says it is goes on the request.
    const info = JSON.parse(lastHeaders["x-ms-device-info"]);
    check("the client claim is sent", !!info, info.dev.os.name + "/" + info.dev.browser.browserName);
    check("it says windows by default", info.dev.os.name === "windows");

    // 3. With no choice, the answer is not changed.
    let answer = await sandbox.window.fetch("https://xhome.gssv-play-prod.xboxlive.com/v2/login/user", { method: "POST", body: "{}" });
    let text = await answer.text();
    check("without a choice the answer is untouched", JSON.parse(text).offeringSettings.regions.length === 3);

    // 4. With a choice, the answer is narrowed to it.
    sandbox.window.__gsSetCloudChoice("NewZealand", "tizen|chrome|140|3840|2160|tizen|26.1.97");
    answer = await sandbox.window.fetch("https://xhome.gssv-play-prod.xboxlive.com/v2/login/user", { method: "POST", body: "{}" });
    text = await answer.text();
    const narrowed = JSON.parse(text).offeringSettings.regions;
    check("with a choice the answer is narrowed", narrowed.length === 1, narrowed.length + " region");
    check("it is the one that was chosen", narrowed[0] && narrowed[0].name === "NewZealand");
    check("it is marked as the default", narrowed[0] && narrowed[0].isDefault === true);
    const claim = JSON.parse(lastHeaders["x-ms-device-info"]);
    check("the chosen client is sent", claim.dev.os.name === "tizen" && claim.appInfo.env.clientAppType === "tizen");

    // 5. The queue is reported from the session answer.
    await sandbox.window.fetch("https://xhome.gssv-play-prod.xboxlive.com/v2/sessions/abc", { method: "GET" });
    const wait = posted.find(p => p.type === "cloudWait");
    check("the queue is reported", !!wait, wait ? wait.seconds + "s" : "nothing reported");

    // 6. A request body is not lost.
    const req = new sandbox.Request("https://xhome.gssv-play-prod.xboxlive.com/v2/login/user", { method: "POST", body: "{\"offeringId\":\"xhome\"}" });
    await sandbox.window.fetch(req);
    check("the request body survives", lastBody !== null && String(lastBody).indexOf("offeringId") !== -1, String(lastBody).slice(0, 40));
})();
