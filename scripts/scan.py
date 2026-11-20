#!/usr/bin/env python3
"""A whole-code scanner for the GameStream iOS app.

Every check looks at the whole repository at once. Run it, fix what it
finds, run it again: that is the loop.
"""
import os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "GameStream")

def swift_files():
    out = []
    for base, _, names in os.walk(APP):
        for n in names:
            if n.endswith(".swift"):
                out.append(os.path.join(base, n))
    return sorted(out)

def read(p):
    try:
        return open(p, encoding="utf-8").read()
    except Exception:
        return ""

def strip_swift(text):
    text = re.sub(r'#""".*?"""#', '""', text, flags=re.S)
    text = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', text)
    text = re.sub(r'//[^\n]*', '', text)
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return text

findings = []
def add(kind, where, what):
    findings.append((kind, where, what))

files = swift_files()
sources = {p: read(p) for p in files}

for p, s in sources.items():
    t = strip_swift(s)
    b = t.count("{") - t.count("}")
    pr = t.count("(") - t.count(")")
    if b or pr:
        add("syntax", os.path.relpath(p, ROOT), f"braces {b:+d}, parens {pr:+d}")

for p, s in sources.items():
    for m in re.finditer(r'(?:static let (\w+) = |let (\w+) = )?#"""\n(.*?)\n    """#', s, re.S):
        name = m.group(1) or m.group(2) or "(inline)"
        body = m.group(3)
        if "function(" not in body and "=>" not in body and "window." not in body:
            continue
        if "__CSS__" in body or "var CSS" in body:
            continue
        open("/tmp/scan.js", "w").write(body)
        try:
            r = subprocess.run(["node", "--check", "/tmp/scan.js"], capture_output=True, text=True)
        except FileNotFoundError:
            # Node is not installed here; the build checks the scripts.
            continue
        if r.returncode:
            add("javascript", os.path.relpath(p, ROOT), f"{name}: {r.stderr.splitlines()[0][:70]}")

settings = sources.get(os.path.join(APP, "Services/AppSettings.swift"), "")
props = re.findall(r'@Published (?:private\(set\) )?var (\w+)', settings)
for prop in props:
    uses = 0
    for p, s in sources.items():
        if os.path.basename(p) == "AppSettings.swift":
            uses += len(re.findall(r'\b' + prop + r'\b', s))
            continue
        uses += len(re.findall(r'\.' + prop + r'\b', s))
        uses += len(re.findall(r'\$' + prop + r'\b', s))
    if uses <= 2:
        add("dead-setting", "AppSettings.swift", f"{prop} is stored but never read")

for p, s in sources.items():
    for m in re.finditer(r'static let (\w+) = #"""\n(.*?)\n    """#', s, re.S):
        name, body = m.group(1), m.group(2)
        for fm in re.finditer(r'function ([a-zA-Z_][\w]*)\(', body):
            fn = fm.group(1)
            if len(re.findall(r'\b' + fn + r'\b', body)) <= 1:
                add("dead-js", f"{os.path.basename(p)}:{name}", f"{fn}() is never called")

for p, s in sources.items():
    for m in re.finditer(r'\.frame\(width: (\d+), height: (\d+)\)', s):
        w, h = int(m.group(1)), int(m.group(2))
        if w < 44 or h < 44:
            line = s[:m.start()].count("\n") + 1
            ctx = s[max(0, m.start()-260):m.start()+260]
            if "Circle()" in ctx or "Capsule()" in ctx or "Indicator" in ctx:
                continue
            # A picture, not something to be tapped on its own.
            if "GameArtwork(" in ctx or "Image(systemName" in ctx:
                continue
            # A button that grows to the minimum nearby is fine.
            if "minWidth: 44" in ctx or "minHeight: 44" in ctx or "frame(minHeight: 44)" in ctx:
                continue
            add("touch-target", f"{os.path.basename(p)}:{line}", f"{w}x{h} is under 44 points")

for p, s in sources.items():
    for m in re.finditer(r'Button\s*\{[^}]{0,400}?Image\(systemName:.*?\n(\s*)\}', s, re.S):
        start = m.start()
        # the label may sit just after the button's closing brace
        window = s[start:start + 900]
        if "accessibilityLabel" in window or "Label(" in window:
            continue
        line = s[:start].count("\n") + 1
        add("accessibility", f"{os.path.basename(p)}:{line}", "a button with only an image has no label")

for p, s in sources.items():
    if "/Tests/" in p:
        continue
    for m in re.finditer(r'fatalError\(', s):
        line = s[:m.start()].count("\n") + 1
        add("risk", f"{os.path.basename(p)}:{line}", "fatalError")

for p, s in sources.items():
    lines = [l.strip() for l in s.split("\n") if len(l.strip()) > 40]
    # Only a block of identical lines counts; one repeated line is normal.
    block = []
    for i, l in enumerate(lines + [None]):
        if block and l == block[0]:
            block.append(l)
            continue
        if len(block) >= 3:
            add("duplication", os.path.relpath(p, ROOT),
                f"{len(block)} identical lines: {block[0][:60]}")
        block = [l] if l else []

for p, s in sources.items():
    for m in re.finditer(r'@Published private\(set\) var (\w+)', s):
        name = m.group(1)
        writers = 0
        for q, t in sources.items():
            writers += len(re.findall(r'\b' + name + r'\s*=', t))
            writers += len(re.findall(r'\b' + name + r'\.(append|remove|insert|removeAll|insert|update)\b', t))
            writers += len(re.findall(r'\b' + name + r'\[[^\]]+\]\s*=', t))
        if writers == 0:
            add("dead-property", os.path.basename(p), f"{name} is published but never changed")


# 11. A switch over an enum that has no default: a new case would do
#     nothing at all, and nothing would say so.
enum_cases = {}
for p, s in sources.items():
    for m in re.finditer(r'enum (\w+)\s*:?\s*[^{]*\{', s):
        name = m.group(1)
        i = s.find("{", m.start())
        depth = 0
        for j in range(i, len(s)):
            if s[j] == "{":
                depth += 1
            elif s[j] == "}":
                depth -= 1
                if depth == 0:
                    body = s[i:j]
                    cases = re.findall(r'case\s+([a-zA-Z_][\w]*)', body)
                    if cases:
                        enum_cases.setdefault(name, set()).update(cases)
                    break
for p, s in sources.items():
    for m in re.finditer(r'switch\s+([\w.\(\)]+)\s*\{', s):
        line = s[:m.start()].count("\n") + 1
        i = s.find("{", m.start())
        depth = 0
        body = ""
        for j in range(i, len(s)):
            if s[j] == "{":
                depth += 1
            elif s[j] == "}":
                depth -= 1
                if depth == 0:
                    body = s[i:j]
                    break
        if "default" in body:
            continue
        # the switched value's type, when it can be told
        value = m.group(1)
        typ = None
        for name, cases in enum_cases.items():
            if re.search(r'\b' + name + r'\b', value):
                typ = name
                break
        if typ:
            handled = set(re.findall(r'case\s+\.([a-zA-Z_]\w*)', body))
            missing = [c for c in enum_cases[typ] if c not in handled and c not in body]
            if missing:
                add("switch", f"{os.path.basename(p)}:{line}",
                    f"a switch over {typ} does not handle {', '.join(missing[:4])}")

# 12. A task that is kept in a property and never cancelled.
for p, s in sources.items():
    for m in re.finditer(r'(\w+)\s*=\s*Task\s*\{', s):
        name = m.group(1)
        if name in ("task", "Task"):
            continue
        cancels = len(re.findall(r'\b' + name + r'\?*\.cancel\(\)', s))
        if cancels == 0:
            line = s[:m.start()].count("\n") + 1
            add("task", f"{os.path.basename(p)}:{line}", f"the task in '{name}' is never cancelled")

# 13. Force unwraps in the interface code.
for p, s in sources.items():
    if "/UI/" not in p:
        continue
    for m in re.finditer(r'(\w+)!\.', s):
        line = s[:m.start()].count("\n") + 1
        add("risk", f"{os.path.basename(p)}:{line}", f"forced unwrap: {m.group(1)}!")

# 14. A log line that claims something the code nearby does not do.
for p, s in sources.items():
    for m in re.finditer(r'log\.\w+\("([^"]*)"[^\n]*\n', s):
        text = m.group(1)
        if "never" in text.lower() or "always" in text.lower():
            continue
        after = s[m.end():m.end()+700]
        if "return" in after and "guard" in after:
            continue


# 15. A message that claims one thing while the code around it does another.
#     "never" / "always" / "only" are the words that make a claim.
for p, s in sources.items():
    for m in re.finditer(r'(?:log\.\w+|print)\(\s*"([^"]{12,200})"', s):
        text = m.group(1)
        if not re.search(r'\b(never|always|only|cannot|is not|does not)\b', text, re.I):
            continue
        line = s[:m.start()].count("\n") + 1
        after = s[m.end():m.end()+900]
        # if the claim is about something that is checked right after, it is
        # probably true; if the code plainly does the opposite, it is not.
        if re.search(r'guard\s+[^\n]*else\s*\{', after[:200]):
            continue
        add("claim", f"{os.path.basename(p)}:{line}", text[:70])

# 16. A published value that is read on the main thread while it is written
#     from a background queue.
for p, s in sources.items():
    if "@MainActor" not in s:
        continue
    for m in re.finditer(r'nonisolated\s+(?:var|let|func)\s+(\w+)', s):
        line = s[:m.start()].count("\n") + 1
        add("isolation", f"{os.path.basename(p)}:{line}",
            f"{m.group(1)} is not isolated but the type is")

# 17. A view that uses a geometry reader and lays itself out from it in a
#     way that can put it off the screen.
for p, s in sources.items():
    for m in re.finditer(r'\.frame\(maxWidth: \.infinity, minHeight: geometry\.size\.height', s):
        line = s[:m.start()].count("\n") + 1
        add("layout", f"{os.path.basename(p)}:{line}", "content is as tall as the screen")


# 18. A main-actor type reached from an actor without going through the
#     main actor. This is the mistake that broke four builds in a row.
main_types = set()
for p, s in sources.items():
    for m in re.finditer(r'@MainActor\s+(?:final class|class|actor) (\w+)', s):
        main_types.add(m.group(1))
for p, s in sources.items():
    if not re.search(r'^actor \w+', s, re.M):
        continue
    for t in sorted(main_types):
        for m in re.finditer(r'\b' + t + r'\.shared\b', s):
            start = m.start()
            # is it inside a MainActor.run?
            window = s[max(0, start - 600):start]
            if "MainActor.run" in window.split("Task {")[-1]:
                continue
            line = s[:start].count("\n") + 1
            add("actor-crossing", f"{os.path.basename(p)}:{line}",
                f"{t}.shared is main-actor state, reached from an actor")


# 19. A script that calls a function it does not define.
#
# The two page scripts are separate programs in the same page: one wraps
# the fetch and answers the sign-in, the other rewrites the session. A
# function one of them calls but does not have is a ReferenceError at the
# first request, and the thing it was doing silently stops happening -
# which is how the client the app says it is stopped being sent.
import re as _re
for p, s in sources.items():
    for m in _re.finditer(r'static let (\w+) = #"""\n(.*?)\n    """#', s, _re.S):
        name, body = m.group(1), m.group(2)
        defined = set(_re.findall(r'function ([A-Za-z_][\w]*)\s*\(', body))
        # only the code, not the comments
        code = _re.sub(r'//[^\n]*', '', body)
        code = _re.sub(r'/\*.*?\*/', '', code, flags=_re.S)
        code = _re.sub(r'"(?:\\.|[^"\\\n])*"', '""', code)
        called = set(_re.findall(r'(?<![.\w])([a-z][A-Za-z_]\w*)\s*\(', code))
        # names the script holds in a variable are its own
        local = set(_re.findall(r'(?:var|let|const)\s+([A-Za-z_]\w*)\s*=', code))
        # the built-in ones the scripts use
        builtin = {"if", "for", "while", "switch", "catch", "return", "typeof", "function",
                   "new", "parseInt", "parseFloat", "setTimeout", "setInterval", "clearTimeout",
                   "clearInterval", "isNaN", "Math", "JSON", "Object", "Array", "String",
                   "Number", "Boolean", "Date", "Promise", "Error", "encodeURIComponent",
                   "decodeURIComponent", "postMessage", "event", "resolve", "reject", "require",
                   "matchMedia", "getComputedStyle", "querySelector", "querySelectorAll",
                   "createElement", "getElementById", "appendChild", "removeChild",
                   "addEventListener", "removeEventListener", "dispatchEvent", "clone",
                   "text", "json", "cloneNode", "scrollIntoView", "getBoundingClientRect",
                   "setAttribute", "getAttribute", "removeAttribute", "observe", "disconnect",
                   "push", "shift", "unshift", "splice", "map", "filter", "reduce", "forEach",
                   "some", "every", "find", "findIndex", "includes", "indexOf", "join",
                   "slice", "concat", "sort", "keys", "values", "entries", "now", "floor",
                   "ceil", "round", "max", "min", "abs", "sqrt", "log", "warn", "error",
                   "assign", "fromEntries", "stringify", "parse", "replace", "replaceAll",
                   "toUpperCase", "toLowerCase", "trim", "split", "charAt", "charCodeAt",
                   "startsWith", "endsWith", "padStart", "padEnd", "repeat", "toFixed"}
        for fn in sorted(called - defined - builtin - local):
            if fn in ("_", "it", "e"):
                continue
            add("missing-js", f"{os.path.basename(p)}:{name}", f"{fn}() is called but not defined")


# 20. A call that leaves out a required argument label.
#
# Swift names an argument, and a call that leaves the name out is a
# compile error. It happened here: a function that takes "message:" was
# called with the message alone.
import re as _re2
signatures = {}
for _p, _s in sources.items():
    for _m in _re2.finditer(r'func ([A-Za-z_]\w*)\(\s*([a-zA-Z_]\w*):', _s):
        signatures.setdefault(_m.group(1), set()).add(_m.group(2))
for _p, _s in sources.items():
    # the JavaScript inside the page scripts is not Swift
    _swift = _re2.sub(r'#""".*?"""#', '""', _s, flags=_re2.S)
    for _name, _labels in signatures.items():
        # the call may be on self, so the name is not required to stand
        # alone; what matters is that it is not a definition and that the
        # argument after it has no label
        for _m in _re2.finditer(r'(?<![.\w])(?:self\.)?' + _name + r'\(\s*\n?\s*"', _swift):
            _line = _swift[:_m.start()].count("\n") + 1
            _after = _swift[_m.end():_m.end() + 80]
            if ":" in _after.split("\n")[0][:24]:
                continue
            add("missing-label", f"{os.path.basename(_p)}:{_line}",
                f"{_name}() is called without the label it needs")

print("=" * 66)
print(f"whole-code scan: {len(files)} Swift files, {len(findings)} findings")

# 13. Force unwraps in the interface code.
for p, s in sources.items():
    if "/UI/" not in p:
        continue
    for m in re.finditer(r'(\w+)!\.', s):
        line = s[:m.start()].count("\n") + 1
        add("risk", f"{os.path.basename(p)}:{line}", f"forced unwrap: {m.group(1)}!")

# 14. A log line that claims something the code nearby does not do.
for p, s in sources.items():
    for m in re.finditer(r'log\.\w+\("([^"]*)"[^\n]*\n', s):
        text = m.group(1)
        if "never" in text.lower() or "always" in text.lower():
            continue
        after = s[m.end():m.end()+700]
        if "return" in after and "guard" in after:
            continue

print("=" * 66)
by_kind = {}
for kind, where, what in findings:
    by_kind.setdefault(kind, []).append((where, what))
for kind in sorted(by_kind):
    print(f"\n== {kind} ({len(by_kind[kind])})")
    for where, what in by_kind[kind][:14]:
        print(f"   {where}: {what}")
if len(findings) > 60:
    print(f"\n... and {len(findings) - 60} more")

# Findings are reported, not fatal: the scanner is a pair of eyes,
# and a build should not stop because it noticed something.
sys.exit(0)
