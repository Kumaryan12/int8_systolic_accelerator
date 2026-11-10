
`ifndef SYSTOLIC_TRANSACTION_SVH
`define SYSTOLIC_TRANSACTION_SVH

// ============================================================
// INT8 SYSTOLIC ARRAY - UVM TRANSACTION
// ============================================================
//
// Hardware configuration:
// Array dimension : 4 x 4
// Input precision : Signed INT8
// Output precision: Signed INT18
//
// This class is included inside systolic_uvm_pkg.
// ============================================================

class systolic_transaction extends uvm_sequence_item;

    // ========================================================
    // 1. RANDOMIZED INPUT MATRICES
    // ========================================================

    // A and B each contain 16 signed 8-bit elements.
    // 16 * 8 = 128 bits.

    rand bit [127:0] a_matrix;
    rand bit [127:0] b_matrix;


    // ========================================================
    // 2. OUTPUT MATRIX
    // ========================================================

    // 16 outputs, each 18 bits wide.
    // 16 * 18 = 288 bits.

    logic [287:0] c_matrix = '0;


    // ========================================================
    // 3. TRANSACTION INFORMATION
    // ========================================================

    // 0 = input request
    // 1 = completed output response

    bit is_response = 0;
    bit inject_busy_start = 0;
    bit abort_job = 0;
    bit is_aborted = 0;


    // ========================================================
    // 4. UVM FACTORY REGISTRATION
    // ========================================================

    `uvm_object_utils(systolic_transaction)


    // ========================================================
    // 5. CONSTRUCTOR
    // ========================================================

    function new(string name = "systolic_transaction");

        super.new(name);

    endfunction


    // ========================================================
    // 6. READ SIGNED MATRIX A ELEMENT
    // ========================================================

    function automatic int signed get_a(
        input int row,
        input int col
    );

        logic signed [7:0] value;

        value = a_matrix[
            8*(row*4 + col) +: 8
        ];

        return int'(value);

    endfunction


    // ========================================================
    // 7. READ SIGNED MATRIX B ELEMENT
    // ========================================================

    function automatic int signed get_b(
        input int row,
        input int col
    );

        logic signed [7:0] value;

        value = b_matrix[
            8*(row*4 + col) +: 8
        ];

        return int'(value);

    endfunction


    // ========================================================
    // 8. SET MATRIX A ELEMENT
    // ========================================================

    function void set_a(
        input int row,
        input int col,
        input int signed value
    );

        a_matrix[
            8*(row*4 + col) +: 8
        ] = value[7:0];

    endfunction


    // ========================================================
    // 9. SET MATRIX B ELEMENT
    // ========================================================

    function void set_b(
        input int row,
        input int col,
        input int signed value
    );

        b_matrix[
            8*(row*4 + col) +: 8
        ] = value[7:0];

    endfunction


    // ========================================================
    // 10. GOLDEN REFERENCE MODEL
    // ========================================================

    // Computes expected C = A * B.
    // The scoreboard will compare this with hardware output.

    function automatic bit [287:0] expected_matrix();

        bit [287:0] expected;

        int signed acc;

        expected = '0;

        for (int r = 0; r < 4; r++) begin

            for (int c = 0; c < 4; c++) begin

                acc = 0;

                for (int k = 0; k < 4; k++) begin

                    acc += get_a(r, k) * get_b(k, c);

                end

                expected[
                    18*(r*4 + c) +: 18
                ] = acc[17:0];

            end

        end

        return expected;

    endfunction


    // ========================================================
    // 11. TRANSACTION DEBUG INFORMATION
    // ========================================================

    function string convert2string();

        return $sformatf(
            "A=%032h B=%032h C=%072h response=%0b",
            a_matrix,
            b_matrix,
            c_matrix,
            is_response
        );

    endfunction


endclass

`endif
