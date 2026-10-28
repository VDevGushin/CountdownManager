"""Mechanical native build-contract checks. No compiler, GUI, or application is launched."""

import copy
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("native_design_contract", ROOT / "scripts/native_design_contract.py")
contract_tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract_tool)


def macho(sdk="13.0", minimum="13.0", platform="1"):
    return f"""probe:
Load command 10
      cmd LC_BUILD_VERSION
  cmdsize 32
 platform {platform}
    minos {minimum}
      sdk {sdk}
   ntools 1
     tool 3
  version 27037.1
Load command 11
      cmd LC_MAIN
  cmdsize 24
 entryoff 100
"""


class NativeDesignContractChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.contract_path = self.root / "NativeDesignContract.json"
        self.contract = json.loads((ROOT / "Resources/NativeDesignContract.json").read_text())
        self.write_contract()
        for authority in self.contract["sourceAuthority"].values():
            path = self.root / authority
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("Native fixture authority: " + authority)
        self.sdk = self.root / "MacOSX15.4.sdk"
        self.sdk.mkdir()
        (self.sdk / "SDKSettings.json").write_text(json.dumps({"Version": "15.4", "CanonicalName": "macosx15.4"}))
        self.swift = self.root / "swift"
        self.swift.touch()
        self.app = self.root / "Fixture.app"
        (self.app / "Contents/MacOS").mkdir(parents=True)
        (self.app / "Contents/MacOS/Fixture").touch()
        self.info = {"CFBundleExecutable": "Fixture", "CFBundleIdentifier": "local.fixture",
                     "CFBundleShortVersionString": "1.18.1", "CFBundleVersion": "34",
                     "LSMinimumSystemVersion": "13.0"}
        self.write_info()
        self.otool = macho()
        self.signature_identifier = "local.fixture"
        self.calls = []
        self.context = contract_tool.snapshot_build(self.contract_path, str(self.sdk), str(self.swift),
                                                    self.root, self.command)
        self.context_path = self.root / "context.json"
        self.context_path.write_text(json.dumps(self.context))

    def write_contract(self):
        self.contract_path.write_text(json.dumps(self.contract))

    def write_info(self):
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps(self.info))

    def command(self, args):
        self.calls.append(args)
        if args[0] == str(self.swift):
            return "Apple Swift version 6.4\nTarget: arm64-apple-macosx26.0"
        if args[0] == "/usr/bin/otool":
            return self.otool
        if args[0] == "/usr/bin/codesign":
            if "--display" in args:
                return "Executable=Fixture\nIdentifier=" + self.signature_identifier + "\nSignature=adhoc\n"
            return ""
        self.fail("Unexpected external operation: " + repr(args))

    def record(self):
        return contract_tool.record_build(self.app, self.contract_path, self.context_path, self.root, self.command)

    def verify(self):
        return contract_tool.verify_build(self.app, self.contract_path, self.root, self.command)

    def test_explicit_link_flags_keep_deployment_and_compatibility_separate(self):
        flags = contract_tool.linker_flags(self.contract)
        self.assertEqual(flags, ["-Xlinker", "-platform_version", "-Xlinker", "macos",
                                 "-Xlinker", "13.0", "-Xlinker", "13.0"])

    def test_modern_otool_ignores_linker_tool_version(self):
        records = contract_tool.parse_otool(macho())
        self.assertEqual(records[0]["minos"], "13.0")
        self.assertEqual(records[0]["sdk"], "13.0")
        contract_tool.validate_linked_metadata(records, self.contract)

    def test_legacy_load_command_is_parsed(self):
        records = contract_tool.parse_otool("cmd LC_VERSION_MIN_MACOSX\n version 13.0\n sdk 13.0\n")
        self.assertEqual(records[0]["platform"], "1")
        contract_tool.validate_linked_metadata(records, self.contract)

    def test_every_universal_architecture_must_match(self):
        output = "probe (architecture arm64):\n" + macho()
        output += "probe (architecture x86_64):\n" + macho(sdk="15.4")
        records = contract_tool.parse_otool(output)
        self.assertEqual([item["architecture"] for item in records], ["arm64", "x86_64"])
        with self.assertRaisesRegex(contract_tool.ContractError, "Linked compatibility drift"):
            contract_tool.validate_linked_metadata(records, self.contract)

    def test_wrong_platform_deployment_and_sdk_fail(self):
        for output in [macho(platform="2"), macho(minimum="14.0"), macho(sdk="15.4")]:
            with self.subTest(output=output), self.assertRaises(contract_tool.ContractError):
                contract_tool.validate_linked_metadata(contract_tool.parse_otool(output), self.contract)

    def test_missing_or_incomplete_build_metadata_fails(self):
        for output in ["", "cmd LC_MAIN\n", "cmd LC_BUILD_VERSION\n minos 13.0\n sdk 13.0\n",
                       "cmd LC_BUILD_VERSION\n platform 1\n minos 13.0\n"]:
            with self.subTest(output=output), self.assertRaises(contract_tool.ContractError):
                contract_tool.parse_otool(output)

    def test_record_and_verify_preserve_actual_headers_sdk_truth(self):
        provenance = self.record()
        self.assertEqual(provenance["compilerSDK"]["version"], "15.4")
        self.assertEqual(provenance["linkedCompatibility"], "13.0")
        self.assertFalse(provenance["renderedAppearanceVerified"])
        result = self.verify()
        self.assertEqual(result["styleVersion"], self.contract["styleVersion"])
        self.assertEqual(result["signatureIdentifier"], "local.fixture")
        self.assertIn(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(self.app)], self.calls)

    def test_claiming_headers_sdk_13_against_actual_15_4_is_rejected(self):
        self.record()
        path = self.app / "Contents/Resources" / contract_tool.PROVENANCE_RESOURCE
        provenance = json.loads(path.read_text())
        provenance["compilerSDK"]["version"] = "13.0"
        path.write_text(json.dumps(provenance))
        with self.assertRaisesRegex(contract_tool.ContractError, "SDK provenance is not truthful"):
            self.verify()

    def test_application_versions_do_not_choose_style_version(self):
        first = self.record()
        self.info["CFBundleShortVersionString"] = "99.2.0"
        self.info["CFBundleVersion"] = "9999"
        self.write_info()
        second = self.record()
        self.assertEqual(first["styleVersion"], second["styleVersion"])
        self.assertNotEqual(first["application"], second["application"])
        self.verify()

    def test_application_metadata_cannot_change_after_recording(self):
        self.record()
        self.info["CFBundleVersion"] = "35"
        self.write_info()
        with self.assertRaisesRegex(contract_tool.ContractError, "Application metadata changed"):
            self.verify()

    def test_contract_changed_during_build_fails_before_provenance_write(self):
        self.contract["styleVersion"] = "different-approved-style"
        self.write_contract()
        with self.assertRaisesRegex(contract_tool.ContractError, "contract changed"):
            self.record()
        self.assertFalse((self.app / "Contents/Resources" / contract_tool.PROVENANCE_RESOURCE).exists())

    def test_malformed_context_and_sdk_settings_fail_with_contract_error(self):
        with self.assertRaisesRegex(contract_tool.ContractError, "provenance object"):
            contract_tool.validate_context([], self.contract_path, self.root)
        (self.sdk / "SDKSettings.json").write_text("[]")
        with self.assertRaisesRegex(contract_tool.ContractError, "SDK settings"):
            contract_tool.sdk_metadata(self.sdk)

    def test_source_authority_changed_during_build_fails(self):
        (self.root / self.contract["sourceAuthority"]["tokensAndComponents"]).write_text("new component")
        with self.assertRaisesRegex(contract_tool.ContractError, "source authority changed"):
            self.record()

    def test_bundled_contract_drift_is_rejected(self):
        self.record()
        (self.app / "Contents/Resources" / contract_tool.CONTRACT_RESOURCE).write_text("{}")
        with self.assertRaisesRegex(contract_tool.ContractError, "Bundled native design contract drift"):
            self.verify()

    def test_signature_identifier_must_match_bundle(self):
        self.record()
        self.signature_identifier = "local.other"
        with self.assertRaisesRegex(contract_tool.ContractError, "Signature/bundle identifier mismatch"):
            self.verify()

    def test_info_minimum_system_version_must_match(self):
        self.info["LSMinimumSystemVersion"] = "14.0"
        self.write_info()
        with self.assertRaisesRegex(contract_tool.ContractError, "Info.plist deployment drift"):
            self.record()

    def test_executable_sdk_drift_is_rejected_before_and_after_record(self):
        self.otool = macho(sdk="27.0")
        with self.assertRaisesRegex(contract_tool.ContractError, "Linked compatibility drift"):
            self.record()
        self.otool = macho()
        self.record()
        self.otool = macho(sdk="15.4")
        with self.assertRaisesRegex(contract_tool.ContractError, "Linked compatibility drift"):
            self.verify()

    def test_contract_cannot_duplicate_palette_or_omit_review_dimensions(self):
        original = copy.deepcopy(self.contract)
        self.contract["colors"] = {"accent": "red"}
        self.write_contract()
        with self.assertRaisesRegex(contract_tool.ContractError, "contract fields"):
            contract_tool.load_contract(self.contract_path)
        self.contract = original
        self.contract["requiredNativeReview"]["contrast"] = ["standard"]
        self.write_contract()
        with self.assertRaisesRegex(contract_tool.ContractError, "appearance dimensions"):
            contract_tool.load_contract(self.contract_path)


if __name__ == "__main__":
    unittest.main()
