"""Test the mathematical and cycle-accurate Python models (NOT the RTL)."""
import random
import unittest
from reference import matmul_int8, systolic_cycle_model


class SystolicScheduleTests(unittest.TestCase):
    def test_directed(self):
        n = 4
        cases = [
            ([[0]*n for _ in range(n)], [[0]*n for _ in range(n)]),
            ([[int(i == j) for j in range(n)] for i in range(n)],
             [[int(i == j) for j in range(n)] for i in range(n)]),
            ([[127]*n for _ in range(n)], [[127]*n for _ in range(n)]),
            ([[-128]*n for _ in range(n)], [[-128]*n for _ in range(n)]),
        ]
        for a, b in cases:
            self.assertEqual(matmul_int8(a, b), systolic_cycle_model(a, b))

    def test_random(self):
        rng = random.Random(2026)
        for n in (2, 3, 4, 8):
            for _ in range(200):
                a = [[rng.randint(-128, 127) for _ in range(n)] for _ in range(n)]
                b = [[rng.randint(-128, 127) for _ in range(n)] for _ in range(n)]
                self.assertEqual(matmul_int8(a, b), systolic_cycle_model(a, b))

    def test_accumulator_bounds(self):
        n = 4
        hi = matmul_int8([[-128]*n for _ in range(n)],
                         [[-128]*n for _ in range(n)])
        self.assertEqual(hi[0][0], 65536)
        self.assertLess(65536, 2**17)  # signed 18-bit positive maximum


if __name__ == '__main__':
    unittest.main()
