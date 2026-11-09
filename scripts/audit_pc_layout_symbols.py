#!/usr/bin/env python3
"""Compare windows/linux layout JSON labels against xkeyboard-config basic ground truth.

Usage: python3 scripts/audit_pc_layout_symbols.py /tmp/xkb
"""
import json
import os
import sys

from generate_layout_jsons import BASE, XKB_REF, HAS_ALTGR, load_xkb


def main():
    xkb = load_xkb(sys.argv[1])
    total = 0
    for locale in XKB_REF:
        table = xkb[locale]
        for target_os in ('windows', 'linux'):
            path = os.path.join(BASE, f'{locale}_{target_os}.json')
            data = json.load(open(path))
            print(f'=== {locale}_{target_os}.json')
            mismatches = 0
            seen = set()
            for k in data['keys']:
                hid = k['hidUsageID']
                entry = table.get(hid)
                if entry is None:
                    continue
                seen.add(hid)
                plain, shift, altgr, _ = entry['chars']
                name, label = k['keyName'], k['label']
                shift_label, altgr_label = k.get('shiftLabel'), k.get('altGrLabel')
                problems = []
                is_letter = len(name) == 1 and name.isascii() and name.isalpha()
                if plain:
                    if is_letter:
                        if label.lower() != plain.lower():
                            problems.append(f'label {label!r} != plain {plain!r}')
                    elif label != plain:
                        problems.append(f'label {label!r} != plain {plain!r}')
                if shift and shift != plain and not is_letter:
                    if shift_label != shift:
                        problems.append(f'shiftLabel {shift_label!r} != shift {shift!r}')
                if locale in HAS_ALTGR and altgr and altgr not in (plain, shift, ''):
                    if altgr_label != altgr:
                        problems.append(f'altGrLabel {altgr_label!r} != altgr {altgr!r}')
                if problems:
                    mismatches += 1
                    print(f"  row{k['row']} col{k['column']} {name!r} hid={hid:02X}: " + '; '.join(problems))
            missing = [h for h, e in table.items() if e['chars'][0] and h not in seen]
            for hid in missing:
                mismatches += 1
                print(f'  missing key for HID {hid:02X} (plain {table[hid]["chars"][0]!r})')
            total += mismatches
            if mismatches == 0:
                print('  OK')
    print(f'\nTotal keys with mismatches: {total}')
    sys.exit(1 if total else 0)


if __name__ == '__main__':
    main()