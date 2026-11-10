import unittest

from postroute import parse_activity,parse_power


class PostrouteReportTests(unittest.TestCase):
    def test_measured_annotation_fraction(self):
        result=parse_activity("vcd 53754\nunannotated 2\n")
        self.assertGreater(result["fraction"],0.9999)

    def test_missing_or_low_annotation_is_rejected(self):
        for text in ("report unavailable","vcd 0\nunannotated 12\n","vcd 50\nunannotated 10\n"):
            with self.assertRaises(RuntimeError): parse_activity(text)

    def test_power_units_and_invalid_results(self):
        self.assertAlmostEqual(parse_power("Total 2.0e-2 6.0e-3 9e-8 2.6e-2")['total_W'],0.026)
        for text in ("empty","Total 0 0 0 0","Total nan 0 0 1","Total -1 0 0 1"):
            with self.assertRaises(RuntimeError): parse_power(text)
