# Trained digit classifier through the RTL

```sh
make model
```

This downloads the checksum-pinned UCI Optical Recognition of Handwritten
Digits archive, trains a small linear softmax classifier in ordinary Python,
quantizes it, evaluates the official test split, and runs **every test image**
through the memory-backed accelerator and integer postprocessor. No NumPy,
scikit-learn, PyTorch, GPU, or downloaded pretrained weights are required.
Raw data and generated model weights stay in ignored `build/` directories.

## Data and reproducibility

The supplied training set has 3,823 records and the supplied test set has
1,797, with 64 pixel-count features in 0..16 and ten digit classes. The supplied
split separates contributing writers; this project does not mix or resplit it.
The [source dataset](https://doi.org/10.24432/C50P49) is by E. Alpaydin and
C. Kaynak (1998), licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Dataset attribution,
archive/member checksums and fixed training parameters are in `dataset.json`.
The transformations here are pixel normalization, bias-feature augmentation,
training and quantization.

Normalize each pixel by the published maximum 16 and append a constant 1
feature. Thirty-five fixed-seed SGD epochs train 650 weights (65 inputs × ten
classes). The last row of the matrix implements bias through an ordinary MAC
on the constant feature, so bias is included in the RTL computation. Input
scale is fixed at 1/127; the weight and output scales use training data only.
The official test set is used only for evaluation after training/calibration.

Inference batches four images as a 4×65 by 65×10 GEMM. Output logits are
requantized to signed INT8 without ReLU, and the host takes their argmax.
The last batch has three zero-padded rows. RTL checks include 18,000
accumulator/INT8 pairs: 17,970 real logits plus 30 padding logits. Tags wrap
after 256 batches, exercising reuse without confusing live jobs.

## Recorded result

| Evaluation on all 1,797 official test images | Correct | Accuracy |
|---|---:|---:|
| Floating-point classifier | 1,707 | 94.9917% |
| Quantized integer accumulators | 1,705 | 94.8804% |
| INT8 logits, Python reference | 1,708 | 95.0473% |
| INT8 logits from actual RTL | 1,708 | 95.0473% |

All RTL accumulators and quantized outputs match Python exactly. The small
accuracy differences reflect this fixed model and rounding, not a claim that
quantization improves accuracy generally. No test-example selection or
test-based calibration is used.

The run exports `trained_model.json`, `model_metrics.json`, vectors, outputs,
logs and a source/tool summary. A manually triggered **Trained model** GitHub
workflow repeats the complete experiment on a clean runner. Ordinary
`make verify` runs small offline training/quantization unit tests and the
synthetic layer; it does not require downloading this dataset on every push.

This is a compact task-level demonstration. It reloads weights for each
four-image batch, uses a host argmax, and is not an optimized CNN or a device
speed benchmark. Timing/area results for the default physical 3×5×7 top do not
apply to this different 4×65×10 elaboration.
