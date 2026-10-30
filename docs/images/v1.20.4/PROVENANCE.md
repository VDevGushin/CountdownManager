# 1.20.4/40 native and package evidence

The production-configured release executable is
`898b9f84be02e93807f2a4ae8bf2a36f2bab77a2464c162f84cd227e88ec5ce3`.
It was built from clean main at `e6bfc4fe71dce45195f6624e7b64617adb42470c` through build.sh,
headers SDK 15.4, linked compatibility 13.0, the existing production feed and public key.
[Source input freeze](source-freeze.json) records every application/build input. Subsequent evidence
and homepage commits do not change those inputs. No reconfiguration or re-signing follows capture.

- [Desktop result](verification-desktop.txt): **31/31**. The runtime generated 131 images;
  [desktop receipt](native-desktop.json) identifies the three retained README images.
- [Materials result](verification-materials.txt): **1/1**, with desktop/mini/editor/text-composer
  Light/Dark and Increase Contrast captures in the [16-image manifest](materials/manifest.json).
- [Release-help result](verification-help.txt): **1/1**; [four-image manifest](help/manifest.json).
- [Exact-package Finder result](finder-exact.json): **1/1**, actual PNG drag onto an unselected
  event, original name/bytes/source, and persistence across restart. The repository Xcode project
  built normally after registering its existing missing source. A temporary xctestrun points the
  UI target at this exact production bundle; [execution log](verification-finder.txt).
- [Strict lint](verification-lint.txt), [CoreChecks/UIChecks](verification-fast.txt), and
  [public-key package audit](artifact-audit.json) are retained separately.

The three README images and release help were opened and inspected. Images are native in-process
renders on isolated synthetic data, including an injected civil date in the retention scenario;
they are not compositor captures or evidence of every external gesture. The homepage shows a
small current gallery; historical 1.20.3 images remain under their original version.

[Feature acceptance](feature-acceptance.json) records the owner's real floating screenshot-thumbnail
test: eight PNGs across two isolated events, with valid structure/CRCs, dimensions and metadata sizes,
and no remaining import staging. That earlier tester preceded the release-version/help change;
its different executable hash is explicit. Its screenshots contain no published user content here.
The automated screenshot-thumbnail probe stopped before dragging because the system thumbnail had
no accessible window; it is not counted as a failed import or a passing automated drop.

Mini/editor thumbnail targets were not individually observed in external manual acceptance.
VoiceOver, older-macOS runtime coverage, arbitrary Mail/Photos promises and a genuine public-version
Sparkle installation were not newly exercised. The owner performs the final installed-version update.

[Publication](publication.json) and [anonymous delivery](public-consistency.json) verify the public
release, stable feed and current default-branch homepage. [Local handoff](local-handoff.json) leaves
1.20.3/39 installed and running for the owner; [cleanup](cleanup.json) records recoverable task-only
Trash moves and preserved production bytes. Temporary preparation paths describe their original
locations; published assets are canonical and the restore manifest preserves local recovery.
