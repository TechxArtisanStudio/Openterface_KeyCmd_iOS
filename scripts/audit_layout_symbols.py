#!/usr/bin/env python3
"""Compare layout JSON labels against macOS UCKeyTranslate ground truth.

Usage: python3 scripts/audit_layout_symbols.py /tmp/macos_layouts.json [--verbose]
"""
import json
import sys
import os

BASE = os.path.join(os.path.dirname(__file__), '..', 'Resources', 'KeyboardLayouts')

# USB HID usage -> macOS virtual keycode (ANSI/ISO printable keys)
HID_TO_VK = {
    0x04: 0, 0x05: 11, 0x06: 8, 0x07: 2, 0x08: 14, 0x09: 3, 0x0A: 5,
    0x0B: 4, 0x0C: 34, 0x0D: 38, 0x0E: 40, 0x0F: 37, 0x10: 46, 0x11: 45,
    0x12: 31, 0x13: 35, 0x14: 12, 0x15: 15, 0x16: 1, 0x17: 17, 0x18: 32,
    0x19: 9, 0x1A: 13, 0x1B: 7, 0x1C: 16, 0x1D: 6,
    0x1E: 18, 0x1F: 19, 0x20: 20, 0x21: 21, 0x22: 23, 0x23: 22, 0x24: 26,
    0x25: 28, 0x26: 25, 0x27: 29,
    0x2D: 27, 0x2E: 24, 0x2F: 33, 0x30: 30, 0x31: 42, 0x32: 42,
    0x33: 41, 0x34: 39, 0x35: 50, 0x36: 43, 0x37: 47, 0x38: 44,
    0x64: 10,  # ISO key next to left shift
    0x87: 94, 0x89: 93,  # JIS Ro / Yen
}

# Which Apple layout is the reference for each locale's macOS variant.
REFERENCE = {
    'us': 'com.apple.keylayout.US',
    'cn': 'com.apple.keylayout.US',
    'uk': 'com.apple.keylayout.British',
    'au': 'com.apple.keylayout.Australian',
    'de': 'com.apple.keylayout.German',
    'fr': 'com.apple.keylayout.French',
    'es': 'com.apple.keylayout.Spanish-ISO',
    'it': 'com.apple.keylayout.Italian-Pro',
    'pt': 'com.apple.keylayout.Portuguese',
    'ca': 'com.apple.keylayout.Canadian',
    'be': 'com.apple.keylayout.Belgian',
    'ch': 'com.apple.keylayout.SwissGerman',
    'nordic': 'com.apple.keylayout.Swedish-Pro',
    'jp': None,  # JIS keycaps verified separately; ANSI variant uses US
}

def main():
    gt_path = sys.argv[1]
    verbose = '--verbose' in sys.argv
    layouts = {l['layoutID']: l for l in json.load(open(gt_path))}
    total_mismatch = 0
    for locale, ref in REFERENCE.items():
        path = os.path.join(BASE, f'{locale}_macos.json')
        if not os.path.exists(path):
            path = os.path.join(BASE, f'{locale}_macos_ansi.json')
        if locale == 'jp':
            ref = 'com.apple.keylayout.US'
            path = os.path.join(BASE, 'jp_macos_ansi.json')
        if ref is None or not os.path.exists(path):
            continue
        gt = layouts[ref]['keys']
        data = json.load(open(path))
        print(f"=== {os.path.basename(path)}  (ref: {layouts[ref]['name']})")
        mismatches = 0
        for k in data['keys']:
            hid = k['hidUsageID']
            vk = HID_TO_VK.get(hid)
            if vk is None:
                continue
            g = gt.get(str(vk))
            if g is None:
                continue
            plain, shift, option, _shift_option = g
            name = k['keyName']
            label = k['label']
            shift_label = k.get('shiftLabel')
            altgr_label = k.get('altGrLabel')
            problems = []
            # Matches displayText: single-char letter keyNames case dynamically.
            is_letter = len(name) == 1 and name.isalpha()
            if is_letter:
                if plain and label.lower() != plain.lower():
                    problems.append(f'label {label!r} != plain {plain!r}')
            else:
                if plain and label != plain:
                    problems.append(f'label {label!r} != plain {plain!r}')
                if shift and shift != plain:
                    if shift_label != shift:
                        problems.append(f'shiftLabel {shift_label!r} != shift {shift!r}')
                elif shift_label is not None and not is_letter:
                    problems.append(f'shiftLabel {shift_label!r} but ground truth shift == plain')
            if option and option != plain and option != shift:
                if altgr_label is not None and altgr_label != option:
                    problems.append(f'altGrLabel {altgr_label!r} != option {option!r}')
                elif altgr_label is None and verbose:
                    problems.append(f'(missing altGrLabel, option={option!r})')
            elif altgr_label is not None:
                problems.append(f'altGrLabel {altgr_label!r} but ground truth has no distinct option output ({option!r})')
            if problems:
                mismatches += 1
                print(f"  row{k['row']} col{k['column']} {name!r} hid={hid:02X} vk={vk}: " + '; '.join(problems))
        total_mismatch += mismatches
        if mismatches == 0:
            print('  OK')
    print(f'\nTotal keys with mismatches: {total_mismatch}')

if __name__ == '__main__':
    main()