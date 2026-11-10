import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from pvt import checked_library, fetch_library, parse_timing


class PvtEvidenceTests(unittest.TestCase):
    def test_negative_corner_is_recorded_without_claiming_closure(self):
        result=parse_timing("PVT_SETUP\nworst slack max -8.143339\nPVT_HOLD\nworst slack min 0.434713\n")
        self.assertEqual(result['setup_slack_ns'],-8.143339)
        self.assertFalse(result['timing_closed'])
        self.assertTrue(parse_timing("PVT_SETUP\nworst slack max 0\nPVT_HOLD\nworst slack min 0.09")['timing_closed'])

    def test_missing_nonfinite_and_invalid_slacks_are_rejected(self):
        for slack in ('nan','inf','-inf','invalid'):
            with self.subTest(slack=slack),self.assertRaises(RuntimeError):
                parse_timing(f"PVT_SETUP\nworst slack max {slack}\nPVT_HOLD\nworst slack min 0.1")
        with self.assertRaisesRegex(RuntimeError,'Missing hold'):
            parse_timing('PVT_SETUP\nworst slack max 1.0')

    def test_cached_library_tampering_is_rejected_without_network(self):
        with tempfile.TemporaryDirectory() as folder:
            cache=Path(folder)
            path=cache/'sky130_fd_sc_hd__test.lib'
            path.write_bytes(b'original')
            metadata={'sha256':hashlib.sha256(b'original').hexdigest(),'url':'https://example.invalid/not-used'}
            with patch('urllib.request.urlopen',side_effect=AssertionError('cache should be used')):
                self.assertEqual(fetch_library(cache,'test',metadata),path)
                path.write_bytes(b'tampered')
                with self.assertRaisesRegex(RuntimeError,'checksum mismatch'):
                    fetch_library(cache,'test',metadata)
            with self.assertRaises(RuntimeError): checked_library(path,metadata['sha256'])
