
"""Unit tests for tiled INT8 GEMM and symmetric INT8 quantization."""

import random
import unittest

from tiled_gemm import (
    tiled_gemm_int8,
    quantize_symmetric_int8,
    quantized_matmul,
)


def direct_matmul(a, b):
    """Independent mathematical reference without tiling."""
    m, k, n = len(a), len(b), len(b[0])

    return [
        [sum(a[i][p] * b[p][j] for p in range(k))
         for j in range(n)]
        for i in range(m)
    ]


class TestTiledGEMM(unittest.TestCase):

    def test_rectangular_and_edge_padding(self):
        rng = random.Random(1234)

        shapes = [
            (1, 1, 1),
            (3, 5, 7),
            (4, 4, 4),
            (7, 9, 5),
            (8, 8, 8),
            (9, 2, 11),
        ]

        for m, k, n in shapes:
            with self.subTest(shape=(m, k, n)):
                a = [
                    [rng.randint(-128, 127) for _ in range(k)]
                    for _ in range(m)
                ]

                b = [
                    [rng.randint(-128, 127) for _ in range(n)]
                    for _ in range(k)
                ]

                self.assertEqual(
                    tiled_gemm_int8(a, b),
                    direct_matmul(a, b)
                )

    def test_multi_tile_accumulation_and_extremes(self):        # 9-element dot product requires three K tiles.
        a = [[-128] * 9 for _ in range(6)]
        b = [[-128] * 5 for _ in range(9)]

        expected = [
            [9 * 16384] * 5
            for _ in range(6)
        ]

        self.assertEqual(tiled_gemm_int8(a, b), expected)

    def test_mixed_signs(self):
        a = [
            [-128, 127, -1, 0, 2],
            [1, -2, 3, -4, 5],
        ]

        b = [
            [1, -1],
            [2, -2],
            [3, -3],
            [4, -4],
            [5, -5],
        ]

        self.assertEqual(
            tiled_gemm_int8(a, b),
            direct_matmul(a, b)
        )

    def test_quantization_zero_and_clipping(self):
        q, scale = quantize_symmetric_int8(
            [[0.0, 0.0]]
        )

        self.assertEqual(q, [[0, 0]])
        self.assertEqual(scale, 1.0)

        q, scale = quantize_symmetric_int8(
            [[-10.0, 0.0, 10.0]]
        )

        self.assertEqual(q, [[-127, 0, 127]])
        self.assertAlmostEqual(scale, 10.0 / 127.0)

    def test_quantized_matrix_multiplication(self):
        a = [
            [1.0, -2.0],
            [3.0, 4.0],
        ]

        b = [
            [1.0, 0.0],
            [0.0, 1.0],
        ]

        recovered, integer_result, (sa, sb) = (
            quantized_matmul(a, b)
        )

        self.assertEqual(len(integer_result), 2)
        self.assertGreater(sa, 0.0)
        self.assertGreater(sb, 0.0)

        for i in range(2):
            for j in range(2):
                self.assertAlmostEqual(
                    recovered[i][j],
                    a[i][j],
                    delta=0.04
                )

    def test_bad_inputs(self):
        bad_calls = [
            ([], [[1]]),
            ([[1, 2], [3]], [[1], [2]]),
            ([[129]], [[1]]),
            ([[1, 2]], [[1, 2]]),
        ]

        for a, b in bad_calls:
            with self.subTest(a=a, b=b):
                with self.assertRaises(ValueError):
                    tiled_gemm_int8(a, b)

        with self.assertRaises(ValueError):
            tiled_gemm_int8([[1]], [[1]], tile=1)


if __name__ == "__main__":
    unittest.main()
