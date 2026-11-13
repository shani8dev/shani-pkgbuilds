"""tools/check-deps.py, on small packages made up here - each case a way it was
wrong while it was being written, against the real repos:

- bare words in an array (`depends=(curl jq)`, shani-tools-network's style)
  were read as nothing, so curl looked undeclared everywhere;
- a `case` pattern (`gsm|bluetooth)`) read as the program `bluetooth`;
- `set --` in a script, and a script joined from 'a' + 'b' or spread over
  lines, hid the programs after it (mutool went unseen);
- a program the map has never seen must fail, not pass quietly.

    python3 -m pytest tests/test_check_deps.py
"""
import importlib.util
import textwrap
from pathlib import Path

import pytest

TOOL = Path(__file__).resolve().parent.parent / "tools" / "check-deps.py"
spec = importlib.util.spec_from_file_location("check_deps", TOOL)
cd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cd)


def package(tmp: Path, code: dict, depends="", optdepends="", extra="") -> tuple:
    repo = tmp / "demo"
    for name, text in code.items():
        f = repo / name
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(textwrap.dedent(text))
    pb = tmp / "pkgbuilds" / "demo" / "PKGBUILD"
    pb.parent.mkdir(parents=True)
    pb.write_text("\n".join([
        "pkgname=demo",
        "depends=(", depends, ")",
        "optdepends=(", optdepends, ")",
        extra,
        "package() {",
        '    cd "$srcdir/$pkgname"',
        '    install -d "$pkgdir/usr/lib/demo"',
        '    cp -r . "$pkgdir/usr/lib/demo/"',
        "}", ""]))
    return repo, pb


@pytest.fixture
def pmap(monkeypatch):
    rows = {"pactl": {"libpulse"}, "curl": {"curl"}, "mutool": {"mupdf-tools"},
            "nmcli": {"networkmanager"}, "bluetooth": {"tlp"}, "xdotool": {"xdotool"}}
    monkeypatch.setattr(cd, "load_map", lambda: rows)
    monkeypatch.setattr(cd, "on_image", lambda: set())


def run(capsys, repo, pb):
    rc = cd.check(repo, pb, report=False)
    return rc, capsys.readouterr().out


def test_an_undeclared_program_fails(tmp_path, pmap, capsys):
    repo, pb = package(tmp_path, {"a.py": 'subprocess.run(["pactl", "info"])\n'})
    rc, out = run(capsys, repo, pb)
    assert rc == 1 and "UNDECLARED pactl: from libpulse" in out


def test_an_optdepend_declares_it(tmp_path, pmap, capsys):
    repo, pb = package(tmp_path, {"a.py": 'subprocess.run(["pactl", "info"])\n'},
                       optdepends="'libpulse: call audio'")
    assert run(capsys, repo, pb) == (0, "")


def test_bare_words_in_an_array_are_packages(tmp_path, pmap, capsys):
    repo, pb = package(tmp_path, {"a.py": 'shutil.which("curl")\n'}, depends="bash curl  # a comment (with a bracket)\n  jq")
    assert run(capsys, repo, pb) == (0, "")


def test_a_case_pattern_is_not_a_program(tmp_path, pmap, capsys):
    qml = """\
        Process { command: ["sh", "-c", 'nmcli -t c | while read l; do
            case "$l" in wifi|gsm|bluetooth) ;; *) continue;; esac
        done'] }
        """
    repo, pb = package(tmp_path, {"A.qml": qml}, depends="'networkmanager'")
    assert run(capsys, repo, pb) == (0, "")


def test_programs_after_set_and_in_joined_strings_are_seen(tmp_path, pmap, capsys):
    qml = """\
        Item { function f() { p.command = ["sh", "-c", 'set --; for f in *; do set -- "$@" "$f"; done
                    ' + 'mutool convert -o out.pdf "$@"', "sh"]; } }
        """
    repo, pb = package(tmp_path, {"A.qml": qml})
    rc, out = run(capsys, repo, pb)
    assert rc == 1 and "UNDECLARED mutool" in out


def test_unlisted_with_a_reason_is_accepted(tmp_path, pmap, capsys):
    repo, pb = package(tmp_path, {"a.py": 'subprocess.run(["xdotool", "key", "a"])\n'},
                       extra="# check-deps: unlisted xdotool - the X11 fallback")
    assert run(capsys, repo, pb) == (0, "")


def test_unlisted_without_a_reason_is_not(tmp_path, pmap, capsys):
    repo, pb = package(tmp_path, {"a.py": 'subprocess.run(["xdotool", "key", "a"])\n'},
                       extra="# check-deps: unlisted xdotool")
    assert run(capsys, repo, pb)[0] == 1


def test_a_program_the_map_does_not_know_fails(tmp_path, pmap, capsys):
    repo, pb = package(tmp_path, {"a.py": 'subprocess.run(["frobnicate", "-x"])\n'})
    rc, out = run(capsys, repo, pb)
    assert rc == 1 and "NOT IN MAP frobnicate" in out


def test_only_what_package_installs_is_read(tmp_path, pmap, capsys):
    repo, pb = package(tmp_path, {"a.py": "x = 1\n", "tests/t.py": 'subprocess.run(["pactl"])\n'})
    pb.write_text(pb.read_text().replace('cp -r . "$pkgdir/usr/lib/demo/"', 'cp a.py "$pkgdir/usr/lib/demo/"'))
    assert run(capsys, repo, pb) == (0, "")
