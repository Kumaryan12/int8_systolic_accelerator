
# ============================================================
# INT8 SYSTOLIC ARRAY - TIMING CONSTRAINTS
# ============================================================
#
# Design     : 4x4 INT8 Systolic Array Accelerator
# Technology : SKY130HD
# Corner     : Typical, 25 C, 1.8 V
#
# These are initial timing assumptions, not measured results.
# ============================================================

# ------------------------------------------------------------
# 1. CLOCK DEFINITION
# ------------------------------------------------------------

# Initial target: 100 MHz (10 ns period)
create_clock -name core_clk \
    -period 10.0 \
    [get_ports clk]

# Clock uncertainty for setup and hold
set_clock_uncertainty -setup 0.10 \
    [get_clocks core_clk]

set_clock_uncertainty -hold 0.05 \
    [get_clocks core_clk]

# Assumed clock transition time
set_clock_transition 0.10 \
    [get_clocks core_clk]

# ------------------------------------------------------------
# 2. INPUT TIMING CONSTRAINTS
# ------------------------------------------------------------

# Model external arrival delays for synchronous inputs.

foreach port_pattern {start a_matrix* b_matrix*} {

    set ports [get_ports $port_pattern]

    set_input_delay -clock core_clk \
        -max 1.0 $ports

    set_input_delay -clock core_clk \
        -min 0.0 $ports

    set_input_transition 0.10 $ports
}

# ------------------------------------------------------------
# 3. OUTPUT TIMING CONSTRAINTS
# ------------------------------------------------------------

# Model external timing requirements.

foreach port_pattern {busy done c_matrix*} {

    set ports [get_ports $port_pattern]

    set_output_delay -clock core_clk \
        -max 1.0 $ports

    set_output_delay -clock core_clk \
        -min 0.0 $ports

    # Assumed load in library capacitance units
    set_load 0.005 $ports
}

# ------------------------------------------------------------
# 4. ASYNCHRONOUS RESET
# ------------------------------------------------------------

# rst_n is an active-low asynchronous reset.
#
# It is deliberately excluded from the synchronous
# input-delay model.
#
# Reset recovery/removal and reset-tree timing require
# separate verification during the physical-design flow.

# ------------------------------------------------------------
# 5. ANALYSIS NOTES
# ------------------------------------------------------------

# Initial clock target : 10.0 ns
# Initial frequency    : 100 MHz
# No extracted wire parasitics are available.
# No placement or routing has been performed.
#
# Setup/hold results must be reviewed before claiming
# timing closure or a maximum operating frequency.

# ============================================================
# END OF CONSTRAINTS
# ============================================================
