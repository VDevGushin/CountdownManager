#!/usr/bin/env python3
"""Regression checks for update release boundaries; never reads production data."""
import base64
import argparse
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("update_tools", ROOT / "scripts/update_tools.py")
tools = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tools)


class UpdateToolsChecks(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="countdown-packaging.", dir="/private/tmp")
        self.root = Path(self.directory.name)
        self.plist = self.root / "Info.plist"
        self.original = {"CFBundleIdentifier": tools.PRODUCTION_ID, "CFBundleVersion": "12",
                         "CFBundleShortVersionString": "1.6.0", "LSMinimumSystemVersion": "13.0"}
        tools.write_plist(self.plist, self.original)
        self.key = base64.b64encode(bytes(range(32))).decode()

    def tearDown(self):
        self.directory.cleanup()

    def release_environment(self):
        return {"COUNTDOWN_UPDATE_MODE": "release", "COUNTDOWN_UPDATE_FEED_URL":
                "https://vdevgushin.github.io/CountdownManager/appcast.xml",
                "COUNTDOWN_UPDATE_PUBLIC_KEY": self.key, "COUNTDOWN_BUILD_NUMBER": "13"}

    def test_development_bundle_has_no_network_channel(self):
        data = tools.configure(self.plist, {})
        self.assertNotIn("SUFeedURL", data)
        self.assertNotIn("SUPublicEDKey", data)
        self.assertFalse(data["SUEnableAutomaticChecks"])
        self.assertEqual(data["CFBundleIdentifier"], tools.PRODUCTION_ID)

    def test_release_requires_explicit_configuration_and_preserves_identity(self):
        env = self.release_environment()
        data = tools.configure(self.plist, env)
        self.assertEqual(data["CFBundleVersion"], "13")
        self.assertEqual(data["CFBundleIdentifier"], tools.PRODUCTION_ID)
        self.assertEqual(data["LSMinimumSystemVersion"], "13.0")
        self.assertTrue(data["SURequireSignedFeed"])
        self.assertTrue(data["SUVerifyUpdateBeforeExtraction"])
        self.assertFalse(data["SUAllowsAutomaticUpdates"])
        self.assertEqual(data["SUSignedFeedFailureExpirationInterval"], 0)

    def test_disabled_mode_cannot_strip_isolation_from_a_test_bundle(self):
        original = dict(self.original, CFBundleIdentifier=tools.TEST_ID, CountdownUpdateTestMode=True)
        tools.write_plist(self.plist, original)
        with self.assertRaisesRegex(ValueError, "production bundle identifier"):
            tools.configure(self.plist, {})
        self.assertEqual(tools.read_plist(self.plist), original)

    def test_release_rejects_missing_key_http_and_placeholder_without_writing(self):
        for override in ({"COUNTDOWN_UPDATE_PUBLIC_KEY": ""},
                         {"COUNTDOWN_UPDATE_PUBLIC_KEY": base64.b64encode(bytes(32)).decode()},
                         {"COUNTDOWN_UPDATE_FEED_URL": "http://127.0.0.1:8765/appcast.xml"},
                         {"COUNTDOWN_UPDATE_FEED_URL": "https://example.com/appcast.xml"}):
            with self.subTest(override=override):
                env = self.release_environment()
                env.update(override)
                with self.assertRaises(ValueError):
                    tools.configure(self.plist, env)
                self.assertEqual(tools.read_plist(self.plist), self.original)

    def test_test_build_requires_marker_and_persists_isolation_across_relaunch(self):
        home = self.root / "home"
        home.mkdir()
        env = self.release_environment()
        env.update(COUNTDOWN_UPDATE_MODE="test", COUNTDOWN_UPDATE_FEED_URL=
                   "http://127.0.0.1:8765/appcast.xml", COUNTDOWN_MANAGER_TEST_HOME=str(home))
        with self.assertRaises(ValueError):
            tools.configure(self.plist, env)
        (home / tools.TEST_MARKER).touch()
        data = tools.configure(self.plist, env)
        self.assertEqual(data["CFBundleIdentifier"], tools.TEST_ID)
        self.assertEqual(data["SUDefaultsDomain"], tools.TEST_ID)
        self.assertEqual(data["CountdownUpdateTestHome"], str(home.resolve()))
        self.assertTrue(data["CountdownUpdateTestMode"])
        self.assertEqual(data["NSAppTransportSecurity"], {"NSAllowsLocalNetworking": True})

    def test_loopback_exemption_never_allows_remote_http_or_credentials(self):
        for url in ("http://evil.org/appcast.xml", "http://127.0.0.1.evil.org/appcast.xml",
                    "https://user:secret@github.com/feed", "file:///private/tmp/appcast.xml"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                tools.feed_url(url, test=True)

    def test_production_data_overlap_is_rejected_before_marker(self):
        production = Path.home() / "Library/Application Support/CountdownManager"
        for home in (production, production / "tests", production.parent):
            with self.subTest(home=home), self.assertRaisesRegex(ValueError, "overlaps"):
                tools.isolated_home(str(home))

    def test_output_cannot_install_in_applications(self):
        with self.assertRaisesRegex(ValueError, "/Applications"):
            tools.install_built_bundle(self.root, "/Applications/Countdown Manager.app")

    def test_private_file_requires_restricted_permissions_and_external_location(self):
        private = self.root / "private"
        private.write_text("not-a-real-key")
        private.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "0600"):
            tools.validate_private_file(private)
        private.chmod(0o600)
        self.assertEqual(tools.validate_private_file(private), private.resolve())
        with self.assertRaisesRegex(ValueError, "outside"):
            tools.validate_private_file(ROOT / "never-create-private-key")

    def test_embed_preserves_symlinks_and_signs_helpers_before_containers(self):
        artifact = self.root / "build/artifacts/sparkle/Sparkle"
        original = artifact / "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
        original.mkdir(parents=True)
        app = self.root / "Fixture.app"
        framework = app / "Contents/Frameworks/Sparkle.framework"
        version = framework / "Versions/B"
        for name in ("XPCServices/Installer.xpc", "XPCServices/Downloader.xpc", "Updater.app"):
            (version / name).mkdir(parents=True)
        (version / "Autoupdate").touch()
        (version / "Sparkle").touch()
        (framework / "Versions/Current").symlink_to("B")
        (framework / "Sparkle").symlink_to("Versions/Current/Sparkle")
        with patch.object(tools, "run") as calls:
            tools.embed(self.root / "build", app)
        arguments = [x.args[0] for x in calls.call_args_list]
        self.assertEqual(arguments[0][0], "/usr/bin/ditto")
        signed = [x[-1] for x in arguments if "--sign" in x]
        self.assertEqual(signed[-2:], [framework, app])
        self.assertEqual(len(signed), 6)
        self.assertTrue(all("--deep" not in x for x in arguments if "--sign" in x))

    def test_release_rejects_wrong_signing_key_before_creating_archive(self):
        data = tools.configure(self.plist, self.release_environment())
        app = self.root / "Fixture.app"
        (app / "Contents").mkdir(parents=True)
        tools.write_plist(app / "Contents/Info.plist", data)
        key = self.root / "private"
        key.write_text("test-only-not-a-real-key")
        key.chmod(0o600)
        output = self.root / "release"
        args = argparse.Namespace(app=app, private_key=key, test=False,
                                  download_url_prefix="https://github.com/VDevGushin/CountdownManager/releases/download/v1.7/",
                                  output=output, build_dir=self.root / "build")
        with patch.object(tools, "key_public", return_value=base64.b64encode(bytes([1]) * 32).decode()), \
                patch.object(tools, "run") as commands, \
                self.assertRaisesRegex(ValueError, "does not match"):
            tools.release(args)
        commands.assert_not_called()
        self.assertFalse(output.exists())

    def test_test_archive_cannot_be_packaged_as_production_release(self):
        app = self.root / "Fixture.app"
        (app / "Contents").mkdir(parents=True)
        tools.write_plist(app / "Contents/Info.plist", {"CountdownUpdateTestMode": True})
        args = argparse.Namespace(app=app, test=False)
        with self.assertRaisesRegex(ValueError, "Test bundles require"):
            tools.release(args)


if __name__ == "__main__":
    unittest.main()
