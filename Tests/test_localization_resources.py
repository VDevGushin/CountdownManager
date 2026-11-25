import plistlib
import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources"
RESOURCES = SOURCE / "CountdownCore/Resources"
LANGUAGES = ("ru", "en")
LOOKUP = re.compile(r'\bAppText\.string\(\s*"([A-Za-z][\w.]*)"')
DECLARATION = re.compile(r'^"([^"]+)"\s*=', re.MULTILINE)
PLACEHOLDER = re.compile(r"%(?:[0-9]+\$@|%)")


def strings(path: Path) -> dict[str, str]:
    result = subprocess.run(
        ["/usr/bin/plutil", "-convert", "xml1", "-o", "-", str(path)],
        check=True, capture_output=True,
    )
    return plistlib.loads(result.stdout)


class LocalizationResources(unittest.TestCase):
    def test_each_catalog_contains_every_runtime_key_once_with_matching_placeholders(self):
        referenced = {
            key
            for source in SOURCE.rglob("*.swift")
            for key in LOOKUP.findall(source.read_text(encoding="utf-8"))
        }
        source = strings(RESOURCES / "ru.lproj/Localizable.strings")
        for language in LANGUAGES:
            with self.subTest(language=language):
                path = RESOURCES / f"{language}.lproj/Localizable.strings"
                translations = strings(path)
                self.assertCountEqual(DECLARATION.findall(path.read_text(encoding="utf-8")), translations.keys())
                self.assertEqual(referenced, set(translations))
                for key, text in translations.items():
                    self.assertIsInstance(text, str, key)
                    self.assertTrue(text.strip(), key)
                    self.assertNotIn("%", PLACEHOLDER.sub("", text), key)
                    self.assertCountEqual(PLACEHOLDER.findall(text), PLACEHOLDER.findall(source[key]), key)

    def test_location_purpose_strings_exist_for_both_plist_keys(self):
        for language in LANGUAGES:
            with self.subTest(language=language):
                purpose = strings(RESOURCES / f"{language}.lproj/InfoPlist.strings")
                self.assertEqual(set(purpose), {"NSLocationUsageDescription", "NSLocationWhenInUseUsageDescription"})
                self.assertTrue(all(isinstance(text, str) and text.strip() for text in purpose.values()))


if __name__ == "__main__":
    unittest.main()
