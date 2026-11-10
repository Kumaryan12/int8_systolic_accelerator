import unittest

from quantization import fixed_point_scale, requantize_int


class OutputQuantizationTests(unittest.TestCase):
    def test_signed_half_ties_round_away_from_zero(self):
        for value, expected in ((1,1), (-1,-1), (3,2), (-3,-2), (5,3), (-5,-3)):
            self.assertEqual(requantize_int(value, 1, 1), expected)

    def test_saturation_zero_point_and_relu(self):
        self.assertEqual(requantize_int(10000, 1, 0), 127)
        self.assertEqual(requantize_int(-10000, 1, 0), -128)
        self.assertEqual(requantize_int(-10000, 1, 0, zero_point=-7, relu=True), -7)
        self.assertEqual(requantize_int(0, 0, 63, zero_point=11), 11)

    def test_fixed_point_scale_accuracy(self):
        for scale in (0.0001, 0.125, 0.9, 1.0, 12.5):
            multiplier, shift = fixed_point_scale(scale)
            self.assertAlmostEqual(multiplier/(2**shift), scale, delta=scale*2e-9)

    def test_invalid_formats(self):
        for args in ((1,-1,0), (1,2**31,0), (1,1,64), (1,1,0,128), (1.5,1,0)):
            with self.assertRaises(ValueError):
                requantize_int(*args)
        for scale in (0, -1, float("nan"), float("inf"), 1e-30, 1e30):
            with self.assertRaises(ValueError):
                fixed_point_scale(scale)
