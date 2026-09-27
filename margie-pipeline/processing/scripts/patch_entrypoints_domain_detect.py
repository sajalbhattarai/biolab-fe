#!/usr/bin/env python3
"""One-off patch: rewrites each container entrypoint's filename-token block so it
also recognises _bact_gram*/_bact/_arch/_unknown suffixes and sets DOMAIN.
Idempotent: entrypoints that already have the new block are left alone.
"""
import re, pathlib, sys

ROOT = pathlib.Path('processing/containers/build')
files = sorted(ROOT.glob('*/entrypoint.sh'))

OLD = (
    'if [[ -z "$GRAM_STAIN" ]]; then\n'
    '    INPUT_STEM_LOWER=$(basename "$INPUT" | tr \'[:upper:]\' \'[:lower:]\')\n'
    '    case "$INPUT_STEM_LOWER" in\n'
    '        *_gramn.*|*_gramn) GRAM_STAIN="negative" ;;\n'
    '        *_gramp.*|*_gramp) GRAM_STAIN="positive" ;;\n'
    '        *_archaea.*|*_archaea|*_arch.*|*_arch) GRAM_STAIN="unknown" ;;\n'
    '    esac\n'
    '    if [[ -n "$GRAM_STAIN" ]]; then\n'
    '        echo "[{tool}] Auto-detected gram from filename token: --gram-stain $GRAM_STAIN"\n'
    '    fi\n'
    'fi'
)

NEW = (
    'if [[ -z "$GRAM_STAIN" || -z "$DOMAIN" ]]; then\n'
    '    INPUT_STEM_LOWER=$(basename "$INPUT" | tr \'[:upper:]\' \'[:lower:]\')\n'
    '    # Canonical suffixes (post-normalisation):\n'
    '    #   _bact_gramN -> Bacteria/negative   _bact_gramP -> Bacteria/positive\n'
    '    #   _bact_gramU -> Bacteria/unknown    _bact       -> Bacteria/(unknown)\n'
    '    #   _arch / _archaea -> Archaea        _unknown    -> Unknown\n'
    '    # Legacy short suffixes still accepted: _gramN, _gramP, _gramU.\n'
    '    case "$INPUT_STEM_LOWER" in\n'
    '        *_bact_gramn.*|*_bact_gramn) GRAM_STAIN="${{GRAM_STAIN:-negative}}"; DOMAIN="${{DOMAIN:-Bacteria}}" ;;\n'
    '        *_bact_gramp.*|*_bact_gramp) GRAM_STAIN="${{GRAM_STAIN:-positive}}"; DOMAIN="${{DOMAIN:-Bacteria}}" ;;\n'
    '        *_bact_gramu.*|*_bact_gramu) GRAM_STAIN="${{GRAM_STAIN:-unknown}}";  DOMAIN="${{DOMAIN:-Bacteria}}" ;;\n'
    '        *_bact.*|*_bact)             GRAM_STAIN="${{GRAM_STAIN:-unknown}}";  DOMAIN="${{DOMAIN:-Bacteria}}" ;;\n'
    '        *_gramn.*|*_gramn) GRAM_STAIN="${{GRAM_STAIN:-negative}}"; DOMAIN="${{DOMAIN:-Bacteria}}" ;;\n'
    '        *_gramp.*|*_gramp) GRAM_STAIN="${{GRAM_STAIN:-positive}}"; DOMAIN="${{DOMAIN:-Bacteria}}" ;;\n'
    '        *_gramu.*|*_gramu) GRAM_STAIN="${{GRAM_STAIN:-unknown}}";  DOMAIN="${{DOMAIN:-Bacteria}}" ;;\n'
    '        *_archaea.*|*_archaea|*_arch.*|*_arch) GRAM_STAIN="${{GRAM_STAIN:-unknown}}"; DOMAIN="${{DOMAIN:-Archaea}}" ;;\n'
    '        *_unknown.*|*_unknown) GRAM_STAIN="${{GRAM_STAIN:-unknown}}"; DOMAIN="${{DOMAIN:-Unknown}}" ;;\n'
    '    esac\n'
    '    [[ -n "$GRAM_STAIN" ]] && echo "[{tool}] Auto-detected from filename token: --gram-stain $GRAM_STAIN  --domain ${{DOMAIN:-Unknown}}"\n'
    'fi'
)

changed = []
already = []
missing = []
for f in files:
    s = f.read_text()
    tool = f.parent.name
    old_block = OLD.format(tool=tool)
    new_block = NEW.format(tool=tool)
    if new_block in s:
        already.append(tool); continue
    if old_block not in s:
        missing.append(tool); continue
    f.write_text(s.replace(old_block, new_block, 1))
    changed.append(tool)

print(f'changed:  {len(changed)} -> {", ".join(changed)}')
print(f'already:  {len(already)} -> {", ".join(already)}')
print(f'no-match: {len(missing)} -> {", ".join(missing)}')
