# Verification plan — Phase 1

## DUT contract
- N=4, signed 8-bit elements, matrix multiplication C=A×B.
- Results use signed 18-bit two's complement.
- Matrices captured on `start` while `busy==0`; `start` is one clock cycle.
- `busy` is asserted during compute, `done` pulses one cycle at completion.
- Output valid when `done==1`; results are retained until the next accepted `start`.
- One tile per transaction; there is no overlapping job or streaming handshake yet.

## Verification matrix
| Test | Purpose | Status |
|---|---|---|
| Zero matrices | Initialization and zeros | RTL testbench written, not run |
| Identity matrices | Indexing and ordering | RTL testbench written, not run |
| +127 × +127 | Positive accumulation | RTL testbench written, not run |
| -128 × -128 | Peak positive result = 65536 | RTL testbench written, not run |
| Mixed signs | Sign extension, skew mapping | RTL testbench written, not run |
| 100 randomized matrix pairs | General correctness | RTL testbench written, not run |
| Back-to-back independent jobs | Reset on each transaction | RTL testbench written, not run |
| SVA protocol assertions | start/busy/done behavior | Planned |
| Functional coverage | Operand and control corner cases | Planned |
| UVM environment | driver, monitor, agent, scoreboard | Planned |
| Synthesis PPA | area, Fmax, latency | Planned |

## Reference algorithm
Each PE computes `acc[i][j] += A[i][k]*B[k][j]` when `t == k+i+j`.
The last multiply is at `t=3*N-3`; overall compute latency is `3*N-2` cycles,
plus one rising edge to accept input matrices.

## Progress/claims policy
Only claim *designed and verified* once the HDL testbench passes on a real simulator.
Only cite frequency, power, LUT/cell area, and coverage after collecting actual tool reports.
