"""Check that the regression gate rejects false passes and preserves failures."""

from argparse import Namespace
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from regression import Regression


class RegressionGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root_patch = patch("regression.ROOT", Path(self.temp.name))
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)
        self.silence = contextlib.ExitStack()
        self.silence.enter_context(contextlib.redirect_stdout(io.StringIO()))
        self.silence.enter_context(contextlib.redirect_stderr(io.StringIO()))
        self.addCleanup(self.silence.close)
        self.run = Regression(Namespace(suite="sim", seeds=[42], random_cases=1))

    def command(self, code):
        return [sys.executable, "-c", code]

    def test_zero_exit_without_pass_marker_is_failure(self):
        with self.assertRaisesRegex(RuntimeError, "required result"):
            self.run.run("missing", self.command("print('simulation stopped')"), ["PASS"])
        report = json.loads((self.run.directory / "summary.json").read_text())
        self.assertEqual(report["steps"][-1]["status"], "FAIL")

    def test_zero_uvm_summary_is_not_an_error(self):
        self.run.run("summary", self.command("print('PASS\\nUVM_ERROR : 0\\nUVM_FATAL : 0')"), ["PASS"])
        self.assertEqual(self.run.report["steps"][-1]["status"], "PASS")

    def test_uvm_error_rejected_even_with_pass_marker(self):
        with self.assertRaisesRegex(RuntimeError, "UVM error"):
            self.run.run("uvm_error", self.command("print('PASS\\nUVM_ERROR test.sv(5): mismatch')"), ["PASS"])

    def test_nonzero_exit_preserves_log_and_failure(self):
        with self.assertRaisesRegex(RuntimeError, "exited with 3"):
            self.run.run("failure", self.command("print('mismatch'); raise SystemExit(3)"))
        self.assertIn("mismatch", (self.run.directory / "failure.log").read_text())
        self.assertEqual(self.run.report["steps"][-1]["returncode"], 3)


if __name__ == "__main__":
    unittest.main()
