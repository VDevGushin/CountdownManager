"""Exercise the real SwiftLint gate against the duplicate native-field outline regression."""
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class NativeFieldChromeChecks(unittest.TestCase):
    def lint(self, field):
        with tempfile.TemporaryDirectory(prefix="countdown-native-field-") as directory:
            root = Path(directory)
            (root / "Sources").mkdir()
            shutil.copy2(ROOT / ".swiftlint.yml", root / ".swiftlint.yml")
            (root / "Sources/Fixture.swift").write_text(
                'import SwiftUI\nstruct Fixture: View {\n    var body: some View {\n'
                + field + '\n    }\n}\n'
            )
            result = subprocess.run(
                ["swiftlint", "lint", "--config", str(root / ".swiftlint.yml"),
                 "--strict", "--no-cache", "--quiet"],
                cwd=root, capture_output=True, text=True, check=False,
            )
            return result.returncode, result.stdout + result.stderr

    def test_native_field_and_native_focus_are_allowed(self):
        status, output = self.lint(
            '        TextField("Title", text: .constant(""))\n'
            '            .textFieldStyle(.roundedBorder)\n'
            '            .accessibilityIdentifier("title")'
        )
        self.assertEqual(status, 0, output)

    def test_native_field_rejects_second_outline(self):
        for modifier in (
            '.auroraInputChrome(isFocused: false)',
            '.border(Color.red)',
            '.overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.red))',
            '.overlay { RoundedRectangle(cornerRadius: 4).stroke(Color.red) }',
        ):
            with self.subTest(modifier=modifier):
                status, output = self.lint(
                    '        TextField("Title", text: .constant(""))\n'
                    '            .textFieldStyle(.roundedBorder)\n'
                    '            .frame(minHeight: 28)\n'
                    '            ' + modifier
                )
                self.assertNotEqual(status, 0, output)
                self.assertIn("native_field_custom_outline", output)

    def test_independent_selection_control_keeps_its_border(self):
        status, output = self.lint(
            '        Button("Icon", action: {})\n'
            '            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.red))'
        )
        self.assertEqual(status, 0, output)

    def test_container_border_does_not_belong_to_native_field(self):
        status, output = self.lint(
            '        VStack {\n'
            '            TextField("Title", text: .constant(""))\n'
            '                .textFieldStyle(.roundedBorder)\n'
            '        }\n'
            '        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.red))'
        )
        self.assertEqual(status, 0, output)


if __name__ == "__main__":
    unittest.main()
