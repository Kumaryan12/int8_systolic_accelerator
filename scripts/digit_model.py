"""Small reproducible softmax classifier and INT8 export, using only stdlib."""

import csv
import hashlib
import io
import json
import math
from pathlib import Path
import random
import time
from urllib.request import urlopen
import zipfile

from quantization import fixed_point_scale, requantize_int


def softmax(scores):
    offset=max(scores)
    exponents=[math.exp(value-offset) for value in scores]
    total=sum(exponents)
    return [value/total for value in exponents]


def scores_for(features,weights):
    return [sum(x*w for x,w in zip(features,row)) for row in weights]


def train_classifier(rows,config,classes=10):
    width=len(rows[0][0])
    weights=[[0.0]*width for _ in range(classes)]
    order=list(range(len(rows)))
    rng=random.Random(config["seed"])
    for epoch in range(config["epochs"]):
        rng.shuffle(order)
        rate=config["initial_learning_rate"]/math.sqrt(1+epoch/5)
        for index in order:
            features,label=rows[index]
            probabilities=softmax(scores_for(features,weights))
            for cls,row in enumerate(weights):
                gradient=probabilities[cls]-(1.0 if cls==label else 0.0)
                for feature,x in enumerate(features):
                    row[feature]-=rate*(gradient*x+config["l2"]*row[feature])
        if (epoch+1)%5==0:
            print(f"  TRAIN epoch {epoch+1}/{config['epochs']}",flush=True)
    return weights


def read_dataset(root):
    manifest=json.loads((root/"examples/digits/dataset.json").read_text())
    cache=root/"build/data_cache"
    cache.mkdir(exist_ok=True,parents=True)
    path=cache/"optdigits_0d7b054fea01.zip"
    if not path.exists():
        data=urlopen(manifest["url"],timeout=60).read()
        if hashlib.sha256(data).hexdigest()!=manifest["sha256"]:
            raise RuntimeError("Dataset download checksum differs from pinned source")
        path.write_bytes(data)
    data=path.read_bytes()
    if hashlib.sha256(data).hexdigest()!=manifest["sha256"]:
        raise RuntimeError("Cached dataset checksum mismatch")
    archive=zipfile.ZipFile(io.BytesIO(data))
    splits={}
    for split,description in manifest["members"].items():
        raw=archive.read(description["name"])
        if hashlib.sha256(raw).hexdigest()!=description["sha256"]:
            raise RuntimeError(f"Dataset member checksum mismatch: {split}")
        records=[]
        for fields in csv.reader(io.StringIO(raw.decode("ascii"))):
            values=list(map(int,fields))
            if len(values)!=65 or any(not 0<=x<=16 for x in values[:64]) or not 0<=values[64]<10:
                raise RuntimeError("Unexpected digit dataset schema")
            records.append(([x/16 for x in values[:64]]+[1.0],values[64]))
        if len(records)!=description["rows"]:
            raise RuntimeError("Unexpected dataset row count")
        splits[split]=records
    return manifest,splits


def argmax(values):
    return max(range(len(values)),key=values.__getitem__)


def export_model(weights,training_rows):
    scale_a=1/127
    scale_b=max(abs(x) for row in weights for x in row)/127
    quantized=[[max(-127,min(127,round(x/scale_b))) for x in row] for row in weights]
    # Output calibration uses training data only, never the official test set.
    scale_out=max(abs(score) for features,_ in training_rows for score in scores_for(features,weights))/120
    multiplier,shift=fixed_point_scale(scale_a*scale_b/scale_out)
    return {"weights_float":weights,"weights_int8":quantized,"input_scale":scale_a,"weight_scale":scale_b,
            "output_scale":scale_out,"multiplier":multiplier,"shift":shift,"parameters":len(weights)*len(weights[0])}


def integer_logits(features,model):
    qa=[round(x/model["input_scale"]) for x in features]
    accum=[sum(x*w for x,w in zip(qa,row)) for row in model["weights_int8"]]
    quantized=[requantize_int(value,model["multiplier"],model["shift"]) for value in accum]
    return qa,accum,quantized


def evaluate(rows,weights,model):
    fp_correct=integer_correct=output_correct=agreements=clipped=0
    for features,label in rows:
        fp=argmax(scores_for(features,weights))
        _,accum,quantized=integer_logits(features,model)
        int_prediction=argmax(accum)
        out_prediction=argmax(quantized)
        fp_correct+=(fp==label)
        integer_correct+=(int_prediction==label)
        output_correct+=(out_prediction==label)
        agreements+=(fp==out_prediction)
        clipped+=sum(x in (-128,127) for x in quantized)
    count=len(rows)
    return {"samples":count,"float_correct":fp_correct,"integer_correct":integer_correct,"int8_output_correct":output_correct,
            "float_accuracy":fp_correct/count,"integer_accuracy":integer_correct/count,"int8_output_accuracy":output_correct/count,
            "float_int8_prediction_agreement":agreements/count,"saturated_output_logits":clipped}


def packed_values(values,width):
    mask=(1<<width)-1
    value=sum((x&mask)<<(width*i) for i,x in enumerate(values))
    return f"{value:0{(len(values)*width+3)//4}x}"


def run_model(run):
    root=Path(__file__).resolve().parents[1]
    manifest,splits=read_dataset(root)
    started=time.monotonic()
    weights=train_classifier(splits["train"],manifest["training"])
    train_seconds=round(time.monotonic()-started,3)
    model=export_model(weights,splits["train"])
    metrics=evaluate(splits["test"],weights,model)
    # This is a fixed smoke-quality guard, not a threshold tuned on test results.
    if metrics["float_accuracy"]<0.85 or metrics["float_accuracy"]-metrics["int8_output_accuracy"]>0.03:
        raise RuntimeError("Trained/quantized model fails the predeclared accuracy guard")
    print(f"  MODEL official-test float={metrics['float_accuracy']:.4%}, INT8={metrics['int8_output_accuracy']:.4%}",flush=True)
    selected=[(sample_id,features,label) for sample_id,(features,label) in enumerate(splits["test"])]
    batches=(len(selected)+3)//4
    qweights=[model["weights_int8"][cls][feature] for feature in range(65) for cls in range(10)]
    lines=[f"{model['multiplier']} {model['shift']} {batches}\n"]
    expected=[]
    for start in range(0,len(selected),4):
        qa_all=[];acc_all=[];out_all=[]
        for _,features,_ in selected[start:start+4]:
            qa,accum,outputs=integer_logits(features,model)
            qa_all+=qa;acc_all+=accum;out_all+=outputs
            expected.extend(zip(accum,outputs))
        missing=4-len(selected[start:start+4])
        qa_all += [0]*(missing*65)
        acc_all += [0]*(missing*10)
        out_all += [0]*(missing*10)
        expected.extend([(0,0)]*(missing*10))
        lines.append(f"{packed_values(qa_all,8)} {packed_values(qweights,8)} {packed_values(acc_all,23)} {packed_values(out_all,8)}\n")
    vectors=run.directory/"classifier_vectors.txt"
    vectors.write_text("".join(lines))
    executable=run.directory/"classifier_sim"
    run.run("classifier_build",[run.tool("iverilog"),"-g2012","-s","tb_digit_classifier","-o",str(executable),
            f"-Ptb_digit_classifier.MAX_BATCHES={batches}",
            "rtl/mac_pe.sv","rtl/systolic_array.sv","rtl/sync_dp_ram.sv","rtl/memory_gemm.sv","rtl/requantize.sv","tb/tb_digit_classifier.sv"])
    outputs=run.directory/"classifier_outputs.txt"
    log=run.run("classifier_rtl",[run.tool("vvp"),str(executable),f"+VECTORS={vectors}",f"+OUTPUT={outputs}"],
                [r"PASS: Trained RTL classifier",f"outputs={len(expected)}"])
    actual=[tuple(map(int,line.split())) for line in outputs.read_text().splitlines()]
    if actual!=expected:
        raise RuntimeError("Trained-model RTL logits differ from Python")
    rtl_predictions=[argmax([actual[10*i+cls][1] for cls in range(10)]) for i in range(len(selected))]
    metrics.update(rtl_samples=len(selected),rtl_logits_checked=len(actual),rtl_integer_mismatches=0,
                   rtl_correct=sum(pred==sample[2] for pred,sample in zip(rtl_predictions,selected)),
                   rtl_valid_logits_checked=len(selected)*10,rtl_padding_logits_checked=len(actual)-len(selected)*10,
                   rtl_accuracy=sum(pred==sample[2] for pred,sample in zip(rtl_predictions,selected))/len(selected),
                   parameters=model["parameters"],training_seconds=train_seconds,
                   training=manifest["training"],train_samples=len(splits["train"]),data_sha256=manifest["sha256"],
                   output_scale=model["output_scale"],weight_scale=model["weight_scale"],
                   rtl_scope="all 1797 official test images, batched four at a time; three padded rows checked separately")
    # The generated model/checkpoints stay in ignored run artifacts, not Git.
    (run.directory/"trained_model.json").write_text(json.dumps(model,indent=2)+"\n")
    (run.directory/"model_metrics.json").write_text(json.dumps(metrics,indent=2)+"\n")
    run.report["trained_model"]=metrics
    run.save()
