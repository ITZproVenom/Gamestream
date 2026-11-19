// A test harness for the gamepad bridge's page script: a fake page, a
// fake pad, and a check that the page sees a pad with the right shape,
// the right buttons and the right axes - and that up is up.

const fs = require('fs');
const vm = require('vm');

const sandbox = {
    window: {
        navigator: {},
        performance: { now: () => 1 },
        addEventListener: () => {},
    },
    performance: { now: () => 1 },
    Promise, Object, JSON, Array, String, Number, Boolean, Error,
};
sandbox.navigator = sandbox.window.navigator;
sandbox.window.webkit = {
    messageHandlers: { gamestream: { postMessage: (p) => {} } }
};

vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(process.argv[2], "utf8"), sandbox);

function check(name, ok, detail) {
    console.log((ok ? "ok   " : "FAIL ") + name + (detail ? "  -> " + detail : ""));
    if (!ok) process.exitCode = 1;
}

const bridge = sandbox.window.__gsGamepad;
check("the bridge exists", typeof bridge === "function");

// The app sends: connected, axes, buttons, values.
const pushed = {
    connected: true,
    axes: [-0.5, 0.25, 0, 0],
    buttons: [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0],
    values: [1, 0, 0, 0, 0, 0, 0.65, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
};

bridge(pushed);
const pads = sandbox.window.navigator.getGamepads();
check("the page sees a pad", pads && pads.length >= 2 && !!pads[1], pads ? pads.length + " slots" : "none");
const pad = pads && pads[1];
if (pad) {
    check("it is a standard mapping", pad.mapping === "standard");
    check("it has four axes", pad.axes.length === 4);
    check("it has seventeen buttons", pad.buttons.length === 17);
    check("the trigger keeps its value", Math.abs(pad.buttons[6].value - 0.65) < 0.001, String(pad.buttons[6].value));
    check("a pressed button is pressed", pad.buttons[0].pressed === true);
    check("an unpressed button is not", pad.buttons[1].pressed === false);
    check("it can vibrate", !!pad.vibrationActuator && typeof pad.vibrationActuator.playEffect === "function");
    check("the vertical axis is the browser's way round", Math.abs(pad.axes[1] - 0.25) < 0.001, String(pad.axes[1]));
}

// With nothing connected there is no pad.
bridge({ connected: false, axes: [0, 0, 0, 0], buttons: new Array(17).fill(0), values: new Array(17).fill(0) });
const empty = sandbox.window.navigator.getGamepads();
check("with no controller there is no pad", !empty[1]);
