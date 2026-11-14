#!/usr/bin/env python3
"""
A static checker for the Kotlin sources in this repo.

There is no JDK and no Gradle on this phone, so the Android app can only be
compiled by CI. Every wasted CI cycle is a wasted cycle, and the failures
seen so far were all the cheap-to-catch kind: a symbol used but never
imported, an import that does not exist in the project, braces that do not
balance, a Modifier property that does not exist.

This checks the four things that actually broke builds:

  1. Braces / parens / brackets balance (ignoring strings and comments).
  2. Every `import com.gamestream.app...` resolves to a declaration that
     exists somewhere in the project.
  3. Every `import androidx...` / `import coil...` is actually USED in the
     file (unused imports are not errors, but they hide intent).
  4. A small table of known-bad patterns, e.g. `Modifier.contentDescription =`
     which is not a thing -- the real API is
     `Modifier.semantics { contentDescription = ... }`.

It is not a compiler. It cannot type-check. It catches the typos.
"""
import os
import re
import sys
from collections import defaultdict

# The Android sources, relative to this script, so the same file works from
# the working copy on the phone and from CI.
_HERE = os.path.dirname(os.path.abspath(__file__))
_REPO = os.path.dirname(_HERE)
ROOT = os.path.join(_REPO, "android", "app", "src", "main", "java")
PRISMAL = os.path.join(ROOT, "com/styropyr0/prismal")

# ---------------------------------------------------------------- collect

kt_files = []
for base, _dirs, files in os.walk(ROOT):
    if "/build/" in base:
        continue
    for f in files:
        if f.endswith(".kt"):
            kt_files.append(os.path.join(base, f))

# Declarations the project defines: package -> set of top level names.
declared = defaultdict(set)
file_decls = {}          # path -> (package, set of names declared in it)
file_text = {}

DECL = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?:public\s+|internal\s+|private\s+|open\s+|abstract\s+|sealed\s+|data\s+|value\s+|inline\s+|suspend\s+|operator\s+|infix\s+|expect\s+|actual\s+)*"
    r"(?:class|interface|object|enum class|fun|val|var|typealias)\s+"
    r"(?:<[^>]*>\s*)?"
    r"([A-Za-z_][A-Za-z0-9_]*)",
    re.M,
)

for path in kt_files:
    text = open(path, encoding="utf-8", errors="replace").read()
    file_text[path] = text
    m = re.search(r"^\s*package\s+([\w.]+)", text, re.M)
    pkg = m.group(1) if m else ""
    names = set()
    for dm in DECL.finditer(text):
        names.add(dm.group(1))
    # constructor-style: class Foo(  -- already caught by DECL
    file_decls[path] = (pkg, names)
    declared[pkg].update(names)
    # also record the package's own file name as a class-ish (e.g. GameCatalog.kt -> GameCatalog)
    base_name = os.path.splitext(os.path.basename(path))[0]
    declared[pkg].add(base_name)

# ---------------------------------------------------------------- helpers

def strip_code(text):
    """Blank out comments and string literals, keeping line structure."""
    out = []
    i = 0
    n = len(text)
    state = None  # None, 'line', 'block', 'str', 'triple', 'char'
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if state is None:
            if c == "/" and nxt == "/":
                state = "line"; out.append("  "); i += 2; continue
            if c == "/" and nxt == "*":
                state = "block"; out.append("  "); i += 2; continue
            if text.startswith('"""', i):
                state = "triple"; out.append('   '); i += 3; continue
            if c == '"':
                state = "str"; out.append(" "); i += 1; continue
            if c == "'":
                state = "char"; out.append(" "); i += 1; continue
            out.append(c); i += 1; continue
        if state == "line":
            if c == "\n":
                state = None; out.append("\n")
            else:
                out.append(" ")
            i += 1; continue
        if state == "block":
            if c == "*" and nxt == "/":
                state = None; out.append("  "); i += 2; continue
            out.append(c if c == "\n" else " "); i += 1; continue
        if state == "triple":
            if text.startswith('"""', i):
                state = None; out.append('   '); i += 3; continue
            out.append(c if c == "\n" else " "); i += 1; continue
        if state in ("str", "char"):
            quote = '"' if state == "str" else "'"
            if c == "\\":
                out.append("  "); i += 2; continue
            if c == quote:
                state = None; out.append(" "); i += 1; continue
            out.append(c if c == "\n" else " "); i += 1; continue
    return "".join(out)


KNOWN_BAD = [
    (re.compile(r"\.contentDescription\s*="), "Modifier has no contentDescription property. Use: .semantics { contentDescription = ... }"),
    (re.compile(r"\.semantics\s*\{\s*this\.contentDescription"), "semantics { contentDescription = ... } -- drop the `this.`"),
    (re.compile(r"\blibrary\.\w"), "`library.` inside an extension LibraryStore -- `self` IS the store; use the members directly"),
    (re.compile(r"remember\s*\{[^{}]*\bLocal\w+\.current\b"), "remember's calculation lambda is @DisallowComposableCalls -- read LocalX.current into a val first, then remember(context) { ... }"),
    (re.compile(r"\bLazyVerticalGrid\b[\s\S]{0,400}?verticalScroll"), "a LazyVerticalGrid inside a verticalScroll crashes at runtime (infinite height)"),
]

# Kotlin built-ins and stdlib names that are always in scope.
KOTLIN_BUILTIN = {
    "String", "Int", "Long", "Float", "Double", "Boolean", "Char", "Byte", "Short",
    "Unit", "Any", "Nothing", "List", "MutableList", "Set", "MutableSet", "Map",
    "MutableMap", "Array", "Pair", "Triple", "Exception", "RuntimeException",
    "IllegalArgumentException", "IllegalStateException", "Error", "Comparable",
    "Number", "CharSequence", "Regex", "Result", "Sequence", "Iterable",
    "Collection", "ArrayList", "HashMap", "HashSet", "LinkedHashMap", "LinkedHashSet",
    "Lazy", "Deprecated", "Suppress", "JvmStatic", "JvmField", "JvmOverloads",
    "Throws", "Volatile", "Synchronized", "OptIn", "RequiresOptIn", "Function",
    "KFunction", "Comparator", "Enum", "Throwable",
}

# Operator imports used by property delegation (`by remember { ... }`).
DELEGATE_OPERATORS = {"getValue", "setValue", "provideDelegate", "invoke"}


# ---------------------------------------------------------------- check

problems = []
for path in sorted(kt_files):
    raw = file_text[path]
    code = strip_code(raw)
    pkg, names = file_decls[path]
    rel = os.path.relpath(path, ROOT)

    # 1. brace balance
    pairs = {"}": "{", ")": "(", "]": "["}
    stack = []
    for ch in code:
        if ch in "{([":
            stack.append(ch)
        elif ch in "}] )".replace(" ", ""):
            if not stack:
                problems.append((rel, "balance", f"stray '{ch}'"))
                break
            if stack[-1] != pairs[ch]:
                problems.append((rel, "balance", f"'{ch}' closes '{stack[-1]}'"))
                break
            stack.pop()
    else:
        if stack:
            problems.append((rel, "balance", f"{len(stack)} unclosed: {''.join(stack[-5:])}"))

    # 2. project imports resolve
    for im in re.finditer(r"^import\s+(com\.gamestream\.app[\w.]*)", raw, re.M):
        fq = im.group(1)
        if fq in ("com.gamestream.app",):
            continue
        # package part
        parts = fq.split(".")
        # find the longest prefix that is a known package
        resolved = False
        for cut in range(len(parts) - 1, 0, -1):
            pkg_guess = ".".join(parts[:cut])
            if pkg_guess in declared:
                last = parts[-1]
                if last in declared[pkg_guess] or parts[cut] in declared[pkg_guess]:
                    resolved = True
                else:
                    # could be a nested class / object member
                    if any(last in s for s in declared.values()):
                        resolved = True
                break
        if not resolved:
            problems.append((rel, "import", f"import {fq} does not resolve to any declaration in the project"))

    # 3. known-bad patterns
    for rx, why in KNOWN_BAD:
        for m in rx.finditer(code):
            line = code[: m.start()].count("\n") + 1
            problems.append((rel, "pattern", f"line {line}: {why}"))

    # 4. androidx imports that are never referenced
    body = re.sub(r"^import .*$", "", raw, flags=re.M)
    for im in re.finditer(r"^import\s+(androidx\.[\w.]+|coil\.[\w.]+)(?:\s+as\s+(\w+))?\s*$", raw, re.M):
        fq = im.group(1)
        alias = im.group(2)
        simple = alias or fq.split(".")[-1]
        if simple == "*":
            continue
        if simple in DELEGATE_OPERATORS:
            continue
        if not re.search(r"\b" + re.escape(simple) + r"\b", body):
            problems.append((rel, "unused", f"import {fq} is never used"))

    # 5. capitalised symbols used in the file that are neither imported,
    #    declared in the file, declared in the same package, nor built in.
    #    This is the "AppearancePrefs used but never imported" class of bug,
    #    which is a compile error and cost a CI cycle before.
    imported = set()
    for im in re.finditer(r"^import\s+([\w.]+)(?:\s+as\s+(\w+))?\s*$", raw, re.M):
        imported.add(im.group(2) or im.group(1).split(".")[-1])
    imported.add("*")
    package_level = declared.get(pkg, set())
    # Enum entries and nested members are declared inside a body, so the
    # declaration regex above misses them. Anything that appears at the
    # start of a line followed by a bracket or comma is declared here.
    local_nested = set(re.findall(r"^\s*([A-Z][A-Za-z0-9_]*)\s*[,({]", code, re.M))
    for m in re.finditer(r"(?<![\w.])([A-Z][A-Za-z0-9_]*)\s*[\(\.\<\:\,\)]", code):
        name = m.group(1)
        if name in KOTLIN_BUILTIN:
            continue
        if name in imported or name in names or name in package_level:
            continue
        if name in local_nested:
            continue
        # A type in the same package but a different file is covered by
        # package_level. Anything else is a candidate missing import.
        if any(name in s for s in declared.values()):
            # exists somewhere in the project, but not imported here
            line = code[: m.start()].count("\n") + 1
            problems.append((rel, "missing-import", f"line {line}: '{name}' is used but never imported"))


# ---------------------------------------------------------------- report

if not problems:
    print("PASS - no static problems found in %d Kotlin files" % len(kt_files))
    sys.exit(0)

by_kind = defaultdict(list)
for rel, kind, msg in problems:
    by_kind[kind].append((rel, msg))

print("PROBLEMS in %d of %d Kotlin files\n" % (len({p[0] for p in problems}), len(kt_files)))
for kind in ("balance", "import", "missing-import", "pattern", "unused"):
    items = by_kind.get(kind, [])
    if not items:
        continue
    print("== %s (%d) ==" % (kind.upper(), len(items)))
    for rel, msg in sorted(items):
        print("  %s: %s" % (rel, msg))
    print()

sys.exit(1 if any(k in ("balance", "import", "missing-import", "pattern") for k in by_kind) else 0)
