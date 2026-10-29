#!/usr/bin/env python3
"""Validate the native build contract; metadata checks do not certify rendered UI."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONTRACT = ROOT / "Resources/NativeDesignContract.json"
CONTRACT_RESOURCE = "NativeDesignContract.json"
PROVENANCE_RESOURCE = "NativeBuildProvenance.json"
VERSION = re.compile(r"[0-9]+(?:\.[0-9]+){0,2}")


class ContractError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ContractError(message)


def read_json(path):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError) as error:
        raise ContractError(f"Cannot read {path}: {error}") from error


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def version(value):
    require(isinstance(value, str) and VERSION.fullmatch(value), f"Invalid version: {value!r}")
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * (3 - len(parts))


def load_contract(path):
    contract = read_json(path)
    keys = {"schemaVersion", "styleVersion", "deploymentTarget", "nativeLinkedCompatibility",
            "sourceAuthority", "requiredNativeReview"}
    require(isinstance(contract, dict) and set(contract) == keys, "Invalid native contract fields")
    require(type(contract["schemaVersion"]) is int and contract["schemaVersion"] == 1, "Unsupported native contract schema")
    require(isinstance(contract["styleVersion"], str) and contract["styleVersion"].strip(), "Missing styleVersion")
    require(version(contract["nativeLinkedCompatibility"]) >= version(contract["deploymentTarget"]),
            "Linked compatibility cannot precede deployment target")
    authorities = contract["sourceAuthority"]
    require(isinstance(authorities, dict) and set(authorities) == {"behavior", "visual", "tokensAndComponents"},
            "Invalid source authority fields")
    for path_value in authorities.values():
        require(isinstance(path_value, str) and path_value and not Path(path_value).is_absolute()
                and ".." not in Path(path_value).parts, "Source authority must be project-relative")
    review = contract["requiredNativeReview"]
    require(review == {"themes": ["light", "dark"], "contrast": ["standard", "increased"],
                       "surfaces": ["desktop", "mini-panel", "editor", "text-composer"]},
            "Native review must retain all required appearance dimensions")
    return contract


def linker_flags(contract):
    return ["-Xlinker", "-platform_version", "-Xlinker", "macos", "-Xlinker", contract["deploymentTarget"],
            "-Xlinker", contract["nativeLinkedCompatibility"]]


def run_command(arguments):
    result = subprocess.run(arguments, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    require(result.returncode == 0, "Command failed: " + " ".join(map(str, arguments)) + "\n" + result.stderr.strip())
    return result.stdout + result.stderr


def sdk_metadata(path):
    sdk = Path(path).resolve()
    require(sdk.is_dir() and Path(path).is_absolute(), "Compiler SDK must be an existing absolute directory")
    settings = sdk / "SDKSettings.json"
    if settings.exists():
        data = read_json(settings)
    else:
        try:
            data = plistlib.loads((sdk / "SDKSettings.plist").read_bytes())
        except (OSError, ValueError, plistlib.InvalidFileException) as error:
            raise ContractError(f"Cannot read actual compiler SDK metadata: {sdk}") from error
    require(isinstance(data, dict), "Invalid compiler SDK settings")
    version(data.get("Version"))
    require(str(data.get("CanonicalName", "")).startswith("macosx"), "Compiler SDK is not macOS")
    return {"path": str(sdk), "version": data["Version"], "canonicalName": data["CanonicalName"]}


def authority_hashes(contract, project_root):
    root = Path(project_root).resolve()
    hashes = {}
    for name in contract["sourceAuthority"].values():
        path = (root / name).resolve()
        require(root in path.parents and path.is_file(), f"Missing or outside source authority: {name}")
        hashes[name] = digest(path)
    return hashes


def parse_otool(output):
    """Parse every architecture's main-executable build command, including older load commands."""
    records = []
    architecture = "thin"
    current = None
    for line in output.splitlines():
        arch = re.search(r"\(architecture ([^)]+)\):", line)
        if arch:
            architecture = arch.group(1)
        command = re.match(r"\s*cmd (LC_[A-Z0-9_]+)\s*$", line)
        if command:
            current = None
            if command.group(1) in ("LC_BUILD_VERSION", "LC_VERSION_MIN_MACOSX"):
                current = {"architecture": architecture, "command": command.group(1)}
                if command.group(1) == "LC_VERSION_MIN_MACOSX":
                    current["platform"] = "1"
                records.append(current)
            continue
        if current is not None:
            field = re.match(r"\s*(platform|minos|version|sdk)\s+(\S+)", line)
            if field:
                key, value = field.groups()
                if key == "version" and current["command"] == "LC_VERSION_MIN_MACOSX":
                    key = "minos"
                if key != "version":
                    current[key] = value
    require(records, "No native deployment/SDK metadata found")
    require(all(all(key in item for key in ("minos", "sdk", "platform")) for item in records),
            "Incomplete Mach-O build metadata")
    return records


def validate_linked_metadata(records, contract):
    for record in records:
        require(record["platform"] in ("1", "MACOS", "macos"), "Executable platform is not macOS")
        require(version(record["minos"]) == version(contract["deploymentTarget"]),
                f"Deployment target drift: {record['minos']} != {contract['deploymentTarget']}")
        require(version(record["sdk"]) == version(contract["nativeLinkedCompatibility"]),
                f"Linked compatibility drift: {record['sdk']} != {contract['nativeLinkedCompatibility']}")


def app_metadata(app):
    app = Path(app)
    try:
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        raise ContractError("Cannot read application Info.plist") from error
    executable = info.get("CFBundleExecutable")
    require(isinstance(executable, str) and executable and Path(executable).name == executable,
            "Invalid CFBundleExecutable")
    require(isinstance(info.get("CFBundleIdentifier"), str) and info["CFBundleIdentifier"], "Missing bundle identifier")
    binary = app / "Contents/MacOS" / executable
    require(binary.is_file(), "Application executable is missing")
    return info, binary


def snapshot_build(contract_path, sdk, swift, project_root=ROOT, command=run_command):
    contract = load_contract(contract_path)
    require(Path(swift).is_absolute() and Path(swift).is_file(), "Swift toolchain must be an existing absolute path")
    return {"schemaVersion": 1, "styleVersion": contract["styleVersion"], "contractSHA256": digest(contract_path),
            "sourceAuthoritySHA256": authority_hashes(contract, project_root), "compilerSDK": sdk_metadata(sdk),
            "swiftToolchain": {"executable": str(Path(swift).resolve()), "version": command([str(swift), "--version"]).strip()},
            "linkedCompatibility": contract["nativeLinkedCompatibility"], "deploymentTarget": contract["deploymentTarget"],
            "createdAtUTC": datetime.now(timezone.utc).isoformat()}


def validate_context(context, contract_path, project_root=ROOT):
    contract = load_contract(contract_path)
    require(isinstance(context, dict), "Invalid build provenance object")
    require(context.get("schemaVersion") == 1, "Invalid build provenance schema")
    require(context.get("contractSHA256") == digest(contract_path), "Native design contract changed during/after build")
    require(context.get("styleVersion") == contract["styleVersion"], "styleVersion drift")
    require(context.get("sourceAuthoritySHA256") == authority_hashes(contract, project_root),
            "Native design source authority changed during/after build")
    require(context.get("linkedCompatibility") == contract["nativeLinkedCompatibility"]
            and context.get("deploymentTarget") == contract["deploymentTarget"], "Provenance compatibility drift")
    recorded_sdk = context.get("compilerSDK", {})
    require(recorded_sdk == sdk_metadata(recorded_sdk.get("path", "")), "Compiler SDK provenance is not truthful")
    require(isinstance(context.get("swiftToolchain", {}).get("version"), str)
            and context["swiftToolchain"]["version"], "Missing Swift toolchain provenance")
    return contract


def record_build(app, contract_path, context_path, project_root=ROOT, command=run_command):
    context = read_json(context_path)
    contract = validate_context(context, contract_path, project_root)
    info, binary = app_metadata(app)
    require(version(info.get("LSMinimumSystemVersion")) == version(contract["deploymentTarget"]), "Info.plist deployment drift")
    linked = parse_otool(command(["/usr/bin/otool", "-l", str(binary)]))
    validate_linked_metadata(linked, contract)
    provenance = dict(context)
    provenance.update(application={"identifier": info["CFBundleIdentifier"], "version": info.get("CFBundleShortVersionString"),
                                   "build": info.get("CFBundleVersion"), "executable": info["CFBundleExecutable"]},
                      linkedMachO=linked, renderedAppearanceVerified=False)
    resources = Path(app) / "Contents/Resources"
    resources.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(contract_path, resources / CONTRACT_RESOURCE)
    (resources / PROVENANCE_RESOURCE).write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + "\n")
    return provenance


def verify_build(app, contract_path, project_root=ROOT, command=run_command):
    resources = Path(app) / "Contents/Resources"
    provenance = read_json(resources / PROVENANCE_RESOURCE)
    contract = validate_context(provenance, contract_path, project_root)
    require(digest(resources / CONTRACT_RESOURCE) == digest(contract_path), "Bundled native design contract drift")
    info, binary = app_metadata(app)
    expected_app = {"identifier": info["CFBundleIdentifier"], "version": info.get("CFBundleShortVersionString"),
                    "build": info.get("CFBundleVersion"), "executable": info["CFBundleExecutable"]}
    require(provenance.get("application") == expected_app, "Application metadata changed after provenance recording")
    require(version(info.get("LSMinimumSystemVersion")) == version(contract["deploymentTarget"]), "Info.plist deployment drift")
    linked = parse_otool(command(["/usr/bin/otool", "-l", str(binary)]))
    validate_linked_metadata(linked, contract)
    require(linked == provenance.get("linkedMachO"), "Executable build metadata changed after recording")
    command(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)])
    signature = command(["/usr/bin/codesign", "--display", "--verbose=4", str(app)])
    identifier = re.search(r"^Identifier=(.+)$", signature, re.MULTILINE)
    require(identifier is not None and identifier.group(1) == info["CFBundleIdentifier"], "Signature/bundle identifier mismatch")
    return {"styleVersion": contract["styleVersion"], "compilerSDK": provenance["compilerSDK"],
            "linkedCompatibility": contract["nativeLinkedCompatibility"], "signatureIdentifier": identifier.group(1),
            "renderedAppearanceVerified": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", type=Path, default=DEFAULT_CONTRACT)
    commands = parser.add_subparsers(dest="mode", required=True)
    commands.add_parser("linker-flags")
    snapshot = commands.add_parser("snapshot")
    snapshot.add_argument("--compiler-sdk", required=True)
    snapshot.add_argument("--swift", required=True)
    snapshot.add_argument("--output", type=Path, required=True)
    record = commands.add_parser("record")
    record.add_argument("--app", type=Path, required=True)
    record.add_argument("--context", type=Path, required=True)
    verify = commands.add_parser("verify")
    verify.add_argument("--app", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.mode == "linker-flags":
            print(" ".join(linker_flags(load_contract(args.contract))))
        elif args.mode == "snapshot":
            value = snapshot_build(args.contract, args.compiler_sdk, args.swift)
            args.output.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
        elif args.mode == "record":
            record_build(args.app, args.contract, args.context)
        else:
            print(json.dumps(verify_build(args.app, args.contract), ensure_ascii=False, indent=2))
    except (ContractError, OSError) as error:
        print("Native design/build contract failed: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
