"""Executable source-contract gate for named native families, not a Swift AST/pixel test.

The gate covers the inventoried Save/Create/Cancel and event-symbol consumers, the unchanged
native toolbar primitives, and the rejected addition-Undo/status contract. Other native control
families keep their own roles. Deliberate exceptions must be narrow and reviewed in the inventory.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
INVENTORY = "docs/qa/native-component-families-2026-10-28.json"
AUTHORITY = "Sources/CountdownManager/AuroraInstrument.swift"
PROMINENT = re.compile(r"\.buttonStyle\s*\(\s*\.borderedProminent\s*\)")
STRING_START = re.compile(r'(#+)?("""|")')
# Frozen from the actual AuroraInstrument enum in accepted baseline 14dc489. This covers named
# numeric/theme recipes and branches, not appended components or CFBundleVersion. Changing the
# golden requires explicit design-scope/StyleVersion review; a green digest is not user approval.
THEME_VERSION = "theme-v1"
THEME_RECIPE_SHA256 = "87308dc30a8f47d7863d6bd88c7dd7d57d522a4ad5b9ac39c0d766a93eaf5f3b"
# The current inventory has no direct prominent-style exception outside the primary authority.
# A future exception needs an exact source path and named declaration; no whole-directory waiver.
PROMINENT_EXCEPTIONS: dict[str, tuple[str, ...]] = {}
ACTION_CONTROLS = {
    "editor.save": ("Sources/CountdownManager/Views.swift", "primary-action", "auroraPrimaryAction"),
    "materials.text.create": ("Sources/CountdownManager/TextAttachmentView.swift", "primary-action", "auroraPrimaryAction"),
    "editor.cancel": ("Sources/CountdownManager/Views.swift", "secondary-action", "auroraSecondaryAction"),
    "materials.text.cancel": ("Sources/CountdownManager/TextAttachmentView.swift", "secondary-action", "auroraSecondaryAction"),
}


def code_mask(text: str, mask_strings: bool = True) -> str:
    """Keep code positions/newlines while masking comments and Swift string contents."""
    result = list(text)
    index = 0
    while index < len(text):
        start = index
        if text.startswith("//", index):
            index = text.find("\n", index)
            if index < 0:
                index = len(text)
        elif text.startswith("/*", index):
            depth = 1
            index += 2
            while index < len(text) and depth:
                if text.startswith("/*", index):
                    depth += 1
                    index += 2
                elif text.startswith("*/", index):
                    depth -= 1
                    index += 2
                else:
                    index += 1
        else:
            string = STRING_START.match(text, index)
            if string is None:
                index += 1
                continue
            hashes, quote = string.group(1) or "", string.group(2)
            end = quote + hashes
            index += len(string.group(0))
            while index < len(text):
                if not hashes and text[index] == "\\":
                    index += 2
                elif text.startswith(end, index):
                    index += len(end)
                    break
                else:
                    index += 1
            if not mask_strings:
                continue
        for position in range(start, min(index, len(text))):
            if result[position] != "\n":
                result[position] = " "
    return "".join(result)


def declaration(text: str, name: str) -> tuple[str, tuple[int, int]]:
    mask = code_mask(text)
    match = re.search(r"\b(?:struct|class|enum)\s+" + re.escape(name) + r"\b[^\{]*\{", mask)
    if match is None:
        raise ValueError("missing declaration " + name)
    begin, depth, index = match.end() - 1, 1, match.end()
    while index < len(mask) and depth:
        depth += (mask[index] == "{") - (mask[index] == "}")
        index += 1
    if depth:
        raise ValueError("unbalanced declaration " + name)
    return text[begin:index], (begin, index)


def theme_recipe_digest(text: str) -> str:
    body, _ = declaration(text, "AuroraInstrument")
    # The frozen enum uses numeric/color expressions, with no string-valued theme tokens.
    # Reject new string-valued recipes rather than silently masking their future contents.
    if '"' in code_mask(body, mask_strings=False):
        raise ValueError("theme recipe gained string-valued tokens; review the golden recipe format")
    normalized = re.sub(r"\s+", "", code_mask(body))
    return hashlib.sha256(normalized.encode()).hexdigest()


def control_chain(text: str, identifier: str, builders: str = "Button|AuroraSymbolAction",
                  prefix: bool = False) -> str:
    mask = code_mask(text)
    suffix = r'[^"\n]*' if prefix else ""
    pattern = r'\.accessibilityIdentifier\s*\(\s*"' + re.escape(identifier) + suffix + r'"'
    matches = [match for match in re.finditer(pattern, text)
               if mask[match.start():].startswith(".accessibilityIdentifier")]
    if len(matches) != 1:
        raise ValueError("expected one control " + identifier)
    target = matches[0].start()
    starts = list(re.finditer(r"\b(?:" + builders + r")\s*(?:\(|\{)", mask[:target]))
    if not starts:
        raise ValueError("missing native builder for " + identifier)
    return text[starts[-1].start():target]


def validate_sources(root: Path) -> list[str]:
    failures: list[str] = []
    inventory_path = root / INVENTORY
    try:
        inventory = json.loads(inventory_path.read_text())
        families = {family["id"]: family for family in inventory["families"]}
        if inventory["schema_version"] != 1:
            raise ValueError("unsupported inventory schema")
        sources = {path.relative_to(root).as_posix(): path.read_text()
                   for path in (root / "Sources/CountdownManager").rglob("*.swift") if not path.is_symlink()}
        authority = sources[AUTHORITY]
        primary, primary_span = declaration(authority, "AuroraPrimaryActionModifier")
        secondary, _ = declaration(authority, "AuroraSecondaryActionModifier")
        symbol, _ = declaration(authority, "AuroraSymbolAction")
        toolbar_style, _ = declaration(authority, "AuroraToolbarActionModifier")
        toolbar_label, _ = declaration(authority, "AuroraToolbarLabel")
        if theme_recipe_digest(authority) != THEME_RECIPE_SHA256:
            failures.append("frozen theme recipe drift: " + THEME_VERSION)
    except (OSError, ValueError, KeyError, TypeError) as error:
        return ["inventory/authority: " + str(error)]

    for identifier, (file, family_id, reuse) in ACTION_CONTROLS.items():
        try:
            consumers = families[family_id]["consumers"]
            if not any(entry.get("file") == file and entry.get("accessibility_id") == identifier
                       and entry.get("reuse") == reuse for entry in consumers):
                failures.append("inventory consumer missing: " + identifier)
            chain = control_chain(sources[file], identifier)
            shared = re.search(r"\." + reuse + r"\s*\(\s*\)", chain)
            if shared is None:
                failures.append("shared action family bypassed: " + identifier)
            elif re.search(r"\.(?:buttonStyle|controlSize|tint|foregroundStyle|font|background|overlay|border)\s*\(",
                           code_mask(chain[shared.end():])):
                failures.append("local action style fork: " + identifier)
        except (KeyError, ValueError) as error:
            failures.append(str(error))

    for name, body, style in (("primary", primary, "borderedProminent"), ("secondary", secondary, "bordered")):
        required = [r"\.buttonStyle\s*\(\s*\." + style + r"\s*\)",
                    r"\.controlSize\s*\(\s*\.large\s*\)", r"\.font\s*\(\s*\.system\s*\(\s*size:\s*12\s*\)",
                    r"\.tint\s*\(\s*AuroraInstrument\.accent", r"highContrast:\s*accessibilitySettings\.prefersHighContrast"]
        if not all(re.search(pattern, body) for pattern in required):
            failures.append("native action token contract drift: " + name)
        if re.search(r"\.(?:overlay|background|border)\s*\(", body):
            failures.append("invented action chrome: " + name)
        if any(len(re.findall(r"\." + method + r"\s*\(", code_mask(body))) != 1
               for method in ("buttonStyle", "controlSize", "tint", "font")):
            failures.append("duplicate/missing action token owner: " + name)

    if "AuroraInstrument.canvas" not in primary or ".white" not in primary:
        failures.append("primary foreground roles missing")
    if len(re.findall(r"\.foregroundStyle\s*\(", code_mask(primary))) != 1:
        failures.append("primary foreground has competing owners")
    if ".foregroundStyle" in secondary:
        failures.append("secondary native foreground overridden")

    for file, text in sources.items():
        mask = code_mask(text)
        allowed = [primary_span] if file == AUTHORITY else []
        for name in PROMINENT_EXCEPTIONS.get(file, ()):
            try:
                allowed.append(declaration(text, name)[1])
            except ValueError as error:
                failures.append(str(error))
        for match in PROMINENT.finditer(mask):
            if not any(start <= match.start() < end for start, end in allowed):
                failures.append("direct prominent style outside authority: " + file)
        if re.search(r"\b(?:MaterialAdditionReceipt|MaterialAdditionBanner|lastMaterialAddition|undoMaterialAddition|materialMessage)\b", mask):
            failures.append("addition undo/status state reintroduced: " + file)
        for match in re.finditer(r'\.(?:accessibilityIdentifier|uiSmokeControl)\s*\(\s*(?:id:\s*)?"materials\.(?:undo|status)"', text):
            if mask[match.start():].startswith("."):
                failures.append("addition undo/status UI reintroduced: " + file)

    required_symbol_parts = ["Image(systemName: symbolName)", ".frame(width: 28, height: 28)",
                             ".contentShape(Rectangle())", ".accessibilityLabel(accessibilityLabel)",
                             "button.buttonStyle(.borderless)", "button.buttonStyle(.plain)"]
    compact_symbol = re.sub(r"\s+", "", symbol)
    if not all(re.sub(r"\s+", "", part) in compact_symbol for part in required_symbol_parts) or re.search(r"\b(?:Path|Canvas|NSBezierPath)\s*\(", code_mask(symbol)):
        failures.append("native SF symbol authority drift")
    symbol_controls = [
        ("Sources/CountdownManager/Desktop/DesktopEventDetail.swift", "desktop.favorite.", "desktop", ["star.fill", "star"], "tone:presentation.isPrimary?.accent:.ink"),
        ("Sources/CountdownManager/Desktop/DesktopEventDetail.swift", "desktop.detail.edit", "desktop", ["pencil"], "tone:.ink"),
        ("Sources/CountdownManager/Desktop/DesktopEventDetail.swift", "desktop.detail.delete", "desktop", ["trash"], "tone:.ink"),
        ("Sources/CountdownManager/Views.swift", "event.primary.", "mini", ["star.fill", "star"], "tone:presentation.isPrimary?.accent:.secondary"),
        ("Sources/CountdownManager/Views.swift", "event.edit.", "mini", ["pencil"], "tone:.secondary"),
    ]
    for file, identifier, surface, names, tone in symbol_controls:
        try:
            chain = control_chain(sources[file], identifier, prefix=identifier.endswith("."))
            if not re.search(r"\bAuroraSymbolAction\s*\(", chain) or not re.search(r"surface:\s*\." + surface, chain) or not all('"' + name + '"' in chain for name in names):
                failures.append("native symbol family bypassed: " + identifier)
            if tone not in re.sub(r"\s+", "", chain) or re.search(r"\.(?:foregroundStyle|tint|buttonStyle|background|overlay)\s*\(", code_mask(chain)):
                failures.append("native symbol tone/style fork: " + identifier)
        except ValueError as error:
            failures.append(str(error))

    toolbar = "Sources/CountdownManager/Desktop/DesktopViews.swift"
    for identifier, builder, image in (("desktop.create", "Button", "plus"), ("desktop.create-day", "Menu", "calendar.badge.plus")):
        try:
            chain = control_chain(sources[toolbar], identifier, builders=builder)
            consumers = families["desktop-toolbar-creation"]["consumers"]
            if not any(entry.get("file") == toolbar and entry.get("accessibility_id") == identifier
                       and entry.get("reuse") == "auroraToolbarAction"
                       and entry.get("label_reuse") == "AuroraToolbarLabel"
                       and entry.get("shows_menu_indicator") == (builder == "Menu") for entry in consumers):
                failures.append("inventory consumer missing: " + identifier)
            if not re.search(r'systemImage:\s*"' + re.escape(image) + '"', chain):
                failures.append("native toolbar symbol changed: " + identifier)
            if not re.search(r"\.auroraToolbarAction\s*\(\s*\)", code_mask(chain)):
                failures.append("shared toolbar family bypassed: " + identifier)
            label_calls = list(re.finditer(r"\bAuroraToolbarLabel\s*\(", code_mask(chain)))
            expected_indicator = "true" if builder == "Menu" else "false"
            if len(label_calls) != 1 or not re.search(r"showsMenuIndicator:\s*" + expected_indicator + r"\b", code_mask(chain)):
                failures.append("shared toolbar label bypassed: " + identifier)
            if re.search(r"\.(?:tint|foregroundStyle|buttonStyle|background|overlay|border)\s*\(", code_mask(chain)):
                failures.append("local toolbar style fork: " + identifier)
            menus = list(re.finditer(r"\.menuStyle\s*\(\s*\.(\w+)\s*\)", code_mask(chain)))
            if builder == "Menu" and (len(menus) != 1 or menus[0].group(1) != "button"):
                failures.append("native toolbar menu must use button style: " + identifier)
            if builder == "Button" and menus:
                failures.append("event button gained menu styling")
            indicators = list(re.finditer(r"\.menuIndicator\s*\(\s*\.(\w+)\s*\)", code_mask(chain)))
            if builder == "Menu" and (len(indicators) != 1 or indicators[0].group(1) != "hidden"):
                failures.append("framework toolbar menu indicator must stay hidden: " + identifier)
            if builder == "Button" and indicators:
                failures.append("event button gained framework menu indicator styling")
            if re.search(r"\bprimaryAction\s*:", code_mask(chain)):
                failures.append("toolbar menu gained an unrelated primary action")
        except (KeyError, ValueError) as error:
            failures.append(str(error))
    toolbar_required = [r"\.buttonStyle\s*\(\s*\.bordered\s*\)",
                        r"\.controlSize\s*\(\s*\.regular\s*\)",
                        r"\.font\s*\(\s*\.system\s*\(\s*size:\s*13\s*\)",
                        r"\.foregroundStyle\s*\(\s*AuroraInstrument\.ink"]
    if not all(re.search(pattern, toolbar_style) for pattern in toolbar_required):
        failures.append("shared native toolbar token contract drift")
    if any(len(re.findall(r"\." + method + r"\s*\(", code_mask(toolbar_style))) != 1
           for method in ("buttonStyle", "controlSize", "font", "foregroundStyle")):
        failures.append("competing/missing native toolbar token owner")
    if re.search(r"\.(?:tint|background|overlay|border|frame)\s*\(|\b(?:Path|Canvas|NSBezierPath)\s*\(",
                 code_mask(toolbar_style)):
        failures.append("invented toolbar tint/chrome/geometry")
    label_required = [r"HStack\s*\(\s*spacing:\s*6\s*\)",
                      r"Label\s*\(\s*title,\s*systemImage:\s*systemImage\s*\)",
                      r"if\s+showsMenuIndicator\s*\{",
                      r'Image\s*\(\s*systemName:\s*"chevron\.down"\s*\)',
                      r"\.font\s*\(\s*\.system\s*\(\s*size:\s*9\s*\)",
                      r"\.accessibilityHidden\s*\(\s*true\s*\)"]
    if not all(re.search(pattern, toolbar_label) for pattern in label_required):
        failures.append("shared native toolbar label/chevron contract drift")
    if re.search(r"\.(?:tint|foregroundStyle|background|overlay|border|frame)\s*\(|\b(?:Path|Canvas|NSBezierPath)\s*\(",
                 code_mask(toolbar_label)):
        failures.append("invented toolbar label tint/chrome/drawing")
    return failures


class NativeDesignSystemChecks(unittest.TestCase):
    def fixture(self, directory: str) -> Path:
        root = Path(directory)
        shutil.copytree(ROOT / "Sources/CountdownManager", root / "Sources/CountdownManager")
        destination = root / INVENTORY
        destination.parent.mkdir(parents=True)
        shutil.copy2(ROOT / INVENTORY, destination)
        self.assertEqual(validate_sources(root), [], "mutation baseline must satisfy the contract")
        return root

    def test_current_sources_obey_named_native_families(self):
        self.assertEqual(validate_sources(ROOT), [])

    def test_replacing_create_shared_style_with_direct_style_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.fixture(directory)
            path = root / "Sources/CountdownManager/TextAttachmentView.swift"
            text = path.read_text()
            self.assertEqual(text.count(".auroraPrimaryAction()"), 1)
            path.write_text(text.replace(".auroraPrimaryAction()", ".buttonStyle(.borderedProminent)"))
            failures = validate_sources(root)
            self.assertTrue(any("shared action family bypassed: materials.text.create" in item for item in failures), failures)
            self.assertTrue(any("direct prominent style outside authority" in item for item in failures), failures)

    def test_toolbar_cannot_bypass_shared_family_or_revert_menu_to_automatic(self):
        for identifier, mutation in (("desktop.create", "shared"),
                                     ("desktop.create-day", "shared"),
                                     ("desktop.create-day", "menu"),
                                     ("desktop.create", "label"),
                                     ("desktop.create-day", "label"),
                                     ("desktop.create-day", "indicator")):
            with self.subTest(control=identifier, mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = self.fixture(directory)
                path = root / "Sources/CountdownManager/Desktop/DesktopViews.swift"
                text = path.read_text()
                builder = "Menu" if identifier.endswith("-day") else "Button"
                chain = control_chain(text, identifier, builders=builder)
                if mutation == "shared":
                    changed = chain.replace(".auroraToolbarAction()", ".buttonStyle(.bordered)", 1)
                    expected = "shared toolbar family bypassed: " + identifier
                elif mutation == "menu":
                    changed = chain.replace(".menuStyle(.button)", ".menuStyle(.automatic)", 1)
                    expected = "native toolbar menu must use button style: " + identifier
                elif mutation == "label":
                    image = "calendar.badge.plus" if builder == "Menu" else "plus"
                    changed = re.sub(r"AuroraToolbarLabel\s*\([^\n]*\)",
                                     'Label("Legacy", systemImage: "' + image + '")', chain, count=1)
                    expected = "shared toolbar label bypassed: " + identifier
                else:
                    changed = chain.replace(".menuIndicator(.hidden)", ".menuIndicator(.visible)", 1)
                    expected = "framework toolbar menu indicator must stay hidden: " + identifier
                self.assertNotEqual(changed, chain, "mutation must alter an actual consumer")
                path.write_text(text.replace(chain, changed, 1))
                self.assertIn(expected, validate_sources(root))

    def test_reintroducing_status_row_is_rejected_even_with_a_new_type_name(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.fixture(directory)
            path = root / "Sources/CountdownManager/MaterialIntake.swift"
            with path.open("a") as output:
                output.write('''\nstruct DifferentFeedbackName: View {
    var body: some View {
        HStack {
            Text("Added").accessibilityIdentifier("materials.status")
            Button("Undo") {}.accessibilityIdentifier("materials.undo")
        }
    }
}\n''')
            self.assertTrue(any("addition undo/status UI reintroduced" in item for item in validate_sources(root)))

    def test_replacing_shared_native_symbol_with_text_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.fixture(directory)
            path = root / AUTHORITY
            text = path.read_text()
            self.assertEqual(text.count("Image(systemName: symbolName)"), 1)
            path.write_text(text.replace("Image(systemName: symbolName)", 'Text("icon")'))
            self.assertIn("native SF symbol authority drift", validate_sources(root))

    def test_changing_an_actual_rgb_recipe_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.fixture(directory)
            path = root / AUTHORITY
            text = path.read_text()
            self.assertEqual(text.count("red: 0.718, green: 0.278, blue: 0.173"), 1)
            path.write_text(text.replace("red: 0.718, green: 0.278, blue: 0.173",
                                         "red: 0.700, green: 0.278, blue: 0.173"))
            self.assertIn("frozen theme recipe drift: theme-v1", validate_sources(root))

    def test_comments_and_string_examples_do_not_create_false_source_controls(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.fixture(directory)
            authority = root / AUTHORITY
            authority.write_text(authority.read_text().replace(
                "enum AuroraInstrument {", 'enum AuroraInstrument {\n/* theme comment "not a token" */\n', 1)
                + "\nprivate enum UnrelatedComponentScope { static let version = 99 }\n")
            path = root / "Sources/CountdownManager/MaterialIntake.swift"
            with path.open("a") as output:
                output.write('''\n// MaterialAdditionBanner .buttonStyle(.borderedProminent)
/* nested /* undoMaterialAddition */ comment */
private let sourceExample = #"Text(\"x\").accessibilityIdentifier(\"materials.status\")"#
''')
            self.assertEqual(validate_sources(root), [])


if __name__ == "__main__":
    unittest.main()
