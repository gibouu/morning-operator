import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "ci_scripts" / "ci_post_clone.sh"
CLIENT = "123456789-example.apps.googleusercontent.com"
CALLBACK = "com.googleusercontent.apps.123456789-example"


class XcodeCloudConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.checkout = Path(self.temporary.name)
        self.plist = self.checkout / "Configuration" / "iOS-Info.plist"
        self.plist.parent.mkdir()
        shutil.copyfile(REPO / "Configuration" / "iOS-Info.plist", self.plist)
        self.original = self.plist.read_bytes()
        self.environment = dict(os.environ)
        self.environment.update(CI_XCODE_CLOUD="TRUE", CI_PRIMARY_REPOSITORY_PATH=str(self.checkout),
                                MORE_GOOGLE_CLIENT_ID=CLIENT, MORE_GOOGLE_CALLBACK_SCHEME=CALLBACK)
        self.environment.pop("MORNING_API_BASE_URL", None)

    def run_hook(self):
        return subprocess.run([str(SCRIPT)], env=self.environment, capture_output=True, text=True)

    def assert_configuration(self, api_url):
        expected = plistlib.loads(self.original)
        expected["MOREGoogleClientID"] = CLIENT
        expected["MorningAPIBaseURL"] = api_url
        next(entry for entry in expected["CFBundleURLTypes"]
             if entry["CFBundleURLName"] == "com.gibouu.morningoperator.google")["CFBundleURLSchemes"] = [CALLBACK]
        self.assertEqual(plistlib.loads(self.plist.read_bytes()), expected)

    def test_optional_backend_stays_empty_and_only_public_entries_change(self):
        for api_url in [None, ""]:
            with self.subTest(api_url=api_url):
                self.plist.write_bytes(self.original)
                if api_url is not None:
                    self.environment["MORNING_API_BASE_URL"] = api_url
                result = self.run_hook()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assert_configuration("")
                self.assertNotIn(CLIENT, result.stdout + result.stderr)

    def test_explicit_https_backend_and_repeat_run(self):
        self.environment["MORNING_API_BASE_URL"] = "https://api.example.test:8443/v1/"
        for _ in range(2):
            result = self.run_hook()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assert_configuration(self.environment["MORNING_API_BASE_URL"])
            self.assertNotIn(self.environment["MORNING_API_BASE_URL"], result.stdout + result.stderr)

    def test_invalid_google_and_backend_configuration_fails_before_writing(self):
        cases = [
            {"MORE_GOOGLE_CLIENT_ID": ""},
            {"MORE_GOOGLE_CLIENT_ID": "not-an-ios-client"},
            {"MORE_GOOGLE_CLIENT_ID": "bad.prefix.apps.googleusercontent.com"},
            {"MORE_GOOGLE_CALLBACK_SCHEME": ""},
            {"MORE_GOOGLE_CALLBACK_SCHEME": "com.googleusercontent.apps.other"},
            *({"MORNING_API_BASE_URL": url} for url in [
                "http://api.example.test", "https://", "https://bad host.test", "https://bad_host.test",
                "https://user:password@api.example.test", "https://api.example.test?token=private",
                "https://api.example.test/#fragment", "https://api.example.test:99999", " https://api.example.test",
            ]),
        ]
        for changes in cases:
            with self.subTest(changes=changes):
                baseline = dict(self.environment)
                self.environment.update(changes)
                result = self.run_hook()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.plist.read_bytes(), self.original)
                self.environment = baseline

    def test_local_clone_does_not_require_configuration_or_change_plist(self):
        self.environment.pop("CI_XCODE_CLOUD")
        self.environment.pop("MORE_GOOGLE_CLIENT_ID")
        self.environment.pop("MORE_GOOGLE_CALLBACK_SCHEME")
        result = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.plist.read_bytes(), self.original)


if __name__ == "__main__":
    unittest.main()
