#!/usr/bin/env python3
"""Local Sparkle bundle/release tooling. Never publishes or accesses the Keychain."""
import argparse
import base64
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import quote, urlsplit
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PRODUCTION_ID = "local.countdownmanager.app"
TEST_ID = "local.countdownmanager.update-test"
TEST_MARKER = ".countdown-update-test-environment"


def fail(message):
    raise ValueError(message)


def run(arguments, *, capture=False, env=None):
    return subprocess.run([str(x) for x in arguments], check=True, env=env,
                          stdout=subprocess.PIPE if capture else None,
                          stderr=subprocess.PIPE if capture else None, text=True)


def read_plist(path):
    with Path(path).open("rb") as source:
        return plistlib.load(source)


def write_plist(path, data):
    with Path(path).open("wb") as destination:
        plistlib.dump(data, destination, sort_keys=False)


def public_key(value):
    try:
        decoded = base64.b64decode(value, validate=True)
    except (ValueError, TypeError):
        fail("Public Ed25519 key must be valid base64")
    if len(decoded) != 32 or decoded == bytes(32):
        fail("Public Ed25519 key must be a nonzero 32-byte key")
    return value


def feed_url(value, test=False):
    url = urlsplit(value)
    if url.username or url.password or url.fragment or not url.hostname:
        fail("Feed URL must have a host and no credentials or fragment")
    if url.scheme == "https":
        if url.hostname.endswith((".example", ".invalid", ".test")) or url.hostname == "example.com":
            fail("Placeholder feed hosts are forbidden")
        return value
    if test and url.scheme == "http" and url.hostname == "127.0.0.1":
        return value
    fail("Production feeds and downloads require HTTPS; tests permit loopback HTTP only")


def isolated_home(value):
    home = Path(value).expanduser().resolve()
    production = (Path.home() / "Library/Application Support/CountdownManager").resolve()
    if home == production or production in home.parents or home in production.parents:
        fail("Test home overlaps production Application Support")
    if not (home / TEST_MARKER).is_file():
        fail("Test home requires " + TEST_MARKER)
    return home


def configure(path, environment=None):
    env = os.environ if environment is None else environment
    data = read_plist(path)
    mode = env.get("COUNTDOWN_UPDATE_MODE", "disabled")
    if mode not in ("disabled", "release", "test"):
        fail("COUNTDOWN_UPDATE_MODE must be disabled, release or test")
    for name, field in (("COUNTDOWN_VERSION", "CFBundleShortVersionString"),
                        ("COUNTDOWN_BUILD_NUMBER", "CFBundleVersion")):
        value = env.get(name, data[field])
        if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value):
            fail(name + " must be a numeric version with at most three components")
        data[field] = value
    for key in ("SUFeedURL", "SUPublicEDKey", "CountdownUpdateTestMode", "CountdownUpdateTestHome",
                "SUDefaultsDomain", "NSAppTransportSecurity"):
        data.pop(key, None)
    data.update(SUEnableAutomaticChecks=True, SUAutomaticallyUpdate=False, SUAllowsAutomaticUpdates=False,
                SUEnableSystemProfiling=False, SUVerifyUpdateBeforeExtraction=True,
                SURequireSignedFeed=True, SUSignedFeedFailureExpirationInterval=0,
                SUScheduledCheckInterval=86400)
    if mode == "disabled":
        if data["CFBundleIdentifier"] != PRODUCTION_ID:
            fail("Disabled updater build must use the production bundle identifier")
        if env.get("COUNTDOWN_UPDATE_FEED_URL") or env.get("COUNTDOWN_UPDATE_PUBLIC_KEY"):
            fail("Set COUNTDOWN_UPDATE_MODE explicitly before configuring an update channel")
        data["SUEnableAutomaticChecks"] = False
    else:
        data["SUFeedURL"] = feed_url(env.get("COUNTDOWN_UPDATE_FEED_URL", ""), mode == "test")
        data["SUPublicEDKey"] = public_key(env.get("COUNTDOWN_UPDATE_PUBLIC_KEY", ""))
        if mode == "test":
            home = isolated_home(env.get("COUNTDOWN_MANAGER_TEST_HOME", ""))
            data.update(CFBundleIdentifier=TEST_ID, CountdownUpdateTestMode=True,
                        CountdownUpdateTestHome=str(home), SUDefaultsDomain=TEST_ID)
            if urlsplit(data["SUFeedURL"]).scheme == "http":
                # Scoped test-only transport exception. Production builds always use HTTPS.
                data["NSAppTransportSecurity"] = {"NSAllowsLocalNetworking": True}
        elif data["CFBundleIdentifier"] != PRODUCTION_ID:
            fail("Release bundle identifier must remain " + PRODUCTION_ID)
    write_plist(path, data)
    return data


def sparkle_distribution(build):
    candidates = list((Path(build) / "artifacts").glob("*/Sparkle"))
    candidates = [x for x in candidates if (x / "Sparkle.xcframework").is_dir()]
    if len(candidates) != 1:
        fail("Expected one resolved Sparkle SPM distribution in build artifacts")
    return candidates[0]


def embed(build, app):
    distribution = sparkle_distribution(build)
    frameworks = list((distribution / "Sparkle.xcframework").glob("macos-*/Sparkle.framework"))
    if len(frameworks) != 1:
        fail("Expected one macOS Sparkle.framework")
    target = Path(app) / "Contents/Frameworks/Sparkle.framework"
    run(["/usr/bin/ditto", frameworks[0], target])
    version = (target / "Versions/Current").resolve()
    for name in ("XPCServices/Installer.xpc", "XPCServices/Downloader.xpc", "Autoupdate", "Updater.app"):
        component = version / name
        if not component.exists():
            fail("Sparkle component missing: " + name)
        flags = ["--preserve-metadata=entitlements"] if name.endswith("Downloader.xpc") else []
        run(["/usr/bin/codesign", "--force", "--sign", "-", *flags, component])
    run(["/usr/bin/codesign", "--force", "--sign", "-", target])
    run(["/usr/bin/codesign", "--force", "--sign", "-", app])
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", app])
    if not (target / "Versions/Current").is_symlink() or not (target / "Sparkle").is_symlink():
        fail("Sparkle versioned framework symlinks were not preserved")


def install_built_bundle(source, destination):
    source = Path(source).resolve()
    destination = Path(destination).expanduser().absolute()
    resolved = destination.resolve()
    if resolved == Path("/Applications") or Path("/Applications") in resolved.parents:
        fail("build.sh cannot install into /Applications")
    if destination.suffix != ".app" or destination.is_symlink():
        fail("Build output must be a regular .app path")
    if destination.exists():
        old = read_plist(destination / "Contents/Info.plist")
        new = read_plist(source / "Contents/Info.plist")
        if old.get("CFBundleIdentifier") != new.get("CFBundleIdentifier"):
            fail("Refusing to replace a bundle with a different identifier")
        shutil.rmtree(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    run(["/usr/bin/ditto", source, destination])
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", destination])


def validate_private_file(path):
    path = Path(path).expanduser().resolve()
    if path == ROOT or ROOT in path.parents:
        fail("Private signing keys must be stored outside the repository")
    if not path.is_file() or path.stat().st_mode & 0o077:
        fail("Private signing key must exist and have permissions 0600 or stricter")
    return path


def key_public(private):
    # CryptoKit accepts the same 32-byte private seed format as current Sparkle tools.
    # The secret is read from its protected file, never placed in argv or output.
    source = '''import Foundation
import CryptoKit
let text = try String(contentsOfFile: CommandLine.arguments.last!, encoding: .utf8)
guard let seed = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)), seed.count == 32 else {
    throw NSError(domain: "CountdownRelease", code: 1)
}
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
print(key.publicKey.rawRepresentation.base64EncodedString())
'''
    with tempfile.TemporaryDirectory(prefix="countdown-key-tool.", dir="/private/tmp") as cache:
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = cache
        return run(["/usr/bin/swift", "-module-cache-path", cache, "-e", source, private],
                   capture=True, env=environment).stdout.strip()


def release(args):
    app = Path(args.app).resolve()
    info = read_plist(app / "Contents/Info.plist")
    test = info.get("CountdownUpdateTestMode") is True
    if test != args.test:
        fail("Test bundles require --test; production releases forbid it")
    if info.get("CFBundleIdentifier") != (TEST_ID if test else PRODUCTION_ID):
        fail("Release bundle identifier does not match the selected channel")
    if not info.get("SURequireSignedFeed") or not info.get("SUVerifyUpdateBeforeExtraction"):
        fail("Bundle must require signed feeds and archive verification before extraction")
    feed_url(info.get("SUFeedURL", ""), test)
    public_key(info.get("SUPublicEDKey", ""))
    download = feed_url(args.download_url_prefix, test)
    if not download.endswith("/"):
        fail("Download URL prefix must end in /")
    private = validate_private_file(args.private_key)
    if key_public(private) != info["SUPublicEDKey"]:
        fail("Private signing key does not match the public key embedded in the app")
    tools = sparkle_distribution(args.build_dir) / "bin"
    output = Path(args.output).expanduser().resolve()
    if output == ROOT or ROOT in output.parents:
        fail("Release output must be outside the source repository")
    if output.exists() and any(output.iterdir()):
        fail("Use a fresh empty release output directory")
    output.mkdir(parents=True, exist_ok=True)
    archive = output / ("CountdownManager-" + info["CFBundleShortVersionString"] + "-" + info["CFBundleVersion"] + ".zip")
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", app])
    run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, archive])
    # A mismatched key must fail before emitting a feed for distribution.
    signature = run([tools / "sign_update", "--ed-key-file", private, archive], capture=True)
    match = re.search(r'sparkle:edSignature="([^"]+)"', signature.stdout)
    if not match:
        fail("Sparkle sign_update did not produce an Ed25519 signature")
    run([tools / "sign_update", "--verify", "--ed-key-file", private, archive, match[1]], capture=True)
    # generate_appcast validates the signing key against the embedded public key and signs the feed.
    run([tools / "generate_appcast", "--ed-key-file", private, "--download-url-prefix", download,
         "--maximum-deltas", "0", output], capture=True)
    feed = output / Path(urlsplit(info["SUFeedURL"]).path).name
    if not feed.is_file():
        fail("Sparkle did not generate the configured appcast")
    run([tools / "sign_update", "--verify", "--ed-key-file", private, feed], capture=True)
    namespace = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    items = ET.parse(feed).findall("channel/item")
    matching = [item for item in items if item.findtext(namespace + "version") == info["CFBundleVersion"]]
    if len(matching) != 1:
        fail("Generated feed must contain exactly one item for this build")
    enclosure = matching[0].find("enclosure")
    if enclosure is None or enclosure.get("url") != download + quote(archive.name):
        fail("Generated feed archive URL does not match the release output")
    if enclosure.get(namespace + "edSignature") != match[1] or enclosure.get("length") != str(archive.stat().st_size):
        fail("Generated feed archive signature or byte length does not match the release output")
    manifest = {"app": str(app), "archive": str(archive), "feed": str(feed),
                "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
                "test_only": test, "published": False}
    (output / "release-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("configure").add_argument("plist")
    embed_parser = commands.add_parser("embed")
    embed_parser.add_argument("build_dir")
    embed_parser.add_argument("app")
    install_parser = commands.add_parser("install-built-bundle")
    install_parser.add_argument("source")
    install_parser.add_argument("destination")
    release_parser = commands.add_parser("release")
    release_parser.add_argument("--app", required=True)
    release_parser.add_argument("--build-dir", default=str(ROOT / ".build"))
    release_parser.add_argument("--private-key", required=True)
    release_parser.add_argument("--download-url-prefix", required=True)
    release_parser.add_argument("--output", required=True)
    release_parser.add_argument("--test", action="store_true")
    args = parser.parse_args()
    try:
        if args.command == "configure":
            configure(args.plist)
        elif args.command == "embed":
            embed(args.build_dir, args.app)
        elif args.command == "install-built-bundle":
            install_built_bundle(args.source, args.destination)
        elif args.command == "release":
            release(args)
    except (ValueError, OSError, subprocess.CalledProcessError, ET.ParseError) as error:
        # Tool stderr can contain private key material; do not relay captured output.
        print("Update tooling failed: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
