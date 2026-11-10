"""Independent arithmetic, paired evaluation and performance-accounting checks."""
import unittest
from pathlib import Path
import tempfile
import json
import shutil
import subprocess

from accuracy_study import integer_layer, paired_metrics, quantized_layer
from cpu_benchmark import gemm
from design_space import tile_performance
from estimate_energy import vcd_duration


class ComparisonTests(unittest.TestCase):
    def test_signed_rectangular_gemm(self):
        self.assertEqual(gemm([[1,-2,3],[-128,127,0]],[[2,-1],[3,2],[-1,4]]),
                         [[-7,7],[125,382]])

    def test_paired_loss_can_be_negative(self):
        m=paired_metrics([0,1,2,3],[0,0,2,0],[0,1,0,3])
        self.assertEqual(m["float_correct_int8_wrong"],1)
        self.assertEqual(m["float_wrong_int8_correct"],2)
        self.assertEqual(m["accuracy_loss_percentage_points"],-25)
        with self.assertRaises(ValueError): paired_metrics([0],[0],[])

    def test_quantized_bias_and_relu(self):
        model=quantized_layer([[1.0,-1.0]],1.0,1.0)
        acc,out=integer_layer([2,3],model,True)
        self.assertLess(acc[0],0)
        self.assertEqual(out,[0])

    def test_peak_is_not_sustained_useful_throughput(self):
        m=tile_performance(4,50)
        self.assertEqual(m["acceptance_interval_cycles"],11)
        self.assertAlmostEqual(m["useful_gmac_s"],64*50e6/11/1e9)
        self.assertEqual(m["peak_gmac_s"],0.8)
        with self.assertRaises(ValueError): tile_performance(4,float("nan"))

    def test_energy_time_units_and_invalid_trace(self):
        with tempfile.TemporaryDirectory() as directory:
            trace=Path(directory)/"activity.vcd"
            trace.write_text("$timescale\n10 ps\n$end\n#0\n#1000\n")
            self.assertAlmostEqual(vcd_duration(trace),1e-8)
            trace.write_text("$timescale 1ns $end\n#10\n#5\n")
            with self.assertRaises(ValueError): vcd_duration(trace)

    def test_native_kernel_signed_extremes_tails_rounding_and_false_pass(self):
        compiler=shutil.which("clang++") or shutil.which("g++")
        if compiler is None:self.skipTest("Native C++ compiler unavailable")
        with tempfile.TemporaryDirectory() as directory:
            executable=Path(directory)/"cpu_gemm"
            source=Path(__file__).resolve().parents[1]/"bench/cpu_gemm.cpp"
            subprocess.run([compiler,"-O3","-std=c++17","-Wall","-Wextra","-Werror",str(source),"-o",str(executable)],
                           check=True,capture_output=True)
            # Two worst-case signed rows test widening before pair addition;
            # the 17th element exercises the scalar tail. A second job checks ties.
            text="\n".join(["2","extreme 2 17 1 1 1 0",
                            " ".join(map(str,[-128]*17+[127]*17))," ".join(["-128"]*17),
                            "278528 -276352","127 -128","ties 2 1 1 1 1 0","3 -3","1","3 -3","2 -2"])+"\n"
            vectors=Path(directory)/"vectors.txt"
            vectors.write_text(text)
            result=subprocess.run([str(executable),str(vectors),"--check-only"],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(json.loads(result.stdout)["validated_jobs"],2)
            vectors.write_text(text.replace("278528 -276352","278527 -276352"))
            result=subprocess.run([str(executable),str(vectors),"--check-only"],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn("Reference mismatch",result.stderr)
