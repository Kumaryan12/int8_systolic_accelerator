"""Pinned OpenRAM views, compatible simulation model and hard-macro checks."""
import hashlib
import json
import re
from pathlib import Path
import subprocess
import sys

NAME='sky130_sram_1kbyte_1rw1r_32x256_8'
ROOT=Path(__file__).resolve().parents[1]


def prepare_model(directory):
    metadata=json.loads((ROOT/'third_party/sky130_sram/manifest.json').read_text())
    for filename,expected in metadata['vendored_sha256'].items():
        if hashlib.sha256((ROOT/'third_party/sky130_sram'/filename).read_bytes()).hexdigest()!=expected:
            raise RuntimeError(f'Changed SRAM view: {filename}')
    original=(ROOT/'third_party/sky130_sram'/f'{NAME}.v').read_text()
    declaration='reg [DATA_WIDTH-1:0]    mem [0:RAM_DEPTH-1];'
    if original.count(declaration)!=1 or '  // All inputs are registers' not in original:
        raise RuntimeError('Unknown upstream SRAM model structure')
    # Icarus 13 requires memory declarations before references in $display.
    # Only declaration order and an explicit time unit change, not behavior.
    model=original.replace(declaration,'').replace('  // All inputs are registers',declaration+'\n  // All inputs are registers',1)
    path=directory/'sky130_sram_model.v'
    path.write_text('`timescale 1ns/1ps\n'+model)
    return path


def run_sram(run):
    model=prepare_model(run.directory)
    run.report['sram_sources']={'manifest':json.loads((ROOT/'third_party/sky130_sram/manifest.json').read_text()),
                                'simulation_model_sha256':hashlib.sha256(model.read_bytes()).hexdigest()}
    run.save()
    sources=['rtl/mac_pe.sv','rtl/systolic_array.sv','rtl/sync_dp_ram.sv','rtl/sky130_dp_ram.sv',
             'rtl/memory_gemm.sv','rtl/reset_sync.sv','rtl/axi_gemm.sv',str(model)]
    executable=run.directory/'sram_unit'
    run.run('sram_unit_build',[run.tool('iverilog'),'-g2012','-s','tb_sky130_dp_ram','-o',str(executable),
                              'rtl/sky130_dp_ram.sv',str(model),'tb/tb_sky130_dp_ram.sv'])
    run.run('sram_unit',[run.tool('vvp'),str(executable)],[r'PASS: Banked SRAM'])
    for case in ('COLLIDE','BAD_READ'):
        run.run(f'sram_reject_{case}',[sys.executable,'scripts/sram.py',run.tool('vvp'),str(executable),case],
                [r'PASS: Expected SRAM rejection'])
    for m,k,n in ((1,1,1),(3,5,7),(4,4,4),(7,9,5),(8,8,8),(9,2,11),(2,17,3),(4,65,10)):
        for bench in ('memory','axi'):
            top=f'tb_{bench}_gemm'
            label=f'sram_{bench}_{m}x{k}x{n}'
            executable=run.directory/label
            run.run(f'{label}_build',[run.tool('iverilog'),'-g2012','-s',top,'-o',str(executable),
                    f'-P{top}.SRAM_IMPL=1',f'-P{top}.M={m}',f'-P{top}.K={k}',f'-P{top}.N={n}']+sources+[f'tb/{top}.sv'])
            for seed in run.args.seeds:
                markers=[r'PASS: Memory GEMM',r'jobs=8'] if bench=='memory' else [r'PASS: AXI GEMM',r'resets=7']
                run.run(f'{label}_seed{seed}',[run.tool('vvp'),str(executable),f'+SEED={seed}'],markers)
    benchmarks=[]
    for m,k,n in ((3,5,7),(8,8,8),(9,2,11)):
        modes={}
        for implementation in (0,1):
            label=f'sram_bench_{m}x{k}x{n}_impl{implementation}'
            executable=run.directory/label
            run.run(f'{label}_build',[run.tool('iverilog'),'-g2012','-s','tb_memory_gemm','-o',str(executable),
                    f'-Ptb_memory_gemm.M={m}',f'-Ptb_memory_gemm.K={k}',f'-Ptb_memory_gemm.N={n}',
                    f'-Ptb_memory_gemm.SRAM_IMPL={implementation}','-Ptb_memory_gemm.STALLS=0']+sources+['tb/tb_memory_gemm.sv'])
            log=run.run(label,[run.tool('vvp'),str(executable),'+SEED=20261110'],[r'PASS: Memory GEMM'])
            modes[str(implementation)]={key:int(value) for key,value in re.findall(r'(\w+)=(\d+)',re.search(r'METRIC .*',log)[0])}
        benchmarks.append({'shape':[m,k,n],'backends':modes})
    obj=run.directory/'sram_sva_obj' 
    run.run('sram_sva_build',[run.tool('verilator'),'--binary','--timing','--assert','-Wno-fatal',
            '--top-module','tb_memory_gemm','-GSRAM_IMPL=1','--Mdir',str(obj),'-j',str(run.args.jobs)]
            +sources+['tb/memory_stream_sva.sv','tb/tb_memory_gemm.sv'],timeout=900)
    for seed in run.args.seeds:
        run.run(f'sram_sva_seed{seed}',[str(obj/'Vtb_memory_gemm'),f'+SEED={seed}'],[r'PASS: Memory GEMM'])
    script=run.directory/'sram_synth.ys' 
    script.write_text(f'read_liberty -lib third_party/sky130_sram/{NAME}_TT_1p8V_25C.lib\n'
                      'read_verilog -sv '+ ' '.join(sources[:-1])+ '\n'
                      'hierarchy -check -top axi_gemm -chparam SRAM_IMPL 1\n'
                      'synth -top axi_gemm -flatten\ncheck\nstat\n'
                      f'write_json "{run.directory/"sram_netlist.json"}"\n'
                      f'write_verilog -noattr "{run.directory/"sram_netlist.v"}"\n')
    run.run('sram_synthesis',[run.tool('yosys'),'-Q','-s',str(script)],[r'Found and reported 0 problems',r'End of script'])
    cells=json.loads((run.directory/'sram_netlist.json').read_text())['modules']['axi_gemm']['cells']
    macros={name:cell['type'] for name,cell in cells.items() if cell['type']==NAME}
    if len(macros)!=3 or any(cell['type'].startswith('$mem') for cell in cells.values()):
        raise RuntimeError('Expected exactly three hard SRAM instances without inferred fallback RAM')
    run.report['sram']={'macro':NAME,'instances':macros,'generic_cells_including_macros':len(cells),'benchmarks':benchmarks,
                        'read_response':'following rising edge after request; held until next response',
                        'scope':'upstream functional model and hard-macro synthesis binding; no macro layout signoff'}
    (run.directory/'sram_metrics.json').write_text(json.dumps(run.report['sram'],indent=2)+'\n')
    run.save()


if __name__=='__main__':
    _,vvp,executable,case=sys.argv
    expected={'COLLIDE':'same-address read/write is unsupported','BAD_READ':'read outside logical depth'}[case]
    result=subprocess.run([vvp,executable,f'+{case}'],text=True,capture_output=True)
    if result.returncode==0 or expected not in result.stdout:
        raise SystemExit('Expected SRAM failure was not observed: '+result.stdout+result.stderr)
    print('PASS: Expected SRAM rejection '+case)
