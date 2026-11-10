"""Paired float64/INT8 evaluation on a fixed official test split, without tuning on it."""

import json
import math
from pathlib import Path
import random

from digit_model import (argmax, export_model, integer_logits, packed_values,
                         read_dataset, scores_for, softmax, train_classifier)
from quantization import fixed_point_scale, requantize_int


MLP_CONFIG = {"seed":20261110,"epochs":35,"hidden":16,"learning_rate":0.03,"l2":0.0001}


def mlp_forward(features, first, second):
    hidden = [max(0.0,x) for x in scores_for(features,first)]
    return hidden, scores_for(hidden+[1.0],second)


def train_mlp(rows, config):
    rng = random.Random(config["seed"])
    width, hidden = len(rows[0][0]), config["hidden"]
    first = [[rng.gauss(0,math.sqrt(2/width)) for _ in range(width)] for _ in range(hidden)]
    second = [[rng.gauss(0,math.sqrt(2/hidden)) for _ in range(hidden)]+[0.0] for _ in range(10)]
    order = list(range(len(rows)))
    for epoch in range(config["epochs"]):
        rng.shuffle(order)
        rate = config["learning_rate"]/math.sqrt(1+epoch/5)
        for index in order:
            features,label = rows[index]
            activations,logits = mlp_forward(features,first,second)
            errors = softmax(logits)
            errors[label] -= 1
            hidden_errors = [sum(errors[c]*second[c][h] for c in range(10)) if activations[h]>0 else 0.0
                             for h in range(hidden)]
            for error,row in zip(errors,second):
                for i,x in enumerate(activations+[1.0]): row[i] -= rate*(error*x+config["l2"]*row[i])
            for error,row in zip(hidden_errors,first):
                for i,x in enumerate(features): row[i] -= rate*(error*x+config["l2"]*row[i])
        if (epoch+1)%5==0: print(f"  MLP epoch {epoch+1}/{config['epochs']}",flush=True)
    return first,second


def quantized_layer(weights, input_scale, output_scale):
    weight_scale = max(abs(x) for row in weights for x in row)/127 or 1.0
    multiplier,shift = fixed_point_scale(input_scale*weight_scale/output_scale)
    return dict(weights_int8=[[max(-127,min(127,round(x/weight_scale))) for x in row] for row in weights],
                input_scale=input_scale,weight_scale=weight_scale,output_scale=output_scale,multiplier=multiplier,shift=shift)


def integer_layer(inputs, model, relu=False):
    accum = [sum(x*w for x,w in zip(inputs,row)) for row in model["weights_int8"]]
    output = [requantize_int(x,model["multiplier"],model["shift"],relu=relu) for x in accum]
    return accum,output


def paired_metrics(labels, floating, quantized):
    if not labels or not (len(labels)==len(floating)==len(quantized)):
        raise ValueError("Predictions and labels must have equal nonzero length")
    count=len(labels)
    fp=sum(p==y for p,y in zip(floating,labels))
    qp=sum(p==y for p,y in zip(quantized,labels))
    lost=sum(f==y and q!=y for y,f,q in zip(labels,floating,quantized))
    gained=sum(f!=y and q==y for y,f,q in zip(labels,floating,quantized))
    # Approximate paired normal interval for the accuracy difference. The
    # official test split is fixed; this is descriptive sampling uncertainty.
    mean=(fp-qp)/count
    variance=max(0,(lost+gained)/count-mean*mean)
    radius=1.96*math.sqrt(variance/count)
    return dict(samples=count,float_correct=fp,int8_correct=qp,float_accuracy=fp/count,int8_accuracy=qp/count,
                accuracy_loss_percentage_points=100*mean,
                loss_approx_95ci_percentage_points=[100*(mean-radius),100*(mean+radius)],
                float_correct_int8_wrong=lost,float_wrong_int8_correct=gained,
                prediction_agreement=sum(f==q for f,q in zip(floating,quantized))/count)


def verify_layer(run, name, inputs, model, relu):
    width, outputs=len(inputs[0]),len(model["weights_int8"])
    word_width=16+(width-1).bit_length()
    b=[x for col in zip(*model["weights_int8"]) for x in col]
    lines=[]
    for start in range(0,len(inputs),4):
        batch=inputs[start:start+4]+[[0]*width for _ in range(4-len(inputs[start:start+4]))]
        acc=[]; out=[]
        for row in batch:
            a,q=integer_layer(row,model,relu)
            acc.extend(a);out.extend(q)
        lines.append(" ".join([packed_values([x for row in batch for x in row],8),packed_values(b,8),
                               packed_values(acc,word_width),packed_values(out,8),
                               str(model["multiplier"]),str(model["shift"]),str(int(relu))]))
    vectors=run.directory/(name+".txt")
    vectors.write_text("\n".join(lines)+"\n")
    executable=run.directory/name
    run.run(name+"_build",[run.tool("iverilog"),"-g2012","-s","tb_shared_gemm","-o",str(executable),
            "-Ptb_shared_gemm.M=4",f"-Ptb_shared_gemm.K={width}",f"-Ptb_shared_gemm.N={outputs}",
            f"-Ptb_shared_gemm.JOBS={len(lines)}","rtl/mac_pe.sv","rtl/systolic_array.sv","rtl/tiled_gemm.sv",
            "rtl/requantize.sv","tb/tb_shared_gemm.sv"])
    run.run(name+"_rtl",[run.tool("vvp"),str(executable),f"+INPUT={vectors}"],[f"PASS: shared GEMM",f"jobs={len(lines)}"],timeout=300)
    return {"samples":len(inputs),"jobs":len(lines),"valid_outputs":len(inputs)*outputs,
            "padding_outputs":(len(lines)*4-len(inputs))*outputs,"accumulator_and_int8_mismatches":0}


def run_accuracy_study(run):
    root=Path(__file__).resolve().parents[1]
    manifest,splits=read_dataset(root)
    train,test=splits["train"],splits["test"]
    labels=[y for _,y in test]
    # Hyperparameters are fixed before examining either test result. No model
    # selection, scale calibration or early stopping uses the test set.
    weights=train_classifier(train,manifest["training"])
    linear=export_model(weights,train)
    floating=[argmax(scores_for(x,weights)) for x,_ in test]
    quantized=[argmax(integer_logits(x,linear)[2]) for x,_ in test]
    linear_metrics=paired_metrics(labels,floating,quantized)
    linear_metrics.update(name="linear_softmax_64_to_10",parameters=650,training=manifest["training"],
                          rtl=verify_layer(run,"linear_accuracy",[integer_logits(x,linear)[0] for x,_ in test],linear,False))
    first,second=train_mlp(train,MLP_CONFIG)
    hidden_max=1.0; output_max=0.0
    for features,_ in train:
        hidden,scores=mlp_forward(features,first,second)
        hidden_max=max(hidden_max,max(hidden))
        output_max=max(output_max,max(abs(x) for x in scores))
    hidden_scale=hidden_max/120
    first_q=quantized_layer(first,1/127,hidden_scale)
    second_q=quantized_layer(second,hidden_scale,output_max/120 or 1.0)
    floating=[]; quantized=[]; layer1_inputs=[]; layer2_inputs=[]
    saturated_hidden=saturated_logits=0
    for features,_ in test:
        hidden,scores=mlp_forward(features,first,second)
        qa=[round(x*127) for x in features]
        _,qh=integer_layer(qa,first_q,True)
        qb=qh+[round(1/hidden_scale)]
        _,qo=integer_layer(qb,second_q)
        floating.append(argmax(scores));quantized.append(argmax(qo))
        layer1_inputs.append(qa);layer2_inputs.append(qb)
        saturated_hidden+=sum(x==127 for x in qh)
        saturated_logits+=sum(x in (-128,127) for x in qo)
    mlp_metrics=paired_metrics(labels,floating,quantized)
    mlp_metrics.update(name="relu_mlp_64_to_16_to_10",parameters=1210,training=MLP_CONFIG,
                       saturated_hidden_outputs=saturated_hidden,saturated_output_logits=saturated_logits,
                       hidden_output_scale=hidden_scale,logit_output_scale=second_q["output_scale"],
                       rtl_layer1=verify_layer(run,"mlp_hidden_accuracy",layer1_inputs,first_q,True),
                       rtl_layer2=verify_layer(run,"mlp_logits_accuracy",layer2_inputs,second_q,False))
    metrics={"models":[linear_metrics,mlp_metrics],"dataset_sha256":manifest["sha256"],
             "train_samples":len(train),"test_samples":len(test),
             "method":"Official UCI optdigits split; Python float64 reference; symmetric per-tensor INT8 weights and activations; half-away integer requantization; all scales calibrated on training only; same samples paired; fixed single seed, no test tuning",
             "scope":"Two architectures on one dataset; every layer checked in packed tiled_gemm RTL; host inserts quantized bias and chains layers; not a physically timed full classifier or multi-dataset generalization study",
             "source_sha256":run.report["source_sha256"],"tools":run.report["tools"]}
    (run.directory/"accuracy_study.json").write_text(json.dumps(metrics,indent=2)+"\n")
    (run.directory/"accuracy_models.json").write_text(json.dumps(dict(linear=linear,mlp_float=[first,second],mlp_int8=[first_q,second_q]),indent=2)+"\n")
    run.report["accuracy_study"]=metrics
    run.save()
