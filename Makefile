.PHONY: sim python-test clean

# Install Icarus Verilog (iverilog + vvp) to run the RTL testbench.
sim:
	@mkdir -p build
	iverilog -g2012 -Wall -s tb_systolic_array -o build/systolic_sim \
		rtl/mac_pe.sv rtl/systolic_array.sv tb/tb_systolic_array.sv
	vvp build/systolic_sim

python-test:
	python3 -m unittest discover -s scripts -p 'test_*.py' -v

clean:
	rm -f build/systolic_sim build/*.vcd
