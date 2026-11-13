#!/usr/bin/env python3
"""check-deps - the programs a Shanios project runs, against what its PKGBUILD declares.

    tools/check-deps.py REPO [--pkgbuild FILE] [--report]
    tools/check-deps.py --refresh REPO...      # rebuild tools/program-packages.tsv (needs pacman -F)

It reads REPO's code for every external program it starts - subprocess and
shutil.which in Python, Process commands in QML/JS, and the command words of
shell scripts and `sh -c` strings - and looks each one up in
tools/program-packages.tsv, a program -> Arch package map built from pacman's
file database. Arrays are read as shell arrays: quoted or bare words, comments
skipped. A program whose package is neither declared (depends or
optdepends, of this package or of a package it depends on in this repo) nor
always present on Shanios (BASE below) is reported. Exit 1 if any are.

A program can be left out on purpose - a fallback for another desktop or
for X11 - with a comment in the PKGBUILD that gives the reason:

    # check-deps: unlisted xdotool xclip - X11 fallbacks of the Wayland tools

--report also lists declared dependencies whose programs nothing runs: a hint
for trimming, not a failure, since a dependency can be a library, a font, a
daemon, or a program started by name from a setting.

The map holds only the programs the projects use, so the check runs anywhere,
without pacman. A program the map does not know is reported too ("not in the
map"): run --refresh in an Arch container to add it.
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
MAP = HERE / "program-packages.tsv"
PKGBUILDS = HERE.parent

# Always on a Shanios install (the base and shani-core closure): never worth declaring.
BASE = {
    "bash", "coreutils", "util-linux", "systemd", "grep", "sed", "gawk", "findutils",
    "procps-ng", "glibc", "file", "gzip", "tar", "shadow", "iproute2", "which", "xz",
    "bzip2", "zstd", "diffutils", "less", "psmisc", "kmod", "pacman", "dbus", "glib2",
    "python", "util-linux-libs", "e2fsprogs", "gettext", "inetutils", "iputils",
    "libcap", "attr", "acl", "sudo", "polkit", "dbus-broker", "hostname", "man-db", "openssl",
    "systemd-sysvcompat",
}

# Shell words that are not programs.
SHELL_WORDS = {
    "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac",
    "in", "function", "return", "local", "export", "readonly", "declare", "typeset", "set",
    "unset", "shift", "exit", "break", "continue", "eval", "exec", "source", "trap", "wait",
    "read", "printf", "echo", "test", "true", "false", "cd", "pwd", "command", "type", "alias",
    "builtin", "let", "getopts", "umask", "ulimit", "times", "kill", "jobs", "fg", "bg",
    "mapfile", "readarray", "shopt", "hash", "time", "nohup", "env", "sh", "bash", "exec",
    "select", "coproc", "disown", "suspend", "history", "fc", "complete", "compgen",
}

SKIP_DIRS = {"__pycache__", ".git"}

PY_CALL = re.compile(r"""(?:\b(?:run|Popen|check_output|check_call|call|spawn\w*|create_subprocess_exec|execvp?e?|execlp?)\s*\(\s*\[?\s*|shutil\.which\s*\(\s*|\bresolve\s*\(\s*|\bwhich\s*\(\s*|GLib\.find_program_in_path\s*\(\s*)["']([A-Za-z0-9_.+-]+)["']""")
PY_ARGV = re.compile(r"""(?:argv|cmd|command|args|argv0)\s*=\s*\[\s*["']([A-Za-z0-9_.+-]+)["']""")
QML_CMD = re.compile(r"""(?:command\s*[:=]\s*|exec(?:Detached)?\s*\(\s*\{?\s*(?:command\s*:\s*)?)\[\s*"([A-Za-z0-9_.+-]+)\"""")
_STR = r"""(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`[^`]*`)"""
# the script of ["sh", "-c", SCRIPT ...]: one string literal, or several joined with +
SH_C = re.compile(r"""["'](?:sh|bash)["']\s*,\s*["']-[a-z]*c["']\s*,\s*(""" + _STR + r"""(?:\s*\+\s*""" + _STR + r""")*)""")
_LIT = re.compile(_STR)
# a command word in shell text: at the start, or after | ; & && || $( ` ( then do else { and before an argument or end
# (not "x = ...", an assignment in a script embedded in the string)
SH_WORD = re.compile(r"""(?:^|[|;&(`{\n]|\$\(|\b(?:then|do|else|exec|command\s+-v|nice|ionice|timeout\s+\S+|xargs(?:\s+-\S+)*)\s)\s*(?:[A-Z_]+=\S*\s+)*([a-z][a-z0-9_.+-]{1,})(?=[\s;|&)]|$)(?!\s*=)""", re.M)


def literal_text(joined: str) -> str:
    """The text of 'a' + "b" ...: each literal's quotes taken off and its escapes read."""
    return "".join(m.group()[1:-1].replace("\\n", "\n").replace("\\'", "'").replace('\\"', '"')
                   for m in _LIT.finditer(joined))


def shell_words(text: str) -> set:
    text = re.sub(r"(?m)^\s*#.*$", "", text)
    # case patterns ("in a|b)" / ";; c|d)") are words, not commands
    text = re.sub(r"(?:\bin\b|;;)\s*\(?[^\s()|;&]+(?:\s*\|\s*[^\s()|;&]+)*\)", " ", text)
    return {w for w in SH_WORD.findall(text) if w not in SHELL_WORDS}


def scan(repo: Path) -> dict:
    """{program: set of files} that the repo's shipped code starts."""
    found: dict = {}

    def add(name, f):
        name = name.rsplit("/", 1)[-1]
        if name and name not in SHELL_WORDS:
            found.setdefault(name, set()).add(str(f.relative_to(repo)))

    for f in repo.rglob("*"):
        if not f.is_file() or any(p in SKIP_DIRS or p.startswith(".") for p in f.relative_to(repo).parts[:-1]):
            continue
        if f.name.startswith(("test_", "fake-", "fake_", "mock")) or f.suffix in {".md", ".txt", ".json", ".svg", ".png"}:
            continue
        try:
            text = f.read_text(errors="replace")
        except OSError:
            continue
        head = text[:120]
        if f.suffix == ".py" or "python" in head.split("\n", 1)[0]:
            for m in PY_CALL.findall(text) + PY_ARGV.findall(text):
                add(m, f)
            for body in map(literal_text, SH_C.findall(text)):
                for w in shell_words(body):
                    add(w, f)
        elif f.suffix in {".qml", ".js"}:
            for m in QML_CMD.findall(text):
                add(m, f)
            for body in map(literal_text, SH_C.findall(text)):
                for w in shell_words(body):
                    add(w, f)
        elif f.suffix in {".sh", ".bash"} or re.match(r"#!.*\b(ba)?sh\b", head):
            for w in shell_words(text):
                add(w, f)
    return found


def read_array(text: str, name: str) -> list:
    """A PKGBUILD array's quoted items: comments skipped, a line-leading ) ends it."""
    m = re.search(rf"^{name}=\s*\(", text, re.M)
    if not m:
        return []
    out, i = [], m.end()
    while i < len(text):
        c = text[i]
        if c == "#":
            i = text.find("\n", i) + 1 or len(text)
        elif c in "'\"":
            j = text.index(c, i + 1)
            out.append(text[i + 1:j])
            i = j + 1
        elif c == ")":
            break
        elif c.isspace():
            i += 1
        else:           # a bare word: depends=(curl jq)
            m2 = re.compile(r"[^\s)#'\"]+").match(text, i)
            out.append(m2.group())
            i = m2.end()
    return out


def declared(pkgbuild: Path, seen=None) -> set:
    """Package names this PKGBUILD depends on, optionally or not, following this repo's own packages."""
    seen = set() if seen is None else seen
    text = pkgbuild.read_text()
    names = set()
    for item in read_array(text, "depends") + read_array(text, "optdepends"):
        names.add(re.split(r"[<>=:]", item, maxsplit=1)[0].strip())
    for n in list(names):
        sub = PKGBUILDS / n / "PKGBUILD"
        if n not in seen and sub.exists():
            seen.add(n)
            names |= declared(sub, seen)
    return names


# Packages of the ecosystem that are never on an image (project_image_package_policy).
NOT_ON_IMAGE = {"shani-fleet", "shani-insights"}


def on_image() -> set:
    """Every package some Shanios image installs: the depends of the shani-* packages, followed."""
    out, seen = set(), set()
    for pb in sorted(PKGBUILDS.glob("shani-*/PKGBUILD")):
        if pb.parent.name in NOT_ON_IMAGE:
            continue
        for item in read_array(pb.read_text(), "depends"):
            out.add(re.split(r"[<>=:]", item, maxsplit=1)[0].strip())
        out.add(pb.parent.name)
    return out


IGNORE = shutil.ignore_patterns(".git", "venv", ".venv", "out", "cache", "build", "kernels", "node_modules",
                                "__pycache__", ".pytest_cache", "tests", "dev", "docs", "demos", "android", "*.gguf")


def stage(repo: Path, pkgbuild: Path, tmp: Path) -> Path:
    """The package's own files: the PKGBUILD's package() run over a copy of the checkout."""
    name = pkgbuild.parent.name
    src = tmp / "src" / name
    shutil.copytree(repo, src, symlinks=True, ignore=IGNORE)
    out = tmp / "pkg"
    out.mkdir()
    run = subprocess.run(["bash", "-ec", 'source "$1"; srcdir="$2" pkgdir="$3"; package >/dev/null',
                          "bash", str(pkgbuild), str(src.parent), str(out)], capture_output=True, text=True)
    if run.returncode:
        raise SystemExit(f"package() of {pkgbuild} failed:\n{run.stderr[-2000:]}")
    return out


UNLISTED = re.compile(r"^\s*#\s*check-deps:\s*unlisted\s+([^-\n]+?)\s+-\s+\S", re.M)


def unlisted(pkgbuild: Path) -> set:
    """Programs a PKGBUILD says, with a reason, it deliberately does not declare:
    `# check-deps: unlisted xdotool xclip - X11 fallbacks; the Wayland tools are declared`."""
    return {w for m in UNLISTED.findall(pkgbuild.read_text()) for w in m.split()}


def load_map() -> dict:
    out: dict = {}
    if MAP.exists():
        for line in MAP.read_text().splitlines():
            if line and not line.startswith("#"):
                prog, pkgs = line.split("\t")
                out[prog] = set(pkgs.split(",")) if pkgs else set()
    return out


def refresh(repos: list, index: str | None) -> None:
    progs = set()           # what the packages' own files run, nothing else
    for r in repos:
        repo = Path(r).resolve()
        with tempfile.TemporaryDirectory() as tmp:
            progs |= set(scan(stage(repo, PKGBUILDS / repo.name / "PKGBUILD", Path(tmp))))
    owners: dict = {}
    if index:       # "program package" lines, as the pacman -Fl below makes them
        for line in Path(index).read_text().splitlines():
            prog, _, pkg = line.partition(" ")
            owners.setdefault(prog, set()).add(pkg)
    else:
        out = subprocess.run(["pacman", "-Fl"], capture_output=True, text=True, check=True).stdout
        for line in out.splitlines():
            pkg, _, path = line.partition(" ")
            if path.startswith(("usr/bin/", "usr/sbin/")) and path.count("/") == 2:
                owners.setdefault(path.split("/")[-1], set()).add(pkg)
    rows = ["# program\tArch packages providing it (empty: no package has it - a name the scan",
            "# mistook for a program, or something the project ships itself). tools/check-deps.py --refresh",
            "# rebuilds it from pacman -F; a row it cannot resolve keeps the packages written by hand",
            "# ([shani] repo packages are not in the Arch file database)."]
    kept = load_map()
    for p in sorted(progs):
        pkgs = owners.get(p) or kept.get(p, ())       # a hand-written row stays: [shani] packages are not in pacman -F
        rows.append(f"{p}\t{','.join(sorted(pkgs))}")
    MAP.write_text("\n".join(rows) + "\n")
    print(f"{len(progs)} programs written to {MAP}")


def check(repo: Path, pkgbuild: Path, report: bool, staged: bool = True) -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = stage(repo, pkgbuild, Path(tmp)) if staged else repo
        used = scan(root)
        shipped = {p.name for p in root.rglob("*") if p.is_file()}
    pmap = load_map()
    have = declared(pkgbuild) | BASE | {pkgbuild.parent.name}
    image = on_image()
    missing, unknown, image_only = [], [], []
    skip = unlisted(pkgbuild)
    for prog, files in sorted(used.items()):
        if prog in skip:
            continue
        if prog not in pmap:
            if prog not in shipped:
                unknown.append((prog, files))
            continue
        pkgs = pmap[prog]
        if not pkgs or pkgs & have:
            continue
        (image_only if pkgs & image else missing).append((prog, pkgs, files))
    for prog, pkgs, files in missing:
        print(f"UNDECLARED {prog}: from {' or '.join(sorted(pkgs))}, run by {', '.join(sorted(files)[:3])}")
    if report:
        for prog, pkgs, files in image_only:
            print(f"IMAGE ONLY {prog}: {' or '.join(sorted(pkgs & image))} is on the image, not declared here")
    for prog, files in unknown:
        print(f"NOT IN MAP {prog}: run by {', '.join(sorted(files)[:3])} (tools/check-deps.py --refresh)")
    if report:
        provided = {pkg for prog in used for pkg in pmap.get(prog, ())}
        direct = {re.split(r"[<>=:]", i, maxsplit=1)[0].strip() for i in read_array(pkgbuild.read_text(), "depends")}
        binpkgs = {pkg for pkgs in pmap.values() for pkg in pkgs}
        for d in sorted(direct - provided - BASE):
            if d in binpkgs:
                print(f"UNUSED? {d}: a depends whose programs nothing here runs")
    return 1 if missing or unknown else 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("repos", nargs="+")
    ap.add_argument("--no-stage", action="store_true", help="scan the checkout as it is, not package()'s output")
    ap.add_argument("--pkgbuild")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--refresh", action="store_true")
    ap.add_argument("--index", help="with --refresh: a 'program package' list instead of pacman -Fl")
    a = ap.parse_args(argv)
    if a.refresh:
        refresh(a.repos, a.index)
        return 0
    rc = 0
    for r in a.repos:
        repo = Path(r).resolve()
        pkgbuild = Path(a.pkgbuild) if a.pkgbuild else PKGBUILDS / repo.name / "PKGBUILD"
        rc |= check(repo, pkgbuild, a.report, not a.no_stage)
    return rc


if __name__ == "__main__":
    sys.exit(main())
