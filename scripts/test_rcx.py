import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from rcx import load_rc_corners, spef_metrics

SPEF='''*SPEF "ieee 1481-1999"
*DESIGN "axi_gemm"
*C_UNIT 1 PF
*R_UNIT 1 OHM
*D_NET *1 1.2
*CONN
*I *1:I I
*CAP
1 *1:I 1.2
*RES
1 *1:I *2:O 10
*END
*D_NET *2 0.8
*RES
1 *2:I *3:O 5
*END
'''


class RcEvidenceTests(unittest.TestCase):
    def test_spef_network_units_and_totals(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'test.spef';path.write_text(SPEF)
            result=spef_metrics(path)
            self.assertEqual(result['nets'],2)
            self.assertEqual(result['resistance_segments'],2)
            self.assertAlmostEqual(result['sum_dnet_capacitance_pF'],2)
            self.assertAlmostEqual(result['sum_segment_resistance_ohm'],15)

    def test_missing_network_bad_units_and_nonfinite_values_fail(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'test.spef'
            for text in ('',SPEF.replace('1 PF','1 FF'),SPEF.replace('*1 1.2','*1 nan'),
                         SPEF.replace('*3:O 5','*3:O inf'),SPEF.replace('*3:O 5','*3:O -5')):
                path.write_text(text)
                with self.subTest(text=text),self.assertRaises(RuntimeError):spef_metrics(path)

    def test_layout_corner_completeness_and_artifact_tampering(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);layout=root/'layout';layout.mkdir()
            odb=layout/'6_final.odb';odb.write_bytes(b'original layout')
            corners={}
            for corner in ('min','nom','max'):
                path=root/f'{corner}.spef';path.write_text(SPEF)
                corners[corner]={'file':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
            rc={'image':'pinned','physical_odb_sha256':hashlib.sha256(odb.read_bytes()).hexdigest(),'corners':corners}
            summary={'status':'PASS','suite':'rcx','rcx':rc}
            def save():(root/'summary.json').write_text(json.dumps(summary))
            save()
            self.assertEqual(set(load_rc_corners(root,layout,{'image':'pinned'})[0]),{'min','nom','max'})
            with self.assertRaisesRegex(RuntimeError,'image/layout'):
                load_rc_corners(root,layout,{'image':'different'})
            maximum=corners.pop('max');save()
            with self.assertRaisesRegex(RuntimeError,'Incomplete'):
                load_rc_corners(root,layout,{'image':'pinned'})
            corners['max']=maximum;save();(root/'max.spef').write_text('modified')
            with self.assertRaisesRegex(RuntimeError,'artifact changed'):
                load_rc_corners(root,layout,{'image':'pinned'})
