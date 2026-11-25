import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import check_release


class ReleaseChecks(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='countdown-release-check-')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        subprocess.run(['git', 'init', '--quiet', str(self.root)], check=True)
        self.write('Resources/Info.plist', plistlib.dumps({'CFBundleShortVersionString': '9.2.1', 'CFBundleVersion': '42'}))
        self.write('Sources/CountdownManager/WhatsNew.swift', 'static let releaseID = "9.2.1"')
        self.write('docs/images/v9.2.1/current.png', b'image-fixture')
        self.readme = '# Project\n\n9.2.1\n<img src="docs/images/v9.2.1/current.png">\n'
        self.write('README.md', self.readme)

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content if isinstance(content, bytes) else content.encode())

    def test_current_fixture_and_code_examples(self):
        self.write('README.md', self.readme + '\n```sh\n[not a doc link](not-installed.md)\n```\n')
        self.assertEqual(check_release.local_check(self.root)['errors'], [])

    def test_old_homepage_image_is_rejected_even_when_present(self):
        self.write('docs/images/v9.1.0/old.png', b'old')
        self.write('README.md', self.readme.replace('v9.2.1/current.png', 'v9.1.0/old.png'))
        self.assertTrue(any('not from v9.2.1' in error for error in check_release.local_check(self.root)['errors']))

    def test_native_release_help_mismatch_is_rejected(self):
        self.write('Sources/CountdownManager/WhatsNew.swift', 'static let releaseID = "9.1.0"')
        self.assertTrue(any('release-help ID' in error for error in check_release.local_check(self.root)['errors']))

    def test_broken_local_reference_is_rejected(self):
        self.write('README.md', self.readme + '\n[missing](docs/missing.md)\n')
        self.assertTrue(any('docs/missing.md' in error for error in check_release.local_check(self.root)['errors']))

    def public_downloads(self):
        archive, feed = b'archive', b'feed'
        self.write('docs/images/v9.2.1/artifact-audit.json', json.dumps({
            'archiveSHA256': hashlib.sha256(archive).hexdigest(),
            'feedSHA256': hashlib.sha256(feed).hexdigest()}))
        base = 'https://github.com/MonolitST/CountdownManager'
        stable = '/releases/latest/download/appcast.xml'
        versioned = '/releases/download/v9.2.1/'
        archive_path = versioned + 'CountdownManager-9.2.1-42.zip'
        return {
            base + '/releases/latest': (200, base + '/releases/tag/v9.2.1', b'latest'),
            base + archive_path: (200, '', archive),
            base + versioned + 'appcast.xml': (200, '', feed),
            base + stable: (200, '', feed),
            'https://raw.githubusercontent.com/MonolitST/CountdownManager/HEAD/README.md':
                (200, '', self.readme.encode()),
        }

    def run_public_check(self, downloads):
        report = check_release.local_check(self.root)
        with patch.object(check_release, 'download', side_effect=downloads.__getitem__):
            check_release.public_check(self.root, report)
        return report

    def test_organization_release_and_assets_are_checked(self):
        report = self.run_public_check(self.public_downloads())
        self.assertEqual(report['errors'], [])
        self.assertEqual(set(report['publicChecks']), {'latest', 'archive', 'versionFeed', 'stableFeed'})

    def test_wrong_default_branch_readme_is_rejected(self):
        downloads = self.public_downloads()
        downloads['https://raw.githubusercontent.com/MonolitST/CountdownManager/HEAD/README.md'] = (
            200, '', b'stale homepage')
        self.assertEqual(self.run_public_check(downloads)['errors'], [
            'GitHub default-branch README differs from local current README',
        ])


if __name__ == '__main__':
    unittest.main()
