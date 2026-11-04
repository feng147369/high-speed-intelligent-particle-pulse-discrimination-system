"""Read-only Vivado ILA CSV audit; Python standard library only."""
import argparse
import csv
import hashlib
import json
import math
import re
from pathlib import Path


def audit(path, signals, bits=14, shift=0, valid=None, event=None, signed=False):
    if not 1 <= bits <= 64 or not 0 <= shift <= 63:
        raise ValueError('bits must be 1..64, shift 0..63')
    path = Path(path)
    with path.open(encoding='utf-8-sig', newline='') as f:
        rows = list(csv.reader(f))
    if len(rows) < 3:
        raise ValueError('Expected ILA header, radix row and samples')
    names = [n.strip() for n in rows[0]]
    if len(set(names)) != len(names):
        raise ValueError('Duplicate column names are ambiguous')
    radix = [v.strip().upper().removeprefix('RADIX - ').strip() for v in rows[1]]
    if len(radix) != len(names):
        raise ValueError('Radix row width mismatch')
    bases = {'HEX':16, 'BIN':2, 'OCT':8, 'DEC':10, 'UNSIGNED':10, 'SIGNED':10}
    if any(v not in bases for v in radix):
        raise ValueError('Unsupported radix: '+str(radix))
    wanted = list(dict.fromkeys(signals + [x for x in [valid,event] if x]))
    missing = set(wanted)-set(names)
    if missing:
        raise ValueError('Missing signals: '+str(sorted(missing)))
    indexes = {n:names.index(n) for n in wanted}
    values = {n:[] for n in signals}
    events = []
    sample_count = 0
    valid_count = 0
    mask = (1 << bits)-1
    for line, row in enumerate(rows[2:], 3):
        if not row or not any(x.strip() for x in row):
            continue
        if len(row) != len(names):
            raise ValueError(f'CSV line {line}: column count mismatch')
        try:
            parsed = {n:int(row[i].strip(), bases[radix[i]]) for n,i in indexes.items()}
        except ValueError as exc:
            raise ValueError(f'CSV line {line}: invalid numeric value') from exc
        row_index = sample_count
        sample_count += 1
        if valid and not parsed[valid]:
            continue
        valid_count += 1
        decoded = {}
        for n in signals:
            v = (parsed[n] >> shift) & mask
            if signed and v & (1 << (bits-1)):
                v -= 1 << bits
            decoded[n] = v
            values[n].append(v)
        if event and parsed[event]:
            events.append({'sample_row':row_index, 'decoded':decoded})
    stats = {}
    for n,a in values.items():
        u = sorted(set(a))
        g = 0
        for x,y in zip(u,u[1:]):
            g = math.gcd(g,y-x)
        lowmask = (1 << min(5,bits))-1
        stats[n] = {'count':len(a),'min':min(a) if a else None,
                    'max':max(a) if a else None,'unique':len(u),
                    'code_spacing_gcd':g if a else None,
                    'constant':len(u)==1 if a else None,
                    'low5_patterns':sorted({v & lowmask for v in a}),
                    'low5_nonzero_count':sum(bool(v & lowmask) for v in a)}
    return {'source':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
            'captured_rows':sample_count,'valid_rows':valid_count,
            'decode':{'bits':bits,'shift':shift,'signed':signed,'valid':valid,'event':event},
            'signals':stats,'event_count':len(events) if event else None,'events':events,
            'limits':['Rows of latched registers are not independent SPI transactions.',
                      'Code spacing is not ENOB; constant channels cannot establish resolution.',
                      'Low bits moving does not certify full-resolution VDR operation.',
                      'Each nonzero event-valid row is counted; edge detection is not assumed.']}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('csv')
    p.add_argument('--signal',action='append',required=True)
    p.add_argument('--bits',type=int,default=14)
    p.add_argument('--shift',type=int,default=0)
    p.add_argument('--valid')
    p.add_argument('--event')
    p.add_argument('--signed',action='store_true')
    p.add_argument('--out')
    a = p.parse_args()
    if a.out and Path(a.out).resolve() == Path(a.csv).resolve():
        p.error('Output must not overwrite the source CSV')
    try:
        result = audit(a.csv,a.signal,a.bits,a.shift,a.valid,a.event,a.signed)
    except (ValueError,OSError) as exc:
        p.error(str(exc))
    data = json.dumps(result,ensure_ascii=False,indent=2)
    if a.out:
        Path(a.out).write_text(data,encoding='utf-8')
    else:
        print(data)


if __name__ == '__main__':
    main()
