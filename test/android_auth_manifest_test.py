"""Offline check that Android registers the app's existing Supabase callback."""
import pathlib
import re
import unittest
import urllib.parse
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
ANDROID = "{http://schemas.android.com/apk/res/android}"


class AndroidAuthManifestTest(unittest.TestCase):
    def test_auth_redirect_is_a_browsable_activity_link(self):
        auth = (ROOT / "lib/net/auth.dart").read_text(encoding="utf-8")
        match = re.search(r"const\s+kAuthRedirect\s*=\s*'([^']+)'", auth)
        self.assertIsNotNone(match, "existing auth redirect constant not found")
        uri = urllib.parse.urlsplit(match.group(1))
        manifest = ET.parse(ROOT / "android/app/src/main/AndroidManifest.xml")
        activity = manifest.find("./application/activity[@%sname='.MainActivity']" % ANDROID)
        self.assertIsNotNone(activity)
        self.assertEqual(activity.get(ANDROID + "exported"), "true")
        self.assertEqual(activity.get(ANDROID + "launchMode"), "singleTop")
        self.assertTrue(any(
            meta.get(ANDROID + "name") == "flutter_deeplinking_enabled"
            and meta.get(ANDROID + "value") == "false"
            for meta in activity.findall("meta-data")
        ), "Supabase's app_links listener must handle deep links")
        matching = []
        for intent_filter in activity.findall("intent-filter"):
            actions = {e.get(ANDROID + "name") for e in intent_filter.findall("action")}
            categories = {e.get(ANDROID + "name") for e in intent_filter.findall("category")}
            data = intent_filter.findall("data")
            if ("android.intent.action.VIEW" in actions
                    and {"android.intent.category.DEFAULT", "android.intent.category.BROWSABLE"} <= categories
                    and any(e.get(ANDROID + "scheme") == uri.scheme
                            and e.get(ANDROID + "host") == uri.hostname
                            and not any(e.get(ANDROID + n) for n in ("path", "pathPrefix", "pathPattern"))
                            for e in data)):
                matching.append(intent_filter)
        self.assertEqual(len(matching), 1, "expected one handler for the configured auth callback")


if __name__ == "__main__":
    unittest.main()
