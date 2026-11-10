
`ifndef SYSTOLIC_SEQUENCE_SVH
`define SYSTOLIC_SEQUENCE_SVH

// ============================================================
// INT8 SYSTOLIC ARRAY - UVM TEST SEQUENCE
// ============================================================
//
// Generates:
//   1. Zero matrices
//   2. Identity matrices
//   3. Maximum positive INT8 values
//   4. Minimum negative INT8 values
//   5. Mixed-sign extreme values
//   6. Negative/positive diagonal matrices
//   7. Randomized matrix pairs
//
// ============================================================

class systolic_sequence extends
    uvm_sequence #(systolic_transaction);

    `uvm_object_utils(systolic_sequence)

    // ========================================================
    // 1. SEQUENCE CONFIGURATION
    // ========================================================

    int unsigned num_random = 200;

    localparam int N = 4;
    localparam int NUM_DIRECTED = 6;


    // ========================================================
    // 2. CONSTRUCTOR
    // ========================================================

    function new(string name = "systolic_sequence");

        super.new(name);

    endfunction


    // ========================================================
    // 3. DIRECTED MATRIX GENERATOR
    // ========================================================

    function void prepare_directed(
        systolic_transaction tr,
        int test_id
    );

        int signed a_value;
        int signed b_value;

        tr.a_matrix = '0;
        tr.b_matrix = '0;

        for (int r = 0; r < N; r++) begin

            for (int c = 0; c < N; c++) begin

                a_value = 0;
                b_value = 0;

                case (test_id)

                    // ----------------------------------------
                    // TEST 0: ALL-ZERO MATRICES
                    // ----------------------------------------

                    0: begin

                        a_value = 0;
                        b_value = 0;

                    end


                    // ----------------------------------------
                    // TEST 1: IDENTITY MATRICES
                    // ----------------------------------------

                    1: begin

                        a_value = (r == c) ? 1 : 0;
                        b_value = (r == c) ? 1 : 0;

                    end


                    // ----------------------------------------
                    // TEST 2: MAXIMUM POSITIVE INT8
                    // ----------------------------------------

                    2: begin

                        a_value = 127;
                        b_value = 127;

                    end


                    // ----------------------------------------
                    // TEST 3: MINIMUM NEGATIVE INT8
                    // ----------------------------------------

                    3: begin

                        a_value = -128;
                        b_value = -128;

                    end


                    // ----------------------------------------
                    // TEST 4: MIXED-SIGN EXTREMES
                    // ----------------------------------------

                    4: begin

                        a_value =
                            ((r*N+c)%2 == 0) ? -128 : 127;

                        b_value =
                            ((r*N+c)%3 == 0) ? 127 : -128;

                    end


                    // ----------------------------------------
                    // TEST 5: SIGNED DIAGONAL MATRICES
                    // ----------------------------------------

                    5: begin

                        a_value = (r == c) ? -128 : 0;
                        b_value = (r == c) ? 127 : 0;

                    end

                    default: begin

                        a_value = 0;
                        b_value = 0;

                    end

                endcase

                tr.set_a(r, c, a_value);
                tr.set_b(r, c, b_value);

            end

        end

    endfunction


    // ========================================================
    // 4. MAIN SEQUENCE BODY
    // ========================================================

    virtual task body();

        systolic_transaction req;

        // ----------------------------------------------------
        // A. RUN DIRECTED TESTS
        // ----------------------------------------------------

        `uvm_info(
            "SEQ",
            "Starting directed matrix tests",
            UVM_LOW
        )

        for (int test_id = 0;
             test_id < NUM_DIRECTED;
             test_id++) begin

            req = systolic_transaction::type_id::create(
                $sformatf("directed_req_%0d", test_id)
            );

            start_item(req);

            prepare_directed(req, test_id);

            req.is_response = 0;
            req.c_matrix = '0;

            finish_item(req);

            `uvm_info(
                "SEQ",
                $sformatf(
                    "Directed transaction %0d sent",
                    test_id
                ),
                UVM_MEDIUM
            )

        end


        // ----------------------------------------------------
        // B. RUN RANDOMIZED TESTS
        // ----------------------------------------------------

        `uvm_info(
            "SEQ",
            $sformatf(
                "Starting %0d randomized transactions",
                num_random
            ),
            UVM_LOW
        )

        for (int test_id = 0;
             test_id < num_random;
             test_id++) begin

            req = systolic_transaction::type_id::create(
                $sformatf("random_req_%0d", test_id)
            );

            start_item(req);

            if (!req.randomize()) begin

                `uvm_fatal(
                    "RAND_FAIL",
                    "Transaction randomization failed"
                )

            end

            req.is_response = 0;
            req.c_matrix = '0;

            finish_item(req);

            `uvm_info(
                "SEQ",
                $sformatf(
                    "Random transaction %0d sent",
                    test_id
                ),
                UVM_HIGH
            )

        end


        // ----------------------------------------------------
        // C. SEQUENCE COMPLETION
        // ----------------------------------------------------

        `uvm_info(
            "SEQ",
            $sformatf(
                "Sequence completed: %0d directed + %0d random",
                NUM_DIRECTED,
                num_random
            ),
            UVM_LOW
        )

    endtask

endclass

`endif
