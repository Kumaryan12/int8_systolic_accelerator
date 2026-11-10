PYTHON ?= python3
SEEDS ?= 2026 20261110 42
JOBS ?= 2
RANDOM_CASES ?= 200
RUN = $(PYTHON) scripts/regression.py --seeds $(SEEDS) --jobs $(JOBS) --random-cases $(RANDOM_CASES)

.PHONY: verify regression python-test sim advanced coverage uvm sva gemm memory memory-sva memory-bench memory-synth inference synth sta gate architecture physical model

# Each invocation creates a separate build/run_* directory and summary.json.
verify regression:
	$(RUN) --suite verify

python-test:
	$(RUN) --suite python

sim advanced coverage uvm sva gemm memory memory-sva memory-bench memory-synth inference gate architecture physical model:
	$(RUN) --suite $@

synth:
	$(RUN) --suite synth

sta:
	$(RUN) --suite ppa
