"""Optional C/Odin differential check; normal tests need only Odin.

Recover the original binding and C object from immutable repository history.
The object is only linked into a temporary oracle executable, never the library.
"""

import argparse
import difflib
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
BASELINE = "a57cea853a46bf1b0a5662b80c0bb976154c635e"
OBJECT_SHA256 = "7dc7101dfbea6f30742b77b6fdaa77a8391dbd9665a117f10d7133e0c390f557"
TESTS = Path(__file__).resolve().parent


def historical(path):
    return subprocess.check_output(["git", "show", f"{BASELINE}:{path}"], cwd=ROOT)


def run_suite(work, kind, summarize=False):
    runner = work / f"{kind}_runner"
    runner.mkdir(exist_ok=True)
    body = "fmt.print(output)"
    if summarize:
        body = "summary := suite.Summarize(output); defer delete(summary); fmt.print(summary)"
    (runner / "main.odin").write_text(
        f'package main\nimport "core:fmt"\nimport suite "../{kind}_suite"\n'
        f'main :: proc() {{ output := suite.Run(); defer delete(output); {body} }}\n',
        encoding="utf-8",
    )
    return subprocess.check_output(
        ["odin", "run", str(runner), f"-collection:olib={ROOT}",
         f"-out:{work / (kind + '.exe')}"], cwd=ROOT,
    ).decode("utf-8").replace("\r\n", "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update-snapshot", action="store_true",
                        help="write a snapshot from C, only after C/Odin equality")
    args = parser.parse_args()
    if os.name != "nt":
        parser.error("This historical oracle is Windows x64; normal Odin snapshot tests are portable.")
    obj = historical("thirdparty/clay-odin/windows/clay.obj")
    if hashlib.sha256(obj).hexdigest() != OBJECT_SHA256:
        raise RuntimeError("Unexpected C oracle object hash")
    suite = (TESTS / "suite.odin").read_text(encoding="utf-8")
    with tempfile.TemporaryDirectory(prefix="olib-clay-parity-") as tmp:
        work = Path(tmp)
        reference = work / "reference"
        (reference / "windows").mkdir(parents=True)
        (reference / "windows/clay.obj").write_bytes(obj)
        (reference / "clay.odin").write_bytes(historical("thirdparty/clay-odin/clay.odin"))
        for kind, path in [("reference", "../reference"), ("native", "olib:thirdparty/clay-odin")]:
            target = work / f"{kind}_suite"
            target.mkdir()
            (target / "suite.odin").write_text(suite.replace('clay ".."', f'clay "{path}"'), encoding="utf-8")
        expected = run_suite(work, "reference")
        actual = run_suite(work, "native")
        if actual != expected:
            out = ROOT / "build/clay-parity"
            out.mkdir(parents=True, exist_ok=True)
            (out / "reference.txt").write_text(expected, encoding="utf-8")
            (out / "native.txt").write_text(actual, encoding="utf-8")
            diff = list(difflib.unified_diff(expected.splitlines(), actual.splitlines(),
                                           fromfile="C v0.14", tofile="Odin"))
            print("\n".join(diff[:100]))
            raise SystemExit(f"Mismatch; full output saved to {out}")
        if args.update_snapshot:
            snapshot = run_suite(work, "reference", summarize=True)
            (TESTS / "testdata/c-v0.14.txt").write_text(snapshot, encoding="utf-8", newline="\n")
        print(f"C/Odin match: {len(expected.splitlines())} lines; oracle SHA-256 {OBJECT_SHA256}")


if __name__ == "__main__":
    main()
