# AXI4-Lite processor interface

`rtl/axi_gemm.sv` wraps the two-slot memory engine with a 32-bit AXI4-Lite
subordinate. The default shape remains M=3, K=5, N=7, TILE=4. Byte addresses
are eight bits wide; an interconnect must decode the peripheral's base address.
All registers require four-byte alignment. This is a CPU programmed-I/O
interface; a DMA engine and actual processor/board integration remain separate.

The five AXI channels use independent handshakes. AW and W each have a
one-entry buffer, so either may arrive first. There is at most one outstanding
write response and one outstanding read response. B/R payloads remain stable
until accepted. AxPROT is accepted without access filtering; the system must
implement any required security policy upstream. There are no bursts or IDs.
These choices follow the [Arm AXI4-Lite specification](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0022H_amba_axi_protocol_spec.pdf).

| Offset | Access | Contents |
|---|---|---|
| 0x00 | R | ID `0x49385341` (I8SA) |
| 0x04 | RW | Bank bit 0, IRQ enable bit 4, input tag bits 15:8 |
| 0x08 | W | One signed INT8 operand in bits 7:0; only WSTRB[0] loads a word |
| 0x0c | R | Busy bit 0, free banks bits 2:1, result valid bit 3, done sticky bit 6, error sticky bit 7, reset ready bit 8 |
| 0x10 | R | One sign-extended INT32 result; empty returns SLVERR |
| 0x14 | R | Metadata of last successful result-read address: tag bits 31:24, last bit 23, bank bit 22, index bits 15:0 |
| 0x18 | R | Accepted operand count, modulo 2³² |
| 0x1c | R | Completed compute-job count, modulo 2³² |
| 0x20 | RW1C | Done bit 0, error bit 1; writing one clears the corresponding sticky event |
| 0x24 | R | M, K, N, TILE packed into bytes from most to least significant |
| 0x28 | R | Number of input words per job, M×K+K×N |
| 0x2c | R | Number of output words per job, M×N |

Unknown, unaligned and read-only writes/write-only reads return SLVERR and
set the error bit. Valid RW fields honor byte strobes; zero-strobe DATA writes
complete without changing the engine. Reserved fields are read as zero and
ignored on writes to a writable CSR. M/K/N/TILE must be positive and at most
255; the metadata index is 16 bits. Integer outputs use the core's native width.

Select a free bank and tag, then write exactly M×K A words followed by K×N B
words in row-major order. Hardware counts words independently for each bank
and supplies the end-of-frame marker. The first word latches the tag. Completing
a frame starts computation automatically. Reset is the way to cancel a partial
frame; no software-abort CSR is implemented. Computation completion sets the
done bit; it does not imply the processor has drained the outputs.

Poll result-valid, read 0x10, then read 0x14 to associate the value with its job
and row-major index. A DATA read captures a result on AR acceptance and removes
it from the engine only on R acceptance. The result and its metadata remain
coherent under R backpressure. Consume the last result before reusing that bank.
The IRQ output is level-sensitive and equals enable AND (done OR error).
Hardware events win over simultaneous W1C clearing. Reset clears counters,
buffers, metadata and sticky status as well as cancelling all engine jobs.

A DATA write to an occupied bank waits until that bank becomes loadable. The
independent read channel remains available. Software must continue draining
results while such a write is pending, or avoid submitting it by checking the
free-bank bits first. A single-threaded CPU that blocks on an occupied-bank
write before reading results can deadlock itself. IRQs are event hints; poll
status for the exact current state.

`reset_sync.sv` asynchronously asserts and synchronously releases reset through
two clocked stages. READY and response VALID stay low until qualification.
All peripheral and core control state uses the qualified reset. The original
streaming core retains its existing reset interface. `async_reg` and `keep`
attributes identify the synchronizer; physical implementation must preserve
both stages, place them appropriately, time internal recovery/removal and
verify the library-specific reset pulse and metastability requirements.
Digital tests establish cancellation and clocked-release behavior, not MTBF.

`make axi` checks seven shapes at three seeds, four jobs per run, both write
channel orders, byte strobes, invalid accesses, IRQ/W1C, backpressure and seven
reset situations. The default shape also runs with five temporal assertions
under Verilator. These tests are included in `make verify` and CI. This is a
verified RTL peripheral; the earlier routed timing/power results belong to the
streaming memory top and do not include this wrapper.
