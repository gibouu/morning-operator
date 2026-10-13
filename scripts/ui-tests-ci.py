#!/usr/bin/env python3
"""Helpers for .github/workflows/ui-tests.yml.

  pick-simulator   reads `xcrun simctl list devices available -j` on stdin and
                   prints the identifier of one iPhone on the newest iOS runtime.
  select           turns test class names into xcodebuild -only-testing or
                   -skip-testing arguments, refusing a name no test file declares.
  summary          prints a Markdown summary of one .xcresult bundle and exits
                   non-zero when the bundle does not describe a clean run.

`summary` never decides whether the tests passed: xcodebuild's exit status does.
It only adds failures of its own (nothing ran, a failed test in the bundle, a
skip where none is allowed), so it can turn a job red but never green.
"""
import argparse
import json
import pathlib
import re
import subprocess
import sys

TARGET = "MorningOperatorUITests"


def version_tuple(text):
    return tuple(int(part) for part in re.findall(r"\d+", text))


def pick_simulator(listing, max_os=None):
    """Return (udid, name, os) for an iPhone on the newest usable iOS runtime."""
    runtimes = {}
    for runtime, devices in listing.get("devices", {}).items():
        match = re.search(r"SimRuntime\.iOS-([\d-]+)$", runtime)
        if not match:
            continue
        phones = [d for d in devices if d.get("isAvailable") and d.get("name", "").startswith("iPhone")]
        if phones:
            runtimes[version_tuple(match.group(1))] = phones
    if not runtimes:
        raise SystemExit("No available iPhone simulator on any iOS runtime.")
    # A runtime newer than the selected Xcode's SDK belongs to another (possibly
    # beta) Xcode on the image. Prefer the newest one this Xcode was built for.
    usable = [v for v in runtimes if max_os is None or v[:2] <= max_os[:2]] or list(runtimes)
    newest = max(usable)

    def preference(device):
        name = device["name"]
        number = version_tuple(name) or (0,)
        if re.fullmatch(r"iPhone \d+ Pro", name):
            rank = 2  # the size the layout checks were written against
        elif re.fullmatch(r"iPhone \d+", name):
            rank = 1
        else:
            rank = 0
        return (rank, number, name)

    chosen = max(runtimes[newest], key=preference)
    return chosen["udid"], chosen["name"], ".".join(str(part) for part in newest)


def declared_test_classes(directory):
    names = set()
    for path in pathlib.Path(directory).glob("*.swift"):
        names.update(re.findall(r"^\s*(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase\b", path.read_text(), re.M))
    return names


def select(mode, classes, directory):
    known = declared_test_classes(directory)
    unknown = [name for name in classes if name not in known]
    if unknown:
        # A misspelt name would make -only-testing run nothing and still succeed.
        raise SystemExit(f"Not a test class under {directory}: {', '.join(unknown)}")
    if not classes:
        raise SystemExit("No test class named.")
    return [f"-{mode}-testing:{TARGET}/{name}" for name in classes]


def xcresulttool(*arguments):
    output = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", *arguments],
                            check=True, capture_output=True, text=True).stdout
    return json.loads(output)


def walk(node, suite=None):
    """Yield (suite name, test case node) for every test case below node."""
    kind = node.get("nodeType")
    if kind == "Test Case":
        yield suite, node
        return
    if kind == "Test Suite":
        suite = node.get("name")
    for child in node.get("children", []):
        yield from walk(child, suite)


def messages(node, kind):
    found = []
    for child in node.get("children", []):
        if child.get("nodeType") == kind:
            found.append(" ".join(child.get("name", "").split()))
        found.extend(messages(child, kind))
    return found


def cell(text, limit=300):
    text = text.replace("|", "\\|").replace("<", "&lt;")
    return text if len(text) <= limit else text[: limit - 1] + "…"


def summarize(summary, tests, title, allow_skips=True):
    """Return (markdown, problems). problems is empty for a clean run."""
    cases = [pair for root in tests.get("testNodes", []) for pair in walk(root)]
    by_result = {}
    for suite, case in cases:
        by_result.setdefault(case.get("result", "unknown"), []).append((suite, case))
    passed, failed, skipped, expected = (len(by_result.get(key, []))
                                         for key in ("Passed", "Failed", "Skipped", "Expected Failure"))
    other = len(cases) - passed - failed - skipped - expected
    seconds = sum(case.get("durationInSeconds", 0) for _, case in cases)
    devices = ", ".join(f"{d.get('deviceName', '?')} · iOS {d.get('osVersion', '?')}" for d in tests.get("devices", []))

    lines = [f"### {title}", "",
             f"**{passed} passed · {failed} failed · {skipped} skipped** of {len(cases)} tests"
             + (f" · {expected} failing as expected (quarantined)" if expected else "")
             + (f" · {other} with another result" if other else "")
             + f" · {seconds / 60:.1f} min of test time · {devices or 'no device recorded'}", ""]
    if failed:
        lines += ["| Failed test | First failure |", "| --- | --- |"]
        for suite, case in by_result["Failed"]:
            first = (messages(case, "Failure Message") or ["no message recorded"])[0]
            lines.append(f"| `{suite}/{case.get('name')}` | {cell(first)} |")
        lines.append("")
    if expected:
        lines += ["| Quarantined test (fails as expected) | Recorded reason |", "| --- | --- |"]
        for suite, case in by_result["Expected Failure"]:
            reason = (messages(case, "Expected Failure") or messages(case, "Failure Message") or ["no reason recorded"])[0]
            lines.append(f"| `{suite}/{case.get('name')}` | {cell(reason)} |")
        lines.append("")
    if skipped:
        reasons = {}
        for suite, case in by_result["Skipped"]:
            reason = (messages(case, "Skip Message") or ["no reason recorded"])[0]
            reasons.setdefault(reason, []).append(f"`{suite}/{case.get('name')}`")
        lines += ["<details><summary>Skipped tests, by reason</summary>", ""]
        for reason, names in sorted(reasons.items()):
            lines.append(f"- {cell(reason)}: {', '.join(names)}")
        lines += ["", "</details>", ""]
    slowest = sorted(cases, key=lambda pair: pair[1].get("durationInSeconds", 0), reverse=True)[:5]
    if slowest:
        lines.append("Slowest: " + ", ".join(
            f"`{case.get('name')}` {case.get('durationInSeconds', 0):.0f} s" for _, case in slowest))
        lines.append("")

    problems = []
    if not cases:
        problems.append("the result bundle contains no test case: nothing ran")
    if failed or summary.get("failedTests", 0):
        problems.append(f"{max(failed, summary.get('failedTests', 0))} failed test(s)")
    if other:
        problems.append(f"{other} test(s) with neither a pass, a failure nor a skip")
    if skipped and not allow_skips:
        problems.append(f"{skipped} test(s) skipped in a pass where every selected test must run")
    if summary.get("result") not in ("Passed", "Skipped", "Expected Failure") and not problems:
        problems.append(f"the bundle reports the overall result {summary.get('result')!r}")
    return "\n".join(lines), problems


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    pick = commands.add_parser("pick-simulator")
    pick.add_argument("--max-os", default="", help="newest iOS version the selected Xcode's SDK supports")
    choose = commands.add_parser("select")
    choose.add_argument("mode", choices=["only", "skip"])
    choose.add_argument("classes", nargs="*")
    choose.add_argument("--tests-directory", default="UITests")
    report = commands.add_parser("summary")
    report.add_argument("bundle")
    report.add_argument("--title", default="UI tests")
    report.add_argument("--no-skips", action="store_true", help="fail if any selected test was skipped")
    arguments = parser.parse_args()

    if arguments.command == "pick-simulator":
        udid, name, os_version = pick_simulator(json.load(sys.stdin), version_tuple(arguments.max_os) or None)
        print(f"Chosen simulator: {name}, iOS {os_version}", file=sys.stderr)
        print(udid)
    elif arguments.command == "select":
        print(" ".join(select(arguments.mode, arguments.classes, arguments.tests_directory)))
    else:
        if not pathlib.Path(arguments.bundle).exists():
            print(f"### {arguments.title}\n\nNo result bundle at `{arguments.bundle}`: the tests did not start.")
            raise SystemExit(1)
        text, problems = summarize(xcresulttool("summary", "--path", arguments.bundle),
                                   xcresulttool("tests", "--path", arguments.bundle),
                                   arguments.title, allow_skips=not arguments.no_skips)
        print(text)
        if problems:
            print("Not a clean run: " + "; ".join(problems) + ".")
            raise SystemExit(1)


if __name__ == "__main__":
    main()
