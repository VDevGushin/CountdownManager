#!/usr/bin/env python3
"""Compile theme-aware AppIcon assets using Xcode; normal builds copy Assets.car."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preview', action='store_true', help='export Default/Dark source previews using Icon Composer')
    args = parser.parse_args()
    source = ROOT / 'Resources/AppIcon.icon'
    output = ROOT / '.build/app-icon-brand'
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='compile-', dir=output) as temporary:
        stage = Path(temporary)
        result = subprocess.run([
            'xcrun', 'actool', str(source), '--compile', str(stage),
            '--platform', 'macosx', '--target-device', 'mac',
            '--minimum-deployment-target', '13.0', '--app-icon', 'AppIcon',
            '--output-format', 'xml1', '--output-partial-info-plist', str(stage / 'partial.plist'),
        ], check=True, capture_output=True)
        (output / 'actool.plist').write_bytes(result.stdout)
        metadata = plistlib.loads((stage / 'partial.plist').read_bytes())
        assert metadata.get('CFBundleIconName') == 'AppIcon', metadata
        assert metadata.get('CFBundleIconFile') == 'AppIcon', metadata
        inventory = json.loads(subprocess.check_output(['assetutil', '--info', str(stage / 'Assets.car')]))
        appearances = {r.get('Appearance') for r in inventory if r.get('AssetType') == 'IconImageStack' and r.get('Name') == 'AppIcon'}
        assert {'NSAppearanceNameAqua', 'NSAppearanceNameDarkAqua'} <= appearances, appearances
        assert any(r.get('AssetType') == 'MultiSized Image' and r.get('Name') == 'AppIcon' for r in inventory), 'Missing legacy icon asset'
        (output / 'asset-inventory.json').write_text(json.dumps(inventory, indent=2) + '\n')
        (output / 'partial.plist').write_bytes((stage / 'partial.plist').read_bytes())
        # Keep our deterministic legacy ICNS; actool's emitted fallback is not used here.
        shutil.copy2(stage / 'Assets.car', ROOT / 'Resources/Assets.car')
    if args.preview:
        developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
        tool = developer.parent / 'Applications/Icon Composer.app/Contents/Executables/ictool'
        if not tool.is_file():
            raise RuntimeError('Icon Composer from full Xcode 26 or newer is required for source previews')
        for rendition in ['Default', 'Dark']:
            subprocess.run([
                str(tool), str(source), '--export-image', '--output-file', str(output / f'{rendition.lower()}.png'),
                '--platform', 'macOS', '--rendition', rendition,
                '--width', '512', '--height', '512', '--scale', '1', '--design-generation', '26',
            ], check=True, capture_output=True)
    print('Compiled AppIcon: Default/Dark icon stacks and compatible legacy renditions')


if __name__ == '__main__':
    main()
