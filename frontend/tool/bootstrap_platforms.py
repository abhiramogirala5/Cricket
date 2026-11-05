#!/usr/bin/env python3
"""Prepare the Flutter app for a first run.

What it does (safe to run again, it never overwrites your own files):

1. Creates ``.env`` from ``.env.example`` when it is missing. The app bundles ``.env`` as an
   asset, so ``flutter pub get``, ``flutter test`` and builds fail without it.
2. Runs ``flutter create`` to generate the ``android/`` and ``ios/`` folders. Existing files
   (``pubspec.yaml``, ``lib/``, ``analysis_options.yaml``) are left alone.
3. Applies the few platform settings the app needs:
   * Android: ``INTERNET``, ``ACCESS_NETWORK_STATE`` and ``CAMERA`` permissions (the camera is
     declared as optional, so phones without one can still score), the minimum Android version
     (24, which the camera and body-pose plug-ins need), the app name, and plain-HTTP access to a
     local server in DEBUG and PROFILE builds only (release builds stay HTTPS-only).
   * iOS: the app name, the camera usage text and permission to reach a server on the local
     network (this does not allow arbitrary plain-HTTP internet traffic). The live umpire camera
     itself runs on Android only for now.
4. Removes the sample ``test/widget_test.dart`` that ``flutter create`` adds.

Run it from anywhere:  ``python3 frontend/tool/bootstrap_platforms.py``
Only the standard library is used. Requires the Flutter SDK on PATH (unless ``--skip-create``).
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

FRONTEND_DIR = Path(__file__).resolve().parent.parent
ORGANISATION = "com.gullyumpire"
PROJECT_NAME = "gully_umpire"
APP_LABEL = "Gully Umpire"

ANDROID_PERMISSIONS = (
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.CAMERA",
)
ANDROID_MIN_SDK = 24
IOS_LOCAL_NETWORK_TEXT = "Used only to reach a test server on your own network."
IOS_CAMERA_TEXT = "The camera follows the ball so the umpire assistant can help with wides and no-balls."


# --- Text patches (pure functions, so they are easy to test) ---------------------------------


def add_android_permissions(manifest: str) -> str:
    """Adds the permissions the app needs just before ``<application``."""
    match = re.search(r"^[ \t]*<application\b", manifest, re.MULTILINE)
    if match is None:
        raise ValueError("AndroidManifest.xml has no <application> element")
    missing = [name for name in ANDROID_PERMISSIONS if f'"{name}"' not in manifest]
    if not missing:
        return manifest
    lines = "".join(f'    <uses-permission android:name="{name}" />\n' for name in missing)
    return manifest[: match.start()] + lines + manifest[match.start() :]


def add_android_camera_feature(manifest: str) -> str:
    """Declares the camera as optional (a phone without one can still be used for scoring)."""
    if "android.hardware.camera" in manifest:
        return manifest
    match = re.search(r"^[ \t]*<application\b", manifest, re.MULTILINE)
    if match is None:
        raise ValueError("AndroidManifest.xml has no <application> element")
    line = '    <uses-feature android:name="android.hardware.camera" android:required="false" />\n'
    return manifest[: match.start()] + line + manifest[match.start() :]


_MIN_SDK = re.compile(r"(\bminSdk(?:Version)?\b[ \t]*(?:=[ \t]*)?)(flutter\.minSdkVersion|\d+)")


def set_android_min_sdk(gradle: str, minimum: int = ANDROID_MIN_SDK) -> str:
    """Makes sure the app's minimum Android version is at least ``minimum``.

    Works on both ``build.gradle`` (``minSdkVersion flutter.minSdkVersion``) and
    ``build.gradle.kts`` (``minSdk = flutter.minSdkVersion``). A higher number that is already
    there is kept.
    """
    match = _MIN_SDK.search(gradle)
    if match is None:
        raise ValueError("the Gradle file has no minSdk setting")
    value = match.group(2)
    if value.isdigit() and int(value) >= minimum:
        return gradle
    return gradle[: match.start(2)] + str(minimum) + gradle[match.end(2) :]


def set_android_label(manifest: str) -> str:
    """Sets the name shown under the launcher icon."""
    pattern = re.compile(r'(<application[^>]*?android:label=")[^"]*(")')
    if pattern.search(manifest) is None:
        return manifest
    return pattern.sub(lambda m: f"{m.group(1)}{APP_LABEL}{m.group(2)}", manifest, count=1)


def allow_cleartext_in_debug(manifest: str) -> str:
    """For the debug/profile manifests only: allows ``http://`` to a development server."""
    if "usesCleartextTraffic" in manifest:
        return manifest
    end = manifest.rfind("</manifest>")
    if end < 0:
        raise ValueError("manifest has no closing </manifest>")
    return (
        manifest[:end]
        + '    <application android:usesCleartextTraffic="true" />\n'
        + manifest[end:]
    )


def set_ios_display_name(plist: str) -> str:
    pattern = re.compile(r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)")
    return pattern.sub(lambda m: f"{m.group(1)}{APP_LABEL}{m.group(2)}", plist, count=1)


def add_ios_camera_text(plist: str) -> str:
    """The sentence iOS shows when the app asks for the camera."""
    if "NSCameraUsageDescription" in plist:
        return plist
    end = plist.rfind("</dict>")
    if end < 0:
        raise ValueError("Info.plist has no closing </dict>")
    addition = f"\t<key>NSCameraUsageDescription</key>\n\t<string>{IOS_CAMERA_TEXT}</string>\n"
    return plist[:end] + addition + plist[end:]


def retired_env_notes(text: str) -> list[str]:
    """Things in an existing ``.env`` that an older version of the app wrote and that changed."""
    keys = {}
    for raw in text.splitlines():
        line = raw.strip()
        if line and not line.startswith("#") and "=" in line:
            name, _, value = line.partition("=")
            keys[name.strip()] = value.strip().lower()
    notes = []
    if "ENABLE_MOCK_CV" in keys:
        notes.append(
            "ENABLE_MOCK_CV is not used any more (the app now uses the live camera). "
            "Delete that line. The simulation needs DEV_SIMULATE_CV=true and is for development only."
        )
    if keys.get("ENABLE_LIVE_CV") in ("false", "0", "no"):
        notes.append("ENABLE_LIVE_CV is off: the app will work as a plain scorer, without the camera.")
    off = [name for name in ("ENABLE_EDGE_REVIEW", "ENABLE_LBW_REVIEW") if keys.get(name) in ("false", "0", "no")]
    if off:
        notes.append(
            f"{' and '.join(off)} {'is' if len(off) == 1 else 'are'} false: the review aids from the "
            "tracked ball path are off. Set them to true (see .env.example) to use them."
        )
    return notes


def allow_ios_local_networking(plist: str) -> str:
    """Lets the app talk to a development server on the local network; nothing wider."""
    additions = ""
    if "NSAppTransportSecurity" not in plist:
        additions += (
            "\t<key>NSAppTransportSecurity</key>\n"
            "\t<dict>\n"
            "\t\t<key>NSAllowsLocalNetworking</key>\n"
            "\t\t<true/>\n"
            "\t</dict>\n"
        )
    if "NSLocalNetworkUsageDescription" not in plist:
        additions += (
            "\t<key>NSLocalNetworkUsageDescription</key>\n"
            f"\t<string>{IOS_LOCAL_NETWORK_TEXT}</string>\n"
        )
    if not additions:
        return plist
    end = plist.rfind("</dict>")
    if end < 0:
        raise ValueError("Info.plist has no closing </dict>")
    return plist[:end] + additions + plist[end:]


# --- File operations --------------------------------------------------------------------------


def _patch(path: Path, *patches) -> bool:
    """Applies text patches to a file. Returns True when the file changed."""
    if not path.is_file():
        print(f"  skipped (not found): {path.relative_to(FRONTEND_DIR)}")
        return False
    original = path.read_text(encoding="utf-8")
    text = original
    try:
        for patch in patches:
            text = patch(text)
    except ValueError as problem:
        print(f"  NOT UPDATED:         {path.relative_to(FRONTEND_DIR)} ({problem}); please set it by hand")
        return False
    if text == original:
        print(f"  already set:         {path.relative_to(FRONTEND_DIR)}")
        return False
    path.write_text(text, encoding="utf-8")
    print(f"  updated:             {path.relative_to(FRONTEND_DIR)}")
    return True


def ensure_env_file() -> None:
    env = FRONTEND_DIR / ".env"
    example = FRONTEND_DIR / ".env.example"
    if env.exists():
        print("  .env already exists (left as it is)")
        for note in retired_env_notes(env.read_text(encoding="utf-8")):
            print(f"  NOTE: {note}")
        return
    shutil.copyfile(example, env)
    print("  created .env from .env.example (edit API_BASE_URL if needed)")


def run_flutter_create() -> None:
    flutter = shutil.which("flutter")
    if flutter is None:
        sys.exit(
            "The Flutter SDK was not found on PATH. Install it from https://docs.flutter.dev/get-started/install "
            "and run this script again."
        )
    subprocess.run(
        [
            flutter,
            "create",
            ".",
            "--project-name",
            PROJECT_NAME,
            "--org",
            ORGANISATION,
            "--platforms",
            "android,ios",
            "--no-pub",
        ],
        cwd=FRONTEND_DIR,
        check=True,
    )


def remove_sample_test() -> None:
    sample = FRONTEND_DIR / "test" / "widget_test.dart"
    if sample.is_file() and "Counter increments smoke test" in sample.read_text(encoding="utf-8"):
        sample.unlink()
        print("  removed the sample test/widget_test.dart")


def apply_platform_settings() -> None:
    android = FRONTEND_DIR / "android" / "app" / "src"
    print("Android:")
    _patch(
        android / "main" / "AndroidManifest.xml",
        add_android_permissions,
        add_android_camera_feature,
        set_android_label,
    )
    gradle_files = [
        FRONTEND_DIR / "android" / "app" / name for name in ("build.gradle.kts", "build.gradle")
    ]
    gradle = next((path for path in gradle_files if path.is_file()), gradle_files[0])
    _patch(gradle, set_android_min_sdk)
    for flavour in ("debug", "profile"):
        _patch(android / flavour / "AndroidManifest.xml", allow_cleartext_in_debug)
    print("iOS:")
    _patch(
        FRONTEND_DIR / "ios" / "Runner" / "Info.plist",
        set_ios_display_name,
        add_ios_camera_text,
        allow_ios_local_networking,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument(
        "--skip-create",
        action="store_true",
        help="do not run `flutter create` (use when android/ and ios/ already exist)",
    )
    args = parser.parse_args()

    print("Configuration:")
    ensure_env_file()
    if not args.skip_create:
        print("Generating platform folders with `flutter create` ...")
        run_flutter_create()
    remove_sample_test()
    apply_platform_settings()
    print(
        "\nDone. Next:\n"
        "  cd frontend\n"
        "  flutter pub get\n"
        "  flutter analyze && flutter test\n"
        "  flutter run"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
