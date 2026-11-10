import json
from pathlib import Path
import tempfile
import unittest

from physical_flow import extract_metrics


class PhysicalGateTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.logs=self.root/"logs/sky130hd/int8_memory_gemm/base"
        self.logs.mkdir(parents=True)
        self.finish={"finish__timing__setup__ws":1.0,"finish__timing__hold__ws":0.1,
                     "finish__design__instance__area__stdcell":20,"finish__design__instance__count__stdcell":10,
                     "finish__design__die__area":100,"finish__design__core__area":80,
                     "finish__timing__fmax":100e6,"finish__power__total":0.01}
        self.write()

    def write(self,drc=0,proof="Circuits are IDENTICAL"):
        (self.logs/"5_2_route.json").write_text(json.dumps({"detailedroute__route__drc_errors":drc}))
        (self.logs/"6_report.json").write_text(json.dumps(self.finish))
        (self.logs/"6_final_lec_check.log").write_text(proof)

    def test_valid_routed_metrics(self):
        self.assertTrue(extract_metrics(self.root)["implementation_lec_passed"])

    def test_drc_failure_is_rejected(self):
        self.write(drc=1)
        with self.assertRaisesRegex(RuntimeError,"violations"): extract_metrics(self.root)

    def test_negative_timing_and_missing_schema_rejected(self):
        self.finish["finish__timing__setup__ws"]=-0.1
        self.write()
        with self.assertRaisesRegex(RuntimeError,"violations"): extract_metrics(self.root)
        self.finish.pop("finish__timing__hold__ws")
        self.write()
        with self.assertRaisesRegex(RuntimeError,"Missing"): extract_metrics(self.root)

    def test_failed_equivalence_is_rejected(self):
        self.write(proof="SAT counterexample")
        with self.assertRaisesRegex(RuntimeError,"equivalence"): extract_metrics(self.root)
