import importlib.util
import pathlib
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "ui-tests-ci.py"
spec = importlib.util.spec_from_file_location("ui_tests_ci", SCRIPT)
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)


def device(name, udid, available=True):
    return {"name": name, "udid": udid, "isAvailable": available}


def case(name, result, seconds=1.0, children=()):
    return {"nodeType": "Test Case", "name": name, "result": result,
            "durationInSeconds": seconds, "children": list(children)}


def bundle(*cases):
    return {"devices": [{"deviceName": "iPhone", "osVersion": "27.0"}],
            "testNodes": [{"nodeType": "Test Plan", "name": "plan", "children": [
                {"nodeType": "Test Suite", "name": "SuiteTests", "children": list(cases)}]}]}


class PickSimulatorTests(unittest.TestCase):
    PREFIX = "com.apple.CoreSimulator.SimRuntime."

    def listing(self):
        return {"devices": {
            self.PREFIX + "iOS-26-4": [device("iPhone 17 Pro", "old")],
            self.PREFIX + "iOS-27-0": [device("iPhone 18 Pro Max", "max"), device("iPhone 18 Pro", "pro"),
                                        device("iPhone 18", "plain"), device("iPad Pro", "pad"),
                                        device("iPhone 19 Pro", "gone", available=False)],
            self.PREFIX + "iOS-27-1": [device("iPhone 18 Pro", "beta")],
            self.PREFIX + "watchOS-27-0": [device("Apple Watch", "watch")],
        }}

    def test_newest_runtime_and_a_pro_iphone(self):
        self.assertEqual(ci.pick_simulator(self.listing())[0], "beta")

    def test_runtime_newer_than_the_sdk_is_left_alone(self):
        self.assertEqual(ci.pick_simulator(self.listing(), (27, 0)), ("pro", "iPhone 18 Pro", "27.0"))

    def test_falls_back_when_every_runtime_is_newer_than_the_sdk(self):
        self.assertEqual(ci.pick_simulator(self.listing(), (25, 0))[0], "beta")

    def test_any_iphone_when_no_pro_exists(self):
        listing = {"devices": {self.PREFIX + "iOS-27-0": [device("iPhone 18e", "e"), device("iPad Air", "pad")]}}
        self.assertEqual(ci.pick_simulator(listing)[0], "e")

    def test_no_iphone_is_an_error(self):
        with self.assertRaises(SystemExit):
            ci.pick_simulator({"devices": {self.PREFIX + "iOS-27-0": [device("iPad Air", "pad")]}})


class SelectTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        pathlib.Path(self.directory.name, "A.swift").write_text(
            "@MainActor\nfinal class FirstTests: XCTestCase {}\nclass SecondTests : XCTestCase {}\nenum Helper {}\n")

    def test_known_classes_become_arguments(self):
        self.assertEqual(ci.select("only", ["FirstTests", "SecondTests"], self.directory.name),
                         ["-only-testing:MorningOperatorUITests/FirstTests",
                          "-only-testing:MorningOperatorUITests/SecondTests"])
        self.assertEqual(ci.select("skip", ["FirstTests"], self.directory.name),
                         ["-skip-testing:MorningOperatorUITests/FirstTests"])

    def test_a_misspelt_or_missing_class_is_refused(self):
        for classes in (["FirstTest"], ["Helper"], []):
            with self.assertRaises(SystemExit):
                ci.select("only", classes, self.directory.name)

    def test_every_class_named_in_the_workflow_exists(self):
        root = SCRIPT.parents[1]
        workflow = (root / ".github/workflows/ui-tests.yml").read_text()
        names = [name for line in workflow.splitlines() if "_CLASSES:" in line
                 for name in line.split(":", 1)[1].split()]
        self.assertGreater(len(names), 0)
        ci.select("only", names, root / "UITests")
        self.assertEqual(len(names), len(set(names)), "a class sits in two shards")


class SummaryTests(unittest.TestCase):
    def test_clean_run_with_grouped_skips(self):
        skip = [{"nodeType": "Skip Message", "name": "Needs a phone"}]
        text, problems = ci.summarize({"result": "Passed", "failedTests": 0},
                                      bundle(case("testA", "Passed"), case("testB", "Skipped", 0, skip),
                                             case("testC", "Skipped", 0, skip)), "Title")
        self.assertEqual(problems, [])
        self.assertIn("**1 passed · 0 failed · 2 skipped** of 3 tests", text)
        self.assertIn("- Needs a phone: `SuiteTests/testB`, `SuiteTests/testC`", text)

    def test_a_failure_is_listed_and_reported(self):
        failure = [{"nodeType": "Failure Message", "name": "File.swift:3: XCTAssertTrue failed | detail"}]
        text, problems = ci.summarize({"result": "Failed", "failedTests": 1},
                                      bundle(case("testA", "Passed"), case("testB", "Failed", 2, failure)), "Title")
        self.assertEqual(problems, ["1 failed test(s)"])
        self.assertIn("| `SuiteTests/testB` | File.swift:3: XCTAssertTrue failed \\| detail |", text)

    def test_a_failure_only_the_summary_knows_about_is_still_reported(self):
        _, problems = ci.summarize({"result": "Failed", "failedTests": 2}, bundle(case("testA", "Passed")), "Title")
        self.assertEqual(problems, ["2 failed test(s)"])

    def test_nothing_ran_is_a_problem(self):
        _, problems = ci.summarize({"result": "Passed"}, {"devices": [], "testNodes": []}, "Title")
        self.assertEqual(problems, ["the result bundle contains no test case: nothing ran"])

    def test_skips_can_be_forbidden(self):
        tests = bundle(case("testA", "Skipped"))
        self.assertEqual(ci.summarize({"result": "Skipped"}, tests, "Title")[1], [])
        self.assertEqual(len(ci.summarize({"result": "Skipped"}, tests, "Title", allow_skips=False)[1]), 1)

    def test_a_quarantined_test_is_listed_but_is_not_a_problem(self):
        reason = [{"nodeType": "Expected Failure", "name": "Does not fit (issue #1)"}]
        text, problems = ci.summarize({"result": "Passed", "failedTests": 0},
                                      bundle(case("testA", "Passed"), case("testB", "Expected Failure", 1, reason)), "Title")
        self.assertEqual(problems, [])
        self.assertIn("1 failing as expected (quarantined)", text)
        self.assertIn("| `SuiteTests/testB` | Does not fit (issue #1) |", text)

    def test_an_unknown_result_is_a_problem(self):
        _, problems = ci.summarize({"result": "unknown"}, bundle(case("testA", "unknown")), "Title")
        self.assertEqual(len(problems), 1)


if __name__ == "__main__":
    unittest.main()
