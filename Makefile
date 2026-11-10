PYTHON ?= python3
SEEDS ?= 2026 20261110 42
JOBS ?= 2
RANDOM_CASES ?= 200
RUN = $(PYTHON) scripts/regression.py --seeds $(SEEDS) --jobs $(JOBS) --random-cases $(RANDOM_CASES)

.PHONY: verify regression python-test sim advanced coverage uvm sva gemm memory memory-sva memory-bench memory-synth inference synth sta gate architecture physical model axi sram sram-synth

# Each invocation creates a separate build/run_* directory and summary.json.
verify regression:
	$(RUN) --suite verify

python-test:
	$(RUN) --suite python

sim advanced coverage uvm sva gemm memory memory-sva memory-bench memory-synth inference gate architecture model axi sram sram-synth:
	$(RUN) --suite $@

PHYSICAL_DESIGN ?= memory_gemm
physical:
	$(RUN) --suite physical --physical-design $(PHYSICAL_DESIGN)

.PHONY: postroute pvt rcx
.PHONY: design-space cpu-bench accuracy
design-space:
	$(RUN) --suite design-space

cpu-bench accuracy:
	$(RUN) --suite $@

postroute:
	$(RUN) --suite $@ --physical-run "$(PHYSICAL_RUN)"

rcx:
	$(RUN) --suite rcx --physical-run "$(PHYSICAL_RUN)"

pvt:
	$(RUN) --suite pvt --physical-run "$(PHYSICAL_RUN)" $(PVT_ARGS)

synth:
	$(RUN) --suite synth

sta:
	$(RUN) --suite ppa
