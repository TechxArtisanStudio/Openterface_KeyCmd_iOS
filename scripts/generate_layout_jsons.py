#!/usr/bin/env python3
"""Regenerate Resources/KeyboardLayouts/*.json from ground-truth symbol tables.

Ground truth:
  - macOS variants: UCKeyTranslate extraction (scripts/extract_macos_layout_symbols.swift)
  - Windows/Linux variants: xkeyboard-config `basic` variants (base/shift layers
    match the Windows standard layouts)

Usage:
  swift scripts/extract_macos_layout_symbols.swift > /tmp/macos_layouts.json
  # download xkeyboard-config symbols/{fr,gb,de,es,it,pt,be,ch,se,us,latin} to /tmp/xkb
  python3 scripts/generate_layout_jsons.py /tmp/macos_layouts.json /tmp/xkb

jp_macos_ansi.json / jp_macos_jis.json are hand-verified and left untouched.
"""
import json
import os
import re
import sys

BASE = os.path.join(os.path.dirname(__file__), '..', 'Resources', 'KeyboardLayouts')

HID_TO_VK = {
    0x04: 0, 0x05: 11, 0x06: 8, 0x07: 2, 0x08: 14, 0x09: 3, 0x0A: 5,
    0x0B: 4, 0x0C: 34, 0x0D: 38, 0x0E: 40, 0x0F: 37, 0x10: 46, 0x11: 45,
    0x12: 31, 0x13: 35, 0x14: 12, 0x15: 15, 0x16: 1, 0x17: 17, 0x18: 32,
    0x19: 9, 0x1A: 13, 0x1B: 7, 0x1C: 16, 0x1D: 6,
    0x1E: 18, 0x1F: 19, 0x20: 20, 0x21: 21, 0x22: 23, 0x23: 22, 0x24: 26,
    0x25: 28, 0x26: 25, 0x27: 29,
    0x2D: 27, 0x2E: 24, 0x2F: 33, 0x30: 30, 0x31: 42,
    0x33: 41, 0x34: 39, 0x35: 50, 0x36: 43, 0x37: 47, 0x38: 44,
    0x64: 10,
}

APPLE_REF = {
    'us': 'US', 'cn': 'US', 'uk': 'British', 'au': 'Australian', 'ca': 'Canadian',
    'de': 'German', 'fr': 'French', 'es': 'Spanish-ISO', 'it': 'Italian-Pro',
    'pt': 'Portuguese', 'be': 'Belgian', 'ch': 'SwissGerman', 'nordic': 'Swedish-Pro',
}
XKB_REF = {
    'us': 'us', 'cn': 'us', 'au': 'us', 'ca': 'us', 'uk': 'gb', 'de': 'de',
    'fr': 'fr', 'es': 'es', 'it': 'it', 'pt': 'pt', 'be': 'be', 'ch': 'ch',
    'nordic': 'se',
}
# Locales whose row 4 carries the ISO key (HID 0x64) next to LeftShift.
ISO_KEY_LOCALES = {'uk', 'de', 'fr', 'es', 'it', 'pt', 'be', 'ch', 'nordic'}
HAS_ALTGR = {'de', 'fr', 'es', 'it', 'pt', 'be', 'ch', 'nordic'}

ROW1 = [0x35, 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x2D, 0x2E]
ROW2 = [0x14, 0x1A, 0x08, 0x15, 0x17, 0x1C, 0x18, 0x0C, 0x12, 0x13, 0x2F, 0x30, 0x31]
ROW3 = [0x04, 0x16, 0x07, 0x09, 0x0A, 0x0B, 0x0D, 0x0E, 0x0F, 0x33, 0x34]
ROW4 = [0x1D, 0x1B, 0x06, 0x19, 0x05, 0x11, 0x10, 0x36, 0x37, 0x38]

XKB_KEY_TO_HID = {
    'TLDE': 0x35, 'LSGT': 0x64, 'BKSL': 0x31,
    **{f'AE{i:02d}': h for i, h in zip(range(1, 13), [0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x2D, 0x2E])},
    **{f'AD{i:02d}': h for i, h in zip(range(1, 13), [0x14, 0x1A, 0x08, 0x15, 0x17, 0x1C, 0x18, 0x0C, 0x12, 0x13, 0x2F, 0x30])},
    **{f'AC{i:02d}': h for i, h in zip(range(1, 12), [0x04, 0x16, 0x07, 0x09, 0x0A, 0x0B, 0x0D, 0x0E, 0x0F, 0x33, 0x34])},
    **{f'AB{i:02d}': h for i, h in zip(range(1, 11), [0x1D, 0x1B, 0x06, 0x19, 0x05, 0x11, 0x10, 0x36, 0x37, 0x38])},
}

DEAD_CHAR_TO_CASE = {
    '´': 'acute', '`': 'grave', '^': 'circumflex', '¨': 'diaeresis', '~': 'tilde',
    '°': 'ring', 'ˇ': 'caron', '¯': 'macron', '˘': 'breve', '˙': 'dotAbove',
    '¸': 'cedilla', '˛': 'ogonek', '˝': 'doubleAcute',
}
DEAD_KEYSYM_TO_CHAR = {
    'dead_grave': '`', 'dead_acute': '´', 'dead_circumflex': '^', 'dead_tilde': '~',
    'dead_diaeresis': '¨', 'dead_abovering': '°', 'dead_cedilla': '¸', 'dead_ogonek': '˛',
    'dead_macron': '¯', 'dead_breve': '˘', 'dead_abovedot': '˙', 'dead_doubleacute': '˝',
    'dead_caron': 'ˇ',
}
LEGACY_KEYSYM = {
    'ellipsis': '…', 'leftarrow': '←', 'rightarrow': '→', 'uparrow': '↑', 'downarrow': '↓',
    'Greek_omega': 'ω', 'Greek_OMEGA': 'Ω', 'Greek_sigma': 'σ', 'Greek_SIGMA': 'Σ',
    'Greek_pi': 'π', 'Greek_PI': 'Π',
}
NON_ASCII_NAME = {
    'é': 'eacute', 'è': 'egrave', 'à': 'agrave', 'ç': 'ccedilla', 'ù': 'ugrave',
    'ü': 'uuml', 'ö': 'ouml', 'ä': 'auml', 'å': 'aring', 'ñ': 'ntilde',
    'ò': 'ograve', 'ì': 'igrave', 'æ': 'ae', 'ø': 'oslash', 'ß': 'ssharp',
    'µ': 'mu', 'º': 'masculine', '²': 'supra_2', '§': 'section', '¡': 'exclam_down',
    '£': 'sterling', '¤': 'currency', '¥': 'yen',
}


def load_apple(path):
    layouts = {l['layoutID']: l for l in json.load(open(path))}
    tables = {}
    for locale, ref in APPLE_REF.items():
        l = layouts['com.apple.keylayout.' + ref]
        table = {}
        for hid, vk in HID_TO_VK.items():
            g = l['keys'].get(str(vk))
            if not g:
                continue
            dead = l.get('dead', {}).get(str(vk), [False] * 4)
            table[hid] = {'chars': g, 'dead': dead}
        tables[locale] = table
    return tables


def parse_xkb_keysymdef(path):
    syms = {}
    for line in open(path, encoding='utf-8', errors='replace'):
        m = re.match(r'#define\s+XK_(\w+)\s+0x([0-9a-fA-F]+)', line)
        if m:
            syms[m.group(1)] = int(m.group(2), 16)
    return syms


def make_keysym_resolver(syms):
    def resolve(name):
        """Return (char_or_None, is_dead)."""
        if name in ('VoidSymbol', ''):
            return None, False
        if name.startswith('dead_'):
            return DEAD_KEYSYM_TO_CHAR.get(name), True
        m = re.fullmatch(r'U([0-9A-Fa-f]{4,6})', name)
        if m:
            return chr(int(m.group(1), 16)), False
        if name in LEGACY_KEYSYM:
            return LEGACY_KEYSYM[name], False
        if name in syms:
            v = syms[name]
            if v >= 0x01000000:
                return chr(v - 0x01000000), False
            if 0x20 <= v <= 0xFF or v in (0x20AC,):
                return chr(v), False
            return None, False
        if len(name) == 1:
            return name, False
        return None, False
    return resolve


def parse_xkb_variant_body(body, resolve):
    """Parse key lines of one xkb_symbols block into {hid: {chars, dead}}."""
    table = {}
    for m in re.finditer(r'key\s+<(\w+)>\s*\{\s*\[([^\]]*)\]', body):
        key_name, syms_str = m.group(1), m.group(2)
        hid = XKB_KEY_TO_HID.get(key_name)
        if hid is None:
            continue
        names = [s.strip() for s in syms_str.split(',')]
        chars, dead = [], []
        for n in names[:4]:
            c, d = resolve(n)
            chars.append(c)
            dead.append(d)
        while len(chars) < 4:
            chars.append(None)
            dead.append(False)
        table[hid] = {'chars': chars, 'dead': dead}
    return table


def load_xkb(dir_path):
    resolve = make_keysym_resolver(parse_xkb_keysymdef(os.path.join(dir_path, 'keysymdef.h')))
    files = {}
    for f in os.listdir(dir_path):
        if f in ('keysymdef.h', 'level3'):
            continue
        src = open(os.path.join(dir_path, f), encoding='utf-8', errors='replace').read()
        variants = {}
        for m in re.finditer(r'xkb_symbols\s+"([^"]+)"\s*\{(.*?)\n\};', src, re.S):
            variants[m.group(1)] = m.group(2)
        files[f] = variants

    def resolve_variant(file, variant):
        body = files[file][variant]
        table = {}
        for inc in re.finditer(r'include\s+"([\w]+)(?:\(([\w]+)\))?"', body):
            inc_file, inc_variant = inc.group(1), inc.group(2) or 'basic'
            if inc_file in ('level3', 'kpdl'):
                continue
            if inc_file == file:
                table.update(resolve_variant(file, inc_variant))
            elif inc_file in files:
                table.update(resolve_variant(inc_file, inc_variant))
        table.update(parse_xkb_variant_body(body, resolve))
        return table

    tables = {}
    for locale, ref in XKB_REF.items():
        variants = files[ref]
        default = 'basic' if 'basic' in variants else next(iter(variants))
        table = resolve_variant(ref, default)
        # fr/es basic variants omit LSGT; the physical ISO key is always <>.
        if locale in ISO_KEY_LOCALES and 0x64 not in table:
            table[0x64] = {'chars': ['<', '>', None, None], 'dead': [False] * 4}
        tables[locale] = table
    return tables


def key_name_for(plain, used_names):
    if plain.isascii() and plain.isalpha():
        name = plain.lower()
    elif plain.isascii():
        name = plain
    else:
        name = NON_ASCII_NAME.get(plain)
        if name is None:
            name = 'u%04X' % ord(plain)
    if name in used_names:
        raise ValueError(f'duplicate keyName {name!r}')
    used_names.add(name)
    return name


def symbol_key(hid, entry, locale, target_os, used_names):
    chars = entry['chars']
    dead = entry['dead']
    plain = chars[0]
    if not plain:
        return None
    shift = chars[1] if len(chars) > 1 else None
    altgr = chars[2] if len(chars) > 2 else None
    is_ascii_letter = len(plain) == 1 and plain.isascii() and plain.isalpha()
    if is_ascii_letter:
        label = plain.lower() if target_os == 'macos' else plain.upper()
    else:
        label = plain
    key = {
        'hidUsageID': hid,
        'keyName': key_name_for(plain, used_names),
        'label': label,
        'keyType': 'regular',
    }
    if shift and shift != plain and not is_ascii_letter:
        key['shiftLabel'] = shift
    if locale in HAS_ALTGR and altgr and altgr not in (plain, shift, '\uf8ff'):
        key['altGrLabel'] = altgr
    if dead and dead[0] and plain in DEAD_CHAR_TO_CASE:
        key['deadKey'] = DEAD_CHAR_TO_CASE[plain]
    return key


def special_key(hid, name, label, key_type='regular', width=None):
    k = {'hidUsageID': hid, 'keyName': name, 'label': label, 'keyType': key_type}
    if width is not None:
        k['width'] = width
    return k


def build_layout(locale, target_os, table, old):
    mac = target_os == 'macos'
    keys = []
    used_names = set()

    def add(row, col, key):
        key['row'] = row
        key['column'] = col
        keys.append(key)

    def add_sym(row, col, hid):
        entry = table.get(hid)
        if not entry:
            raise ValueError(f'{locale}_{target_os}: no ground truth for HID {hid:02X}')
        k = symbol_key(hid, entry, locale, target_os, used_names)
        if k is None:
            raise ValueError(f'{locale}_{target_os}: empty plain output for HID {hid:02X}')
        add(row, col, k)

    # Row 0: function row
    add(0, 0, special_key(0x29, 'Esc', 'esc' if mac else 'Esc'))
    for i in range(12):
        add(0, i + 1, special_key(0x3A + i, f'F{i + 1}', f'F{i + 1}'))
    if mac:
        add(0, 13, special_key(0x65, 'Menu', '≡'))

    # Row 1: number row
    for col, hid in enumerate(ROW1):
        add_sym(1, col, hid)
    add(1, 13, special_key(0x2A, 'Backspace', '⌫' if mac else 'Backspace'))

    # Row 2
    add(2, 0, special_key(0x2B, 'Tab', '⇥' if mac else 'Tab'))
    for col, hid in enumerate(ROW2):
        add_sym(2, col + 1, hid)
    if mac:
        add(2, 14, special_key(0x4C, 'ForwardDelete', '⌦'))

    # Row 3
    add(3, 0, special_key(0x39, 'Caps', '⇪' if mac else 'Caps', 'special'))
    for col, hid in enumerate(ROW3):
        add_sym(3, col + 1, hid)
    add(3, 12, special_key(0x28, 'Enter', '↩' if mac else 'Enter'))

    # Row 4
    add(4, 0, special_key(0xE1, 'LeftShift', '⇧' if mac else 'Shift', 'modifier', 1.5))
    col = 1
    if locale in ISO_KEY_LOCALES:
        add_sym(4, col, 0x64)
        col += 1
    for hid in ROW4:
        add_sym(4, col, hid)
        col += 1
    add(4, col, special_key(0xE5, 'RightShift', '⇧' if mac else 'Shift', 'modifier', 1.5))
    if not mac:
        add(4, col + 1, special_key(0x52, 'Up', '↑'))

    # Row 5
    if mac:
        add(5, 0, special_key(0x6A, 'Fn', 'fn'))
        add(5, 1, special_key(0xE0, 'LeftCtrl', '⌃', 'modifier'))
        add(5, 2, special_key(0xE2, 'LeftAlt', '⌥', 'modifier'))
        add(5, 3, special_key(0xE3, 'LeftWin', '⌘', 'modifier'))
        add(5, 4, special_key(0x2C, 'Space', ' ', 'regular', 5.0))
        add(5, 9, special_key(0xE7, 'RightWin', '⌘', 'modifier'))
        add(5, 10, special_key(0xE6, 'RightAlt', '⌥', 'modifier'))
        add(5, 11, special_key(0xE4, 'RightCtrl', '⌃', 'modifier'))
        add(5, 12, special_key(0x50, 'Left', '←'))
        add(5, 13, special_key(0x52, 'Up', '↑'))
        add(5, 14, special_key(0x51, 'Down', '↓'))
        add(5, 15, special_key(0x4F, 'Right', '→'))
    else:
        altgr = locale in HAS_ALTGR
        add(5, 0, special_key(0xE0, 'LeftCtrl', 'Ctrl', 'modifier'))
        add(5, 1, special_key(0xE3, 'LeftWin', 'Win', 'modifier'))
        add(5, 2, special_key(0xE2, 'LeftAlt', 'Alt', 'modifier'))
        add(5, 3, special_key(0x2C, 'Space', ' ', 'regular', 6.0))
        add(5, 4, special_key(0xE6, 'RightAlt', 'AltGr' if altgr else 'Alt', 'modifier'))
        add(5, 5, special_key(0xE7, 'RightWin', 'Win', 'modifier'))
        add(5, 6, special_key(0x65, 'Menu', 'Menu'))
        add(5, 7, special_key(0xE4, 'RightCtrl', 'Ctrl', 'modifier'))
        add(5, 8, special_key(0x50, 'Left', '←'))
        add(5, 9, special_key(0x51, 'Down', '↓'))
        add(5, 10, special_key(0x4F, 'Right', '→'))

    metadata = dict(old['metadata'])
    metadata['hasAltGr'] = locale in HAS_ALTGR
    if mac:
        suffix = ' matching macOS Keyboard Viewer'
        desc = old['metadata'].get('description', '')
        while desc.endswith(suffix):
            desc = desc[:-len(suffix)]
        metadata['description'] = desc + suffix
    return {'locale': locale, 'targetOS': target_os, 'metadata': metadata, 'keys': keys}


# JIS symbol rows for jp_windows / jp_linux (PC JIS keycaps).
JIS_ROW1 = [
    (0x35, '半角/全角', '半角/全角', '漢字', None),
    (0x1E, '1', '1', '!', None), (0x1F, '2', '2', '"', None),
    (0x20, '3', '3', '#', None), (0x21, '4', '4', '$', None),
    (0x22, '5', '5', '%', None), (0x23, '6', '6', '&', None),
    (0x24, '7', '7', "'", None), (0x25, '8', '8', '(', None),
    (0x26, '9', '9', ')', None), (0x27, '0', '0', 'を', None),
    (0x2D, '-', '-', '=', None), (0x2E, '^', '^', '~', None),
    (0x89, '¥', '¥', '|', None),
]
JIS_LETTERS = {
    0x14: 'q', 0x1A: 'w', 0x08: 'e', 0x15: 'r', 0x17: 't', 0x1C: 'y',
    0x18: 'u', 0x0C: 'i', 0x12: 'o', 0x13: 'p',
    0x04: 'a', 0x16: 's', 0x07: 'd', 0x09: 'f', 0x0A: 'g', 0x0B: 'h',
    0x0D: 'j', 0x0E: 'k', 0x0F: 'l',
    0x1D: 'z', 0x1B: 'x', 0x06: 'c', 0x19: 'v', 0x05: 'b', 0x11: 'n', 0x10: 'm',
}
JIS_SYMBOLS = {
    0x2F: ('@', '@', '`'), 0x30: ('[', '[', '{'),
    0x33: (';', ';', '+'), 0x34: (':', ':', '*'), 0x31: (']', ']', '}'),
    0x36: (',', ',', '<'), 0x37: ('.', '.', '>'), 0x38: ('/', '/', '?'),
}


def fix_jis_pc(old):
    """Rebuild symbol rows of jp_windows/jp_linux, keep function/bottom rows."""
    keys = [k for k in old['keys'] if k['row'] in (0, 5)]
    # Drop the misplaced yen key (HID 0x64) from row 2; yen lives at 0x89 row 1.
    keys = [k for k in keys if not (k['row'] == 5 and k['hidUsageID'] == 0x64)]

    def add(row, col, hid, name, label, shift=None, key_type='regular', width=None):
        k = {'hidUsageID': hid, 'keyName': name, 'label': label, 'row': row, 'column': col, 'keyType': key_type}
        if shift:
            k['shiftLabel'] = shift
        if width is not None:
            k['width'] = width
        keys.append(k)

    for col, (hid, name, label, shift, _) in enumerate(JIS_ROW1):
        add(1, col, hid, name, label, shift)
    add(1, len(JIS_ROW1), 0x2A, 'Backspace', 'Backspace')

    add(2, 0, 0x2B, 'Tab', 'Tab')
    for col, hid in enumerate([0x14, 0x1A, 0x08, 0x15, 0x17, 0x1C, 0x18, 0x0C, 0x12, 0x13]):
        add(2, col + 1, hid, JIS_LETTERS[hid], JIS_LETTERS[hid].upper())
    for col, hid in enumerate([0x2F, 0x30]):
        name, label, shift = JIS_SYMBOLS[hid]
        add(2, col + 11, hid, name, label, shift)

    add(3, 0, 0x39, 'Caps', 'Caps', key_type='special')
    for col, hid in enumerate([0x04, 0x16, 0x07, 0x09, 0x0A, 0x0B, 0x0D, 0x0E, 0x0F]):
        add(3, col + 1, hid, JIS_LETTERS[hid], JIS_LETTERS[hid].upper())
    for col, hid in enumerate([0x33, 0x34, 0x31]):
        name, label, shift = JIS_SYMBOLS[hid]
        add(3, col + 10, hid, name, label, shift)
    add(3, 13, 0x28, 'Enter', 'Enter')

    add(4, 0, 0xE1, 'LeftShift', 'Shift', key_type='modifier', width=1.5)
    for col, hid in enumerate([0x1D, 0x1B, 0x06, 0x19, 0x05, 0x11, 0x10]):
        add(4, col + 1, hid, JIS_LETTERS[hid], JIS_LETTERS[hid].upper())
    for col, hid in enumerate([0x36, 0x37, 0x38]):
        name, label, shift = JIS_SYMBOLS[hid]
        add(4, col + 8, hid, name, label, shift)
    add(4, 11, 0xE5, 'RightShift', 'Shift', key_type='modifier', width=1.5)
    add(4, 12, 0x52, 'Up', '↑')

    keys.sort(key=lambda k: (k['row'], k['column']))
    return {'locale': old['locale'], 'targetOS': old['targetOS'], 'metadata': old['metadata'], 'keys': keys}


def main():
    apple = load_apple(sys.argv[1])
    xkb = load_xkb(sys.argv[2])
    written = []
    for locale in list(APPLE_REF) + ['jp']:
        for target_os in ('macos', 'windows', 'linux'):
            if locale == 'jp':
                if target_os == 'macos':
                    continue  # hand-verified files
                path = os.path.join(BASE, 'jp_%s.json' % target_os)
                result = fix_jis_pc(json.load(open(path)))
            else:
                path = os.path.join(BASE, f'{locale}_{target_os}.json')
                old = json.load(open(path))
                table = apple[locale] if target_os == 'macos' else xkb[locale]
                result = build_layout(locale, target_os, table, old)
            with open(path, 'w', encoding='utf-8') as f:
                json.dump(result, f, ensure_ascii=False, indent=2)
                f.write('\n')
            written.append(os.path.basename(path))
    print(f'Wrote {len(written)} files:')
    for w in written:
        print(' ', w)


if __name__ == '__main__':
    main()