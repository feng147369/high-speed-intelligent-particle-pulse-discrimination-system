"""Behavioral regression with synthetic ILA captures, not hardware validation."""
import csv
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from ila_audit import audit


class AuditTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.p = Path(self.tmp.name)/'capture.csv'

    def capture(self, rows, radix='HEX'):
        with self.p.open('w',encoding='utf-8-sig',newline='') as f:
            w = csv.writer(f)
            w.writerow(['Sample in Buffer','sample','valid','event'])
            w.writerow(['Radix - UNSIGNED',radix,'HEX','HEX'])
            w.writerows(rows)

    def test_fixed_five_bits(self):
        self.capture([[i,format((i*32)<<2,'x'),'1','0'] for i in range(32)])
        r = audit(self.p,['sample'],14,2,'valid')['signals']['sample']
        self.assertEqual((r['code_spacing_gcd'],r['low5_patterns']), (32,[0]))

    def test_low_bits_and_invalid_cycle_exclusion(self):
        self.capture([[0,'ffff','0','1']]+[[i+1,format(i<<2,'x'),'1','0'] for i in range(32)])
        r = audit(self.p,['sample'],14,2,'valid','event')
        self.assertEqual((r['captured_rows'],r['valid_rows'],r['event_count']),(33,32,0))
        self.assertEqual(r['signals']['sample']['low5_patterns'],list(range(32)))
        self.assertEqual(r['signals']['sample']['code_spacing_gcd'],1)

    def test_held_peak_is_one_event(self):
        self.capture([[i,'43ac','1','1' if i==5 else '0'] for i in range(20)])
        r = audit(self.p,['sample'],16,0,'valid','event')
        self.assertEqual(r['event_count'],1)
        self.assertEqual(r['events'][0]['decoded']['sample'],17324)
        self.assertTrue(r['signals']['sample']['constant'])

    def test_signed_hex_and_decimal(self):
        for radix,values in [('HEX',['ffff','0000','0001']),('SIGNED',['-1','0','1'])]:
            self.capture([[i,x,'1','0'] for i,x in enumerate(values)],radix)
            r = audit(self.p,['sample'],16,0,signed=True)['signals']['sample']
            self.assertEqual((r['min'],r['max']),(-1,1))

    def test_no_valid_data(self):
        self.capture([[0,'0000','0','0']])
        r = audit(self.p,['sample'],valid='valid')['signals']['sample']
        self.assertIsNone(r['min'])
        self.assertEqual(r['low5_patterns'],[])

    def test_reject_malformed_and_missing_signal(self):
        self.capture([[0,'0000','1','0']])
        with self.assertRaises(ValueError): audit(self.p,['missing'])
        self.capture([[0,'xx','1','0']])
        with self.assertRaises(ValueError): audit(self.p,['sample'])

    def test_cli_json_and_source_preservation(self):
        self.capture([[0,'43ac','1','1']])
        original = self.p.read_bytes()
        out = self.p.with_suffix('.json')
        script = Path(__file__).with_name('ila_audit.py')
        args=[sys.executable,str(script),str(self.p),'--signal','sample','--bits','16','--event','event']
        subprocess.run(args+['--out',str(out)],check=True,capture_output=True)
        self.assertEqual(json.loads(out.read_text())['event_count'],1)
        self.assertEqual(self.p.read_bytes(),original)
        blocked=subprocess.run(args+['--out',str(self.p)],capture_output=True)
        self.assertNotEqual(blocked.returncode,0)
        self.assertEqual(self.p.read_bytes(),original)


if __name__ == '__main__':
    unittest.main(verbosity=2)
