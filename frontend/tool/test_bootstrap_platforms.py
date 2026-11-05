"""Tests for the text patches of bootstrap_platforms.py.  Run:  python3 -m unittest discover -s tool"""

from __future__ import annotations

import importlib.util
import plistlib
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("bootstrap_platforms", Path(__file__).with_name("bootstrap_platforms.py"))
bp = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bp)

MAIN_MANIFEST = """<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="gully_umpire"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity android:name=".MainActivity" android:exported="true">
        </activity>
    </application>
</manifest>
"""

KTS = """android {
    defaultConfig {
        applicationId = "com.gullyumpire.gully_umpire"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
    }
}
"""

GROOVY = """android {
    defaultConfig {
        applicationId "com.gullyumpire.gully_umpire"
        minSdkVersion flutter.minSdkVersion
        targetSdkVersion flutter.targetSdkVersion
    }
}
"""

PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>CFBundleDisplayName</key>
\t<string>Gully Umpire X</string>
\t<key>CFBundleName</key>
\t<string>gully_umpire</string>
</dict>
</plist>
"""


class AndroidManifestTests(unittest.TestCase):
    def test_permissions_are_added_once_before_application(self) -> None:
        out = bp.add_android_permissions(MAIN_MANIFEST)
        for name in bp.ANDROID_PERMISSIONS:
            self.assertEqual(out.count(f'"{name}"'), 1)
        self.assertLess(out.index("uses-permission"), out.index("<application"))
        self.assertIn("android.permission.CAMERA", out)
        self.assertEqual(bp.add_android_permissions(out), out)

    def test_an_existing_permission_is_not_repeated(self) -> None:
        pre = MAIN_MANIFEST.replace(
            "<application", '<uses-permission android:name="android.permission.CAMERA"/>\n    <application', 1
        )
        out = bp.add_android_permissions(pre)
        self.assertEqual(out.count("android.permission.CAMERA"), 1)
        self.assertEqual(out.count("android.permission.INTERNET"), 1)

    def test_the_camera_is_declared_optional(self) -> None:
        out = bp.add_android_camera_feature(MAIN_MANIFEST)
        self.assertIn('android:name="android.hardware.camera" android:required="false"', out)
        self.assertLess(out.index("uses-feature"), out.index("<application"))
        self.assertEqual(bp.add_android_camera_feature(out), out)

    def test_a_manifest_without_application_is_refused(self) -> None:
        with self.assertRaises(ValueError):
            bp.add_android_permissions("<manifest></manifest>")
        with self.assertRaises(ValueError):
            bp.add_android_camera_feature("<manifest></manifest>")

    def test_the_label_is_set(self) -> None:
        out = bp.set_android_label(MAIN_MANIFEST)
        self.assertIn('android:label="Gully Umpire"', out)
        self.assertEqual(bp.set_android_label(out), out)

    def test_debug_manifests_allow_plain_http_once(self) -> None:
        debug = '<manifest>\n    <uses-permission android:name="android.permission.INTERNET"/>\n</manifest>\n'
        out = bp.allow_cleartext_in_debug(debug)
        self.assertEqual(out.count("usesCleartextTraffic"), 1)
        self.assertTrue(out.rstrip().endswith("</manifest>"))
        self.assertEqual(bp.allow_cleartext_in_debug(out), out)


class MinSdkTests(unittest.TestCase):
    def test_kotlin_script_is_raised(self) -> None:
        out = bp.set_android_min_sdk(KTS)
        self.assertIn("minSdk = 24", out)
        self.assertNotIn("flutter.minSdkVersion", out)
        self.assertIn("targetSdk = flutter.targetSdkVersion", out)

    def test_groovy_is_raised(self) -> None:
        out = bp.set_android_min_sdk(GROOVY)
        self.assertIn("minSdkVersion 24", out)
        self.assertIn("targetSdkVersion flutter.targetSdkVersion", out)

    def test_a_lower_number_is_raised_and_a_higher_one_kept(self) -> None:
        self.assertIn("minSdk = 24", bp.set_android_min_sdk("minSdk = 21"))
        self.assertEqual(bp.set_android_min_sdk("minSdk = 26"), "minSdk = 26")
        self.assertEqual(bp.set_android_min_sdk("minSdk = 24"), "minSdk = 24")

    def test_it_is_idempotent(self) -> None:
        once = bp.set_android_min_sdk(KTS)
        self.assertEqual(bp.set_android_min_sdk(once), once)

    def test_a_file_without_the_setting_is_refused(self) -> None:
        with self.assertRaises(ValueError):
            bp.set_android_min_sdk("android { }")


class IosTests(unittest.TestCase):
    def test_display_name_is_set(self) -> None:
        out = bp.set_ios_display_name(PLIST)
        self.assertIn("<string>Gully Umpire</string>", out)
        self.assertNotIn("Gully Umpire X", out)

    def test_camera_text_and_local_networking_make_a_valid_plist(self) -> None:
        out = bp.allow_ios_local_networking(bp.add_ios_camera_text(bp.set_ios_display_name(PLIST)))
        parsed = plistlib.loads(out.encode())
        self.assertEqual(parsed["NSAppTransportSecurity"], {"NSAllowsLocalNetworking": True})
        self.assertIn("NSLocalNetworkUsageDescription", parsed)
        self.assertEqual(parsed["NSCameraUsageDescription"], bp.IOS_CAMERA_TEXT)
        self.assertEqual(bp.add_ios_camera_text(out), out)
        self.assertEqual(bp.allow_ios_local_networking(out), out)


class EnvNoteTests(unittest.TestCase):
    def test_a_current_file_has_no_notes(self) -> None:
        text = "APP_ENV=development\nENABLE_LIVE_CV=true\nENABLE_EDGE_REVIEW=true\nENABLE_LBW_REVIEW=true\n"
        self.assertEqual(bp.retired_env_notes(text), [])

    def test_the_old_simulation_key_is_pointed_out(self) -> None:
        notes = bp.retired_env_notes("ENABLE_MOCK_CV=true\n")
        self.assertEqual(len(notes), 1)
        self.assertIn("DEV_SIMULATE_CV", notes[0])

    def test_comments_do_not_count(self) -> None:
        self.assertEqual(bp.retired_env_notes("# ENABLE_MOCK_CV=true\n"), [])

    def test_a_switched_off_camera_is_mentioned(self) -> None:
        notes = bp.retired_env_notes("ENABLE_LIVE_CV=false\n")
        self.assertEqual(len(notes), 1)
        self.assertIn("plain scorer", notes[0])

    def test_review_aids_that_are_off_are_mentioned(self) -> None:
        both = bp.retired_env_notes("ENABLE_EDGE_REVIEW=false\nENABLE_LBW_REVIEW=false\n")
        self.assertEqual(len(both), 1)
        self.assertIn("ENABLE_EDGE_REVIEW and ENABLE_LBW_REVIEW are false", both[0])
        one = bp.retired_env_notes("ENABLE_EDGE_REVIEW=false\nENABLE_LBW_REVIEW=true\n")
        self.assertIn("ENABLE_EDGE_REVIEW is false", one[0])


if __name__ == "__main__":
    unittest.main()
