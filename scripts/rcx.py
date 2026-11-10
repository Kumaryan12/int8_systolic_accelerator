"""Independently extract min/nom/max RC on a validated, unchanged routed ODB."""
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import subprocess

from pvt import fetch_artifact, validate_source


def spef_metrics(path):
    nets=segments=0
    cap=resistance=0.0
    in_res=False
    design=cap_unit=res_unit=None
    with path.open() as stream:
        for raw in stream:
            line=raw.strip()
            if line.startswith('*DESIGN '): design=line.split('"')[1]
            if line.startswith('*C_UNIT '): cap_unit=line.split()[1:]
            if line.startswith('*R_UNIT '): res_unit=line.split()[1:]
            if line.startswith('*D_NET '):
                try: value=float(line.split()[-1])
                except ValueError as error: raise RuntimeError('Invalid SPEF capacitance') from error
                if not math.isfinite(value) or value<0: raise RuntimeError('Invalid SPEF capacitance')
                cap+=value; nets+=1
            if line.startswith('*'): in_res=(line=='*RES')
            elif line and in_res:
                fields=line.split()
                if len(fields)!=4: raise RuntimeError('Invalid SPEF resistance segment')
                try: value=float(fields[-1])
                except ValueError as error: raise RuntimeError('Invalid SPEF resistance') from error
                if not math.isfinite(value) or value<0: raise RuntimeError('Invalid SPEF resistance')
                resistance+=value; segments+=1
    if cap_unit!=['1','PF'] or res_unit!=['1','OHM']:
        raise RuntimeError('Unsupported or missing SPEF units')
    if not design or not nets or not segments or cap<=0 or resistance<=0 or not math.isfinite(cap+resistance):
        raise RuntimeError('Missing or invalid extracted SPEF network')
    return {'design':design,'nets':nets,'resistance_segments':segments,
            'sum_dnet_capacitance_pF':cap,'sum_segment_resistance_ohm':resistance}


def load_rc_corners(directory,physical_result,config):
    previous=json.loads((directory/'summary.json').read_text())
    if previous.get('status')!='PASS' or previous.get('suite')!='rcx':
        raise RuntimeError('RC sweep input must be a successful RCX run')
    rc=previous['rcx']
    if rc['image']!=config['image'] or rc['physical_odb_sha256']!=hashlib.sha256((physical_result/'6_final.odb').read_bytes()).hexdigest():
        raise RuntimeError('RC extraction does not match the selected image/layout')
    if set(rc['corners'])!={'min','nom','max'}: raise RuntimeError('Incomplete RC corner set')
    paths={}
    for corner,metadata in rc['corners'].items():
        path=directory/metadata['file']
        if hashlib.sha256(path.read_bytes()).hexdigest()!=metadata['sha256']:
            raise RuntimeError('Extracted RC artifact changed after validation')
        paths[corner]=path
    return paths,rc


def run_rcx(run):
    root=Path(__file__).resolve().parents[1]
    source=Path(run.args.physical_run).resolve()
    config=json.loads((root/'physical/toolchain.json').read_text())
    previous=validate_source(source,config)
    design=previous['physical_toolchain']['design']
    nickname=previous['physical_toolchain'].get('nickname',f'int8_{design}')
    result=source/f'results/sky130hd/{nickname}/base'
    manifest=json.loads((root/'physical/rcx_rules.json').read_text())
    rules={corner:fetch_artifact(root/'build/rcx_cache',metadata['filename'],metadata)
           for corner,metadata in manifest['downloads'].items()}
    stage=run.directory/'rcx_sources';stage.mkdir()
    shutil.copy2(result/'6_final.odb',stage/'design.odb')
    shutil.copy2(root/'physical/rcx.tcl',stage/'rcx.tcl')
    for corner,path in rules.items():shutil.copy2(path,stage/f'rules.{corner}')
    docker=run.tool('docker');metrics={}
    for corner in ('min','nom','max'):
        name=f'int8-rcx-{run.directory.name}-{corner}'.lower().replace('_','-')
        created=success=False
        try:
            run.run(f'rcx_{corner}_create',[docker,'create','--name',name,'--platform',config['platform'],'--network','none',
                    '-e',f'RCX_CORNER={corner}',config['image'],'bash','-c',
                    'source /OpenROAD-flow-scripts/env.sh && mkdir -p /output && openroad -no_init -exit /project/rcx.tcl'],timeout=120)
            created=True
            run.run(f'rcx_{corner}_copy',[docker,'cp',str(stage),f'{name}:/project'],timeout=120)
            run.run(f'rcx_{corner}_extract',[docker,'start','--attach',name],[r'PASS: Independent RC extraction completed'],timeout=300)
            success=True
        finally:
            if created:
                if not success:subprocess.run([docker,'stop','--time','5',name],capture_output=True,timeout=30)
                collected=subprocess.run([docker,'cp',f'{name}:/output/.',str(run.directory)],capture_output=True,text=True,timeout=120)
                (run.directory/f'rcx_{corner}_collect.log').write_text(collected.stdout+collected.stderr)
            subprocess.run([docker,'rm','-f',name],capture_output=True,timeout=30)
        if collected.returncode:raise RuntimeError('Cannot collect RC extraction outputs')
        path=run.directory/f'{corner}.spef'
        metrics[corner]={**spef_metrics(path),'file':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
        if metrics[corner]['design']!=design:raise RuntimeError('Wrong design in extracted SPEF')
    if len({(m['sum_dnet_capacitance_pF'],m['sum_segment_resistance_ohm']) for m in metrics.values()})!=3:
        raise RuntimeError('RC corner extractions do not have distinct electrical values')
    run.report['rcx']={'physical_run':str(source),'design':design,'image':config['image'],
                       'physical_odb_sha256':hashlib.sha256((result/'6_final.odb').read_bytes()).hexdigest(),
                       'rules':manifest,'corners':metrics,
                       'scope':'independent published min/nom/max rule extraction on identical routed geometry; not foundry signoff'}
    (run.directory/'rcx_metrics.json').write_text(json.dumps(run.report['rcx'],indent=2)+'\n')
    run.save()
