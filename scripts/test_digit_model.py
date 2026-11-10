import unittest

from digit_model import argmax,integer_logits,softmax,train_classifier


class DigitModelTests(unittest.TestCase):
    def test_softmax_is_stable_and_normalized(self):
        values=softmax([10000,10001,9999])
        self.assertAlmostEqual(sum(values),1)
        self.assertEqual(argmax(values),1)

    def test_trains_small_separable_problem_reproducibly(self):
        rows=[([-1.0,1.0],0),([-0.5,1.0],0),([0.5,1.0],1),([1.0,1.0],1)]
        config={"seed":42,"epochs":20,"initial_learning_rate":0.1,"l2":0.0001}
        first=train_classifier(rows,config,classes=2)
        second=train_classifier(rows,config,classes=2)
        self.assertEqual(first,second)
        self.assertGreater(first[1][0],0)
        self.assertLess(first[0][0],0)

    def test_integer_bias_feature_and_signed_logits(self):
        model={"input_scale":1/127,"weights_int8":[[1,-2],[-1,2]],"multiplier":1,"shift":0}
        qa,acc,out=integer_logits([1.0,1.0],model)
        self.assertEqual(qa,[127,127])
        self.assertEqual(acc,[-127,127])
        self.assertEqual(out,[-127,127])
