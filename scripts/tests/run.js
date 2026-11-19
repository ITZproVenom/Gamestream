// Runs the checks on the scripts the app runs in the web page.
//
// The scripts are taken out of the Swift source, so what is checked is
// what the app actually runs. Each script is checked for being valid
// JavaScript, and the three that decide what the page is told are run
// against a fake answer: the session request, the sign-in answer and a
// pad.
//
//   node scripts/tests/run.js

const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const root = path.dirname(__dirname) + '/..';
const outdir = fs.mkdtempSync(path.join(os.tmpdir(), 'gs-scripts-'));

function run(command, args) {
    return execFileSync(command, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

let failed = 0;

// 1. Take the scripts out of the Swift source.
run('python3', [path.join(root, 'scripts', 'extract_scripts.py'), outdir]);
console.log('scripts extracted\n');

// 2. Every script must be valid JavaScript.
const scripts = fs.readdirSync(outdir).filter((f) => f.endsWith('.js'));
for (const file of scripts) {
    try {
        run('node', ['--check', path.join(outdir, file)]);
        console.log('ok   ' + file + ' parses');
    } catch (e) {
        failed++;
        console.log('FAIL ' + file + ' does not parse');
        console.log(String(e.stderr || '').split('\n').slice(0, 4).join('\n'));
    }
}
console.log('');

// 3. The three that decide what the page is told.
const suites = [
    ['session.test.js', 'touchInputJS.js'],
    ['cloud_servers.test.js', 'cloudServersJS.js'],
    ['gamepad.test.js', 'gamepadBridgeJS.js']
];
for (const [test, script] of suites) {
    const testPath = path.join(root, 'scripts', 'tests', test);
    const scriptPath = path.join(outdir, script);
    if (!fs.existsSync(testPath) || !fs.existsSync(scriptPath)) {
        failed++;
        console.log('FAIL ' + test + ' could not be run');
        continue;
    }
    try {
        const output = run('node', [testPath, scriptPath]);
        const lines = output.trim().split('\n');
        const bad = lines.filter((l) => l.startsWith('FAIL'));
        if (bad.length) {
            failed++;
            console.log('FAIL ' + test);
            bad.forEach((l) => console.log('     ' + l));
        } else {
            console.log('ok   ' + test + ' (' + lines.length + ' checks)');
        }
    } catch (e) {
        failed++;
        console.log('FAIL ' + test);
        console.log(String(e.stdout || '') + String(e.stderr || ''));
    }
}

// 4. The names the app and the page scripts agree on.
try {
    const output = run('node', [path.join(root, 'scripts', 'tests', 'names.test.js')]);
    const lines = output.trim().split('\n');
    const bad = lines.filter((l) => l.startsWith('FAIL'));
    if (bad.length) {
        failed++;
        console.log('FAIL names.test.js');
        bad.forEach((l) => console.log('     ' + l));
    } else {
        console.log('ok   names.test.js (' + lines.length + ' checks)');
    }
} catch (e) {
    failed++;
    console.log('FAIL names.test.js');
    console.log(String(e.stdout || '') + String(e.stderr || ''));
}

fs.rmSync(outdir, { recursive: true, force: true });
console.log('\n' + (failed ? failed + ' failed' : 'everything passed'));
process.exit(failed ? 1 : 0);
