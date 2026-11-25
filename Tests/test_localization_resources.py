import plistlib
import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources"
RUSSIAN = SOURCE / "CountdownCore/Resources/ru.lproj"
LOOKUP = re.compile(r'\bAppText\.string\(\s*"([A-Za-z][\w.]*)"')
DECLARATION = re.compile(r'^"([^"]+)"\s*=', re.MULTILINE)


def strings(path: Path) -> dict[str, str]:
    result = subprocess.run(
        ["/usr/bin/plutil", "-convert", "xml1", "-o", "-", str(path)],
        check=True, capture_output=True,
    )
    return plistlib.loads(result.stdout)


class LocalizationResources(unittest.TestCase):
    def test_every_runtime_key_has_one_nonempty_source_value(self):
        path = RUSSIAN / "Localizable.strings"
        translations = strings(path)
        declared = DECLARATION.findall(path.read_text(encoding="utf-8"))
        referenced = {
            key
            for source in SOURCE.rglob("*.swift")
            for key in LOOKUP.findall(source.read_text(encoding="utf-8"))
        }
        self.assertEqual(len(declared), len(translations), "Duplicate or unrecognized resource key")
        self.assertEqual(referenced, set(translations))
        self.assertTrue(all(isinstance(value, str) and value.strip() for value in translations.values()))

    def test_location_purpose_strings_exist_for_both_plist_keys(self):
        purpose = strings(RUSSIAN / "InfoPlist.strings")
        for key in ["NSLocationUsageDescription", "NSLocationWhenInUseUsageDescription"]:
            self.assertTrue(purpose[key].strip())


if __name__ == "__main__":
    unittest.main()
