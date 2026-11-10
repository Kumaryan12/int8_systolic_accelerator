"""Check that the regression gate rejects false passes and preserves failures."""

from argparse import Namespace
import contextlib
import io
import json
from pathlib import Path
import sys
import subprocess
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
        self.regression = Regression(Namespace(suite="sim", seeds=[42], random_cases=1))

    def test_synthesis_preflight_rejects_old_or_unknown_tool_versions(self):
        with patch.object(self.regression,"tool"):
            for version,accepted in (("Yosys 0.33",False),("unrecognized",False),
                                     ("Yosys 0.68+42",True),("Yosys 0.70 (Release)",True)):
                self.regression.report["tools"]["yosys"]={"version":version}
                if accepted:self.regression.require_synthesis_tool()
                else:
                    with self.assertRaisesRegex(RuntimeError,"Yosys 0.68"):
                        self.regression.require_synthesis_tool()

    def command(self, code):
        return [sys.executable, "-c", code]

    def test_zero_exit_without_pass_marker_is_failure(self):
        with self.assertRaisesRegex(RuntimeError, "required result"):
            self.regression.run("missing", self.command("print('simulation stopped')"), ["PASS"])
        report = json.loads((self.regression.directory / "summary.json").read_text())
        self.assertEqual(report["steps"][-1]["status"], "FAIL")

    def test_zero_uvm_summary_is_not_an_error(self):
        self.regression.run("summary", self.command("print('PASS\\nUVM_ERROR : 0\\nUVM_FATAL : 0')"), ["PASS"])
        self.assertEqual(self.regression.report["steps"][-1]["status"], "PASS")

    def test_uvm_error_rejected_even_with_pass_marker(self):
        with self.assertRaisesRegex(RuntimeError, "UVM error"):
            self.regression.run("uvm_error", self.command("print('PASS\\nUVM_ERROR test.sv(5): mismatch')"), ["PASS"])

    def test_nonzero_exit_preserves_log_and_failure(self):
        with self.assertRaisesRegex(RuntimeError, "exited with 3"):
            self.regression.run("failure", self.command("print('mismatch'); raise SystemExit(3)"))
        self.assertIn("mismatch", (self.regression.directory / "failure.log").read_text())
        self.assertEqual(self.regression.report["steps"][-1]["returncode"], 3)

    def test_timeout_records_failure(self):
        with self.assertRaises(subprocess.TimeoutExpired):
            self.regression.run("timeout", self.command("import time; time.sleep(30)"), timeout=0.05)
        self.assertEqual(self.regression.report["steps"][-1]["status"], "FAIL")


if __name__ == "__main__":
    unittest.main()
