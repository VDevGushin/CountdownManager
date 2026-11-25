#!/usr/bin/env python3
"""Read-only release consistency checks; --output writes only the requested JSON receipt."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
from urllib.parse import unquote
from urllib.request import Request, urlopen

REPOSITORY = 'MonolitST/CountdownManager'


def local_check(root):
    errors = []
    info = plistlib.loads((root / 'Resources/Info.plist').read_bytes())
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    readme = (root / 'README.md').read_text()
    source = (root / 'Sources/CountdownManager/WhatsNew.swift').read_text()
    match = re.search(r'static let releaseID = "([^"]+)"', source)
    if not match or match[1] != version:
        errors.append('Native release-help ID differs from Info.plist')
    if version not in '\n'.join(readme.splitlines()[:20]):
        errors.append('README opening does not identify the candidate version')
    images = re.findall(r'<img\s+src="([^"]+)"', readme)
    if not images:
        errors.append('README has no native application images')
    for image in images:
        if not image.startswith(f'docs/images/v{version}/'):
            errors.append(f'Homepage image is not from v{version}: {image}')
        path = root / image
        if not path.is_file() or not path.stat().st_size:
            errors.append(f'Homepage image is missing or empty: {image}')
    command = ['git', '-C', str(root), 'ls-files', '-co', '--exclude-standard', '-z']
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode:
        raise ValueError('Root must be a Git worktree; ignored eval snapshots are not project docs')
    names = sorted(set(filter(None, result.stdout.split('\0'))))
    references, documents = 0, 0
    for name in names:
        path = root / name
        if path.suffix != '.md' or not path.is_file():
            continue
        documents += 1
        text = re.sub(r'```.*?```', '', path.read_text(), flags=re.S)
        links = re.findall(r'\]\(([^\s)]+)(?:\s+[^)]*)?\)', text)
        links += re.findall(r'(?:src|href)="([^"]+)"', text)
        for link in links:
            if link.startswith(('#', 'http:', 'https:', 'mailto:', 'plugin:', 'skill:', 'codex:', 'data:')):
                continue
            target = unquote(link.split('#', 1)[0].strip('<>'))
            if not target or '<' in target or '>' in target:
                continue
            references += 1
            resolved = Path(target) if target.startswith('/') else path.parent / target
            if not resolved.exists():
                errors.append(f'Missing local reference: {name} -> {link}')
    return {'version': version, 'build': build, 'documents': documents,
            'localReferences': references, 'homepageImages': len(images), 'errors': errors}


def download(url):
    request = Request(url, headers={'User-Agent': 'CountdownManager-release-check',
                                    'Cache-Control': 'no-cache'})
    with urlopen(request, timeout=35) as response:
        return response.status, response.url, response.read()


def public_check(root, report):
    version, build = report['version'], report['build']
    base = f'https://github.com/{REPOSITORY}'
    version_path = f'/releases/download/v{version}'
    archive_path = f'{version_path}/CountdownManager-{version}-{build}.zip'
    stable_path = '/releases/latest/download/appcast.xml'
    audit = json.loads((root / f'docs/images/v{version}/artifact-audit.json').read_text())
    urls = {'latest': (base + '/releases/latest', None),
            'archive': (base + archive_path, audit['archiveSHA256']),
            'versionFeed': (f'{base}{version_path}/appcast.xml', audit['feedSHA256']),
            'stableFeed': (base + stable_path, audit['feedSHA256'])}
    checks = {}
    for name, (url, expected) in urls.items():
        status, resolved, data = download(url)
        digest = hashlib.sha256(data).hexdigest()
        if status != 200 or (name == 'latest' and resolved != base + f'/releases/tag/v{version}'):
            report['errors'].append(f'Unexpected public response: {name}')
        elif expected is not None and digest != expected:
            report['errors'].append(f'Public payload differs from audited bytes: {name}')
        checks[name] = {'status': status, 'sha256': digest, 'bytes': len(data)}
    readme_url = f'https://raw.githubusercontent.com/{REPOSITORY}/HEAD/README.md'
    _, _, readme = download(readme_url)
    if readme != (root / 'README.md').read_bytes():
        report['errors'].append('GitHub default-branch README differs from local current README')
    report['publicChecks'] = checks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[4])
    parser.add_argument('--public', action='store_true', help='Check anonymous public assets and default README')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    report = local_check(args.root.resolve())
    if args.public:
        public_check(args.root.resolve(), report)
    output = json.dumps(report, ensure_ascii=False, indent=2) + '\n'
    if args.output:
        args.output.write_text(output)
    print(output, end='')
    return bool(report['errors'])


if __name__ == '__main__':
    raise SystemExit(main())
