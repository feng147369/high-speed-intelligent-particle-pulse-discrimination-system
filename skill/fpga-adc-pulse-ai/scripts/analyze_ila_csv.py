#!/usr/bin/env python3
"""Read Vivado ILA CSV without changing it. Standard library only."""
import argparse
import csv
import json
import math
import re
from pathlib import Path

VECTOR = re.compile(r"\[(\d+):0\]$")
ADC = re.compile(r"^(.*)_sample([01])\[(\d+):0\]$")

def analyze(path, sample_rate=None, threshold=None, pairs=None, signed_adc=False):
    if sample_rate is not None and sample_rate <= 0:
        raise ValueError("sample rate must be positive")
    with Path(path).open(encoding="utf-8-sig", newline="") as f:
        rows = list(csv.reader(f))
    if len(rows) < 2 or len(set(rows[0])) != len(rows[0]):
        raise ValueError("CSV needs unique headers and data")
    headers = rows.pop(0)
    radix = ["UNSIGNED"] * len(headers)
    if rows and rows[0][0].startswith("Radix"):
        radix = [x.replace("Radix - ", "").strip().upper() for x in rows.pop(0)]
        if len(radix) != len(headers):
            raise ValueError("Radix/header length mismatch")
    if not rows:
        raise ValueError("CSV contains no samples")
    signals, unknown = {}, {}
    for j, name in enumerate(headers):
        width_match = VECTOR.search(name)
        width = int(width_match[1]) + 1 if width_match else None
        values, bad = [], []
        base = {"HEX":16, "BINARY":2, "OCTAL":8, "SIGNED":10, "UNSIGNED":10}.get(radix[j])
        if base is None:
            raise ValueError("Unsupported Radix: " + radix[j])
        for row_index, row in enumerate(rows):
            if len(row) != len(headers):
                raise ValueError("Column mismatch at sample " + str(row_index))
            token = row[j].strip()
            token_body = token.lower().removeprefix("0x")
            if not token or re.search(r"[xz?]", token_body):
                values.append(None); bad.append(row_index); continue
            value = int(token, base)
            if width is not None and (radix[j] == "SIGNED" or (signed_adc and ADC.match(name))):
                if value >= 0:
                    value &= (1 << width) - 1
                    if value & (1 << (width - 1)):
                        value -= 1 << width
            values.append(value)
        signals[name] = values
        unknown[name] = bad
    inferred = {}
    for name in headers:
        match = ADC.match(name)
        if match:
            inferred.setdefault((match[1],match[3]), {})[match[2]] = name
    chosen = list(pairs) if pairs else [tuple(p[k] for k in ("0","1")) for p in inferred.values() if "0" in p and "1" in p]
    result = {"source":str(Path(path).resolve()), "rows":len(rows), "columns":{}, "pairs":[],
              "limits":["bit activity is not ENOB", "short analog captures do not prove zero lost samples or bit errors"]}
    for name, values in signals.items():
        valid = [v for v in values if v is not None]
        entry = {"valid":len(valid), "unknown":len(unknown[name]), "unknown_first_indices":unknown[name][:10],
                 "radix":radix[headers.index(name)], "unique":len(set(valid))}
        if valid:
            entry.update(min=min(valid), max=max(valid))
            if ADC.match(name):
                match=VECTOR.search(name); width=int(match[1])+1
                spacing=0
                origin=min(valid)
                for v in valid:
                    spacing=math.gcd(spacing,v-origin)
                entry.update(low5_patterns=sorted(set(v & 31 for v in valid)),
                             low5_nonzero=sum(bool(v & 31) for v in valid), code_spacing_gcd=spacing,
                             signed_positive_rail=sum((v & ((1<<width)-1)) == (1<<(width-1))-1 for v in valid),
                             signed_negative_rail=sum((v & ((1<<width)-1)) == (1<<(width-1)) for v in valid))
        result["columns"][name]=entry
    for a,b in chosen:
        if a not in signals or b not in signals:
            raise ValueError("Pair signal missing")
        stream=[v for pair in zip(signals[a],signals[b]) for v in pair]
        differences=[abs(y-x) for x,y in zip(stream,stream[1:]) if x is not None and y is not None]
        p={"signals":[a,b], "samples":len(stream), "unknown":sum(v is None for v in stream),
           "max_adjacent_difference":max(differences) if differences else None}
        if sample_rate:
            p["duration_seconds"]=len(stream)/sample_rate
        if threshold is not None:
            segments=[]; start=None
            for i,v in enumerate(stream):
                if v is None:
                    start=None
                elif v > threshold:
                    if start is None: start=i
                elif start is not None:
                    if start>0 and stream[start-1] is not None:
                        segments.append((start,i))
                    start=None
            p["threshold"]=threshold
            p["complete_pulses"]=[{"start":s,"width_samples":e-s,"peak":max(stream[s:e])} for s,e in segments]
            p["rise_intervals_samples"]=[b[0]-a[0] for a,b in zip(segments,segments[1:])]
            if sample_rate:
                p["rise_intervals_seconds"]=[v/sample_rate for v in p["rise_intervals_samples"]]
        result["pairs"].append(p)
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input")
    parser.add_argument("--sample-rate",type=float)
    parser.add_argument("--pulse-threshold",type=float)
    parser.add_argument("--pair",nargs=2,action="append")
    parser.add_argument("--signed-adc",action="store_true")
    parser.add_argument("--output")
    args=parser.parse_args()
    if args.output and Path(args.output).resolve()==Path(args.input).resolve():
        parser.error("output must not overwrite input")
    try:
        result=analyze(args.input,args.sample_rate,args.pulse_threshold,args.pair,args.signed_adc)
    except (ValueError,OSError) as exc:
        parser.error(str(exc))
    text=json.dumps(result,ensure_ascii=False,indent=2)
    if args.output:
        Path(args.output).write_text(text,encoding="utf-8")
    else:
        print(text)
if __name__=="__main__":
    main()
