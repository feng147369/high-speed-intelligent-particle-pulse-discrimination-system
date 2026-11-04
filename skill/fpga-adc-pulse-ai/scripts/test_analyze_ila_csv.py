import csv
import tempfile
import unittest
from pathlib import Path
from analyze_ila_csv import analyze

A="cha_sample0[13:0]"
B="cha_sample1[13:0]"

class AnalysisTests(unittest.TestCase):
    def capture(self, rows, radix=("UNSIGNED","UNSIGNED"), headers=(A,B)):
        temp=tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        path=Path(temp.name)/"ila.csv"
        with path.open("w",newline="",encoding="utf-8-sig") as f:
            w=csv.writer(f); w.writerow(headers)
            w.writerow(["Radix - "+radix[0],radix[1]])
            w.writerows(rows)
        return path

    def test_low5_locked(self):
        r=analyze(self.capture([[32,64],[96,128]]))
        self.assertEqual(r["columns"][A]["low5_patterns"],[0])
        self.assertEqual(r["columns"][A]["code_spacing_gcd"],64)

    def test_all_low5_patterns(self):
        r=analyze(self.capture([[i,i] for i in range(32)]))
        self.assertEqual(len(r["columns"][A]["low5_patterns"]),32)

    def test_hex_signed_adc(self):
        r=analyze(self.capture([["1fff","2000"],["3fff","0000"]],("HEX","HEX")),signed_adc=True)
        self.assertEqual(r["columns"][A]["min"],-1)
        self.assertEqual(r["columns"][B]["min"],-8192)
        self.assertEqual(r["columns"][B]["signed_negative_rail"],1)

    def test_signed_decimal(self):
        r=analyze(self.capture([[-2,-1],[0,1]],("SIGNED","SIGNED")))
        self.assertEqual(r["columns"][A]["min"],-2)
        self.assertEqual(r["pairs"][0]["max_adjacent_difference"],1)

    def test_interleave_and_period(self):
        # stream 0,10,10,0,0,10,10,0
        r=analyze(self.capture([[0,10],[10,0],[0,10],[10,0]]),sample_rate=2,threshold=5)
        p=r["pairs"][0]
        self.assertEqual(p["samples"],8)
        self.assertEqual(p["duration_seconds"],4)
        self.assertEqual(p["rise_intervals_samples"],[4])
        self.assertEqual([s["width_samples"] for s in p["complete_pulses"]],[2,2])

    def test_unknown_not_bridged(self):
        r=analyze(self.capture([[1,"X"],[100,101]]))
        self.assertEqual(r["pairs"][0]["samples"],4)
        self.assertEqual(r["pairs"][0]["unknown"],1)
        self.assertEqual(r["pairs"][0]["max_adjacent_difference"],1)

    def test_no_time_without_clock(self):
        r=analyze(self.capture([[0,1],[2,3]]))
        self.assertNotIn("duration_seconds",r["pairs"][0])

    def test_bad_shape_fails(self):
        with self.assertRaises(ValueError):
            analyze(self.capture([[1,2,3]]))

    def test_missing_pair_fails(self):
        with self.assertRaises(ValueError):
            analyze(self.capture([[1,2]]),pairs=[(A,"absent")])

    def test_binary(self):
        r=analyze(self.capture([["0010","0011"]],("BINARY","BINARY")))
        self.assertEqual(r["columns"][A]["min"],2)
        self.assertEqual(r["columns"][B]["max"],3)

    def test_register_hex_not_signed_adc(self):
        r=analyze(self.capture([["dc","db"]],("HEX","HEX"),("ab_chip_id[7:0]","cd_chip_id[7:0]")),signed_adc=True)
        self.assertEqual(r["columns"]["ab_chip_id[7:0]"]["min"],220)
        self.assertEqual(r["pairs"],[])

    def test_censored_pulse_excluded(self):
        r=analyze(self.capture([[10,0],[0,10]]),threshold=5)
        self.assertEqual(r["pairs"][0]["complete_pulses"],[])

if __name__=="__main__":
    unittest.main(verbosity=2)
