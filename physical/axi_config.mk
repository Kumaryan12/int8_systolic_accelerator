include /project/physical/config.mk
export DESIGN_NAME = axi_gemm
export DESIGN_NICKNAME = int8_axi_gemm
export VERILOG_FILES += /project/rtl/reset_sync.sv /project/rtl/axi_gemm.sv
export SDC_FILE = /project/physical/axi_gemm.sdc
export CLOCK_PORT = aclk
