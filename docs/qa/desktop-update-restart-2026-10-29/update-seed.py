"""Seed only the marked, isolated desktop-updater fixture; never launch an application."""
from pathlib import Path
import argparse, datetime, hashlib, json, plistlib, subprocess, time

DEFAULT_ROOT = '/private/tmp/countdown-desktop-update-fix-20261029'
TEST_ID = 'local.countdownmanager.update-test'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def defaults_export(domain):
    result = subprocess.run(['/usr/bin/defaults', 'export', domain, '-'], capture_output=True)
    return plistlib.loads(result.stdout) if result.returncode == 0 else None

def pdf_bytes():
    stream = b'BT /F1 12 Tf 30 90 Td (Synthetic update fixture) Tj ET'
    objects = [b'<< /Type /Catalog /Pages 2 0 R >>', b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
               b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 240 120] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
               b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
               b'<< /Length ' + str(len(stream)).encode() + b' >>\nstream\n' + stream + b'\nendstream']
    data = bytearray(b'%PDF-1.4\n'); offsets = [0]
    for index, body in enumerate(objects, 1):
        offsets.append(len(data)); data.extend(f'{index} 0 obj\n'.encode() + body + b'\nendobj\n')
    start = len(data); data.extend(f'xref\n0 {len(offsets)}\n0000000000 65535 f \n'.encode())
    for offset in offsets[1:]: data.extend(f'{offset:010d} 00000 n \n'.encode())
    data.extend(f'trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{start}\n%%EOF\n'.encode())
    return bytes(data)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', default=DEFAULT_ROOT)
    args = parser.parse_args(); root = Path(args.root).resolve()
    assert str(root).startswith('/private/tmp/countdown-desktop-update-fix-'), 'Unexpected fixture root'
    manifest = json.loads((root / 'test-manifest.json').read_text())
    home = Path(manifest['isolated_home']).resolve()
    assert home.parent == root and (home / '.countdown-update-test-environment').is_file()
    assert manifest['bundle_identifier'] == TEST_ID
    for label in ['older_app', 'newer_app']:
        app = Path(manifest[label]).resolve(); assert root in app.parents
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        assert info['CFBundleIdentifier'] == TEST_ID and info['CountdownUpdateTestMode'] is True
        assert Path(info['CountdownUpdateTestHome']).resolve() == home
        assert info['SUDefaultsDomain'] == TEST_ID
    support = home / 'Application Support/CountdownManager'; support.mkdir(parents=True, exist_ok=True)
    data_path = support / 'countdowns.json'
    assert not data_path.exists() and not (root / 'seed-snapshot.json').exists(), 'Preserve an already seeded fixture'
    today = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=3))).date()
    day = lambda value: dict(year=value.year, month=value.month, day=value.day)
    primary = '11111111-1111-1111-1111-111111111111'; future = '22222222-2222-2222-2222-222222222222'
    originals = root / 'Originals'; originals.mkdir(exist_ok=False)
    attachment_records = []
    for identity, name, body in [
        ('66666666-6666-6666-6666-666666666666', 'Route.txt', 'Синтетический маршрут\n\nТочные переносы и emoji 🏍️\n'.encode()),
        ('77777777-7777-7777-7777-777777777777', 'Booking.pdf', pdf_bytes())
    ]:
        original = originals / name; original.write_bytes(body)
        attachment = dict(id=identity, name=name, byteCount=len(body))
        folder = support / 'Attachments' / identity; folder.mkdir(parents=True, exist_ok=False)
        copy = folder / name; copy.write_bytes(body)
        marker = folder / ('.countdown-attachment-' + identity)
        marker.write_text(json.dumps(attachment, ensure_ascii=False))
        attachment_records.append(dict(metadata=attachment, original=str(original), copy=str(copy),
                                       marker=str(marker), sha256=digest(copy), markerSHA256=digest(marker)))
    data = dict(items=[
        dict(id=primary, title='Сохранённая поездка', note='Изолированные данные для проверки обновления.',
             date=day(today - datetime.timedelta(days=2)), emoji='', keepsAfterDate=True,
             subtasks=[dict(id='33333333-3333-3333-3333-333333333333', text='Маршрут сохранён', isCompleted=True),
                       dict(id='55555555-5555-5555-5555-555555555555', text='Проверить документы', isCompleted=False)],
             links=[dict(id='44444444-4444-4444-4444-444444444444', name='Маршрут', address='https://example.com/route')],
             attachments=[record['metadata'] for record in attachment_records]),
        dict(id=future, title='Будущая встреча', date=day(today + datetime.timedelta(days=5)), emoji='', subtasks=[], attachments=[])
    ], primaryID=primary)
    data_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    domain = 'local.countdownmanager.ui-smoke.' + home.parent.name + '.' + home.name
    assert domain.startswith('local.countdownmanager.ui-smoke.countdown-desktop-update-fix-')
    selected = {'appearance.selection': 'dark', 'whatsNew.lastPresentedRelease': '1.20.0',
                'timer.deadline': time.time() - 120,
                'expandedSubtasksByEvent': {primary: False, future: True}}
    preferences = root / 'seed-preferences.plist'; preferences.write_bytes(plistlib.dumps(selected))
    subprocess.run(['/usr/bin/defaults', 'import', domain, str(preferences)], check=True)
    imported = defaults_export(domain); assert imported is not None
    assert all(imported.get(key) == value for key, value in selected.items())
    sparkle_before = defaults_export(TEST_ID)
    if sparkle_before is not None:
        (root / 'sparkle-defaults-before.plist').write_bytes(plistlib.dumps(sparkle_before))
    subprocess.run(['/usr/bin/defaults', 'write', TEST_ID, 'SUEnableAutomaticChecks', '-bool', 'false'], check=True)
    assert defaults_export(TEST_ID).get('SUEnableAutomaticChecks') is False
    snapshot = dict(root=str(root), isolatedHome=str(home), defaultsDomain=domain,
                    productionDataUsed=False, localSeedDay=today.isoformat(), dataPath=str(data_path),
                    jsonSHA256=digest(data_path), eventIDs=[primary, future], primaryID=primary,
                    selectedPreferences={key: imported[key] for key in selected}, attachments=attachment_records,
                    sparkleDefaultsDomain=TEST_ID, sparkleAutomaticChecks=False,
                    sparkleDefaultsPreviouslyExisted=sparkle_before is not None,
                    sparkleDefaultsBackup=str(root / 'sparkle-defaults-before.plist') if sparkle_before is not None else None)
    (root / 'seed-snapshot.json').write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(dict(status='SEEDED', isolatedHome=str(home), defaultsDomain=domain,
                          eventCount=2, attachmentCount=2, productionDataUsed=False), ensure_ascii=False), flush=True)

if __name__ == '__main__': main()
