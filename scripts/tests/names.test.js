// Checks that the names the app and the page scripts agree on.
//
// The app sets some values on the page - the resolution it wants, the
// bitrate ceiling, whether touch is wanted - and the page script reads
// them. If one of them is renamed on one side and not the other, the
// setting is quietly ignored and nothing says so. These names are
// written down here, and the check fails if either side stops using one.

const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const root = path.dirname(__dirname) + '/..';
const outdir = fs.mkdtempSync(path.join(os.tmpdir(), 'gs-names-'));

function run(command, args) {
    return execFileSync(command, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

run('python3', [path.join(root, 'scripts', 'extract_scripts.py'), outdir]);

const webview = fs.readFileSync(path.join(root, 'GameStream', 'Core', 'XboxWebView.swift'), 'utf8');
const session = fs.readFileSync(path.join(outdir, 'touchInputJS.js'), 'utf8');
const servers = fs.readFileSync(path.join(outdir, 'cloudServersJS.js'), 'utf8');

// The name the app sets, and the name the page reads.
const pairs = [
    ['__gsWantTouch', webview, session],
    ['__gsPreferHEVC', webview, session],
    ['__gsSetCloudChoice', webview, servers]
];

let failed = 0;
for (const [name, setter, reader] of pairs) {
    const sets = setter.includes(name);
    const reads = reader.includes(name);
    if (sets && reads) {
        console.log('ok   ' + name + ' is set by the app and read by the page');
    } else {
        failed++;
        console.log('FAIL ' + name + (sets ? ' is set but never read' : ' is read but never set'));
    }
}

fs.rmSync(outdir, { recursive: true, force: true });
console.log('\n' + (failed ? failed + ' failed' : 'every name agrees'));
process.exit(failed ? 1 : 0);
