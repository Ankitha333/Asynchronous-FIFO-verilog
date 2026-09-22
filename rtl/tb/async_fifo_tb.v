//======================================================================
// Testbench for async_fifo
// - Independent write/read clocks (different frequencies)
// - Randomized writes and reads with a reference queue for checking
// - Checks full/empty flags and data integrity
//======================================================================
`timescale 1ns/1ps

module async_fifo_tb;

    localparam DATA_WIDTH = 8;
    localparam ADDR_WIDTH = 4;
    localparam DEPTH      = 1 << ADDR_WIDTH;

    reg                    wr_clk;
    reg                    wr_rst_n;
    reg                    wr_en;
    reg  [DATA_WIDTH-1:0]  wr_data;
    wire                   full;

    reg                    rd_clk;
    reg                    rd_rst_n;
    reg                    rd_en;
    wire [DATA_WIDTH-1:0]  rd_data;
    wire                   empty;

    integer   wr_count;
    integer   rd_count;
    integer   errors;

    // Reference model: simple software queue
    reg [DATA_WIDTH-1:0] ref_queue [0:1023];
    integer ref_wr_ptr;
    integer ref_rd_ptr;

    //------------------------------------------------------------------
    // DUT instantiation
    //------------------------------------------------------------------
    async_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .wr_clk   (wr_clk),
        .wr_rst_n (wr_rst_n),
        .wr_en    (wr_en),
        .wr_data  (wr_data),
        .full     (full),

        .rd_clk   (rd_clk),
        .rd_rst_n (rd_rst_n),
        .rd_en    (rd_en),
        .rd_data  (rd_data),
        .empty    (empty)
    );

    //------------------------------------------------------------------
    // Clock generation: write clock 10ns period, read clock 17ns period
    // (deliberately different / non-integer-related to stress CDC)
    //------------------------------------------------------------------
    initial wr_clk = 0;
    always #5.0 wr_clk = ~wr_clk;

    initial rd_clk = 0;
    always #8.5 rd_clk = ~rd_clk;

    //------------------------------------------------------------------
    // Reset
    //------------------------------------------------------------------
    initial begin
        wr_rst_n = 0;
        rd_rst_n = 0;
        wr_en    = 0;
        rd_en    = 0;
        wr_data  = 0;
        ref_wr_ptr = 0;
        ref_rd_ptr = 0;
        wr_count = 0;
        rd_count = 0;
        errors   = 0;

        repeat (5) @(posedge wr_clk);
        wr_rst_n = 1;
        repeat (5) @(posedge rd_clk);
        rd_rst_n = 1;
    end

    //------------------------------------------------------------------
    // Write process: push random data with random gaps, respecting full
    //------------------------------------------------------------------
    integer NUM_WRITES = 200;
    initial begin
        @(posedge wr_rst_n);
        repeat (3) @(posedge wr_clk);

        while (wr_count < NUM_WRITES) begin
            @(posedge wr_clk);
            if (!full && ($random % 3 != 0)) begin  // ~2/3 chance to write when not full
                wr_en   <= 1;
                wr_data <= $random;
            end else begin
                wr_en <= 0;
            end

            // Capture into reference queue right after the clock edge that
            // samples wr_en/wr_data, using the value that was just driven.
            if (wr_en && !full) begin
                ref_queue[ref_wr_ptr] = wr_data;
                ref_wr_ptr = ref_wr_ptr + 1;
                wr_count = wr_count + 1;
            end
        end
        wr_en <= 0;
    end

    //------------------------------------------------------------------
    // Read process: pop with random gaps, respecting empty
    //------------------------------------------------------------------
    initial begin
        @(posedge rd_rst_n);
        repeat (3) @(posedge rd_clk);

        forever begin
            @(posedge rd_clk);
            if (!empty && ($random % 3 != 0)) begin
                rd_en <= 1;
            end else begin
                rd_en <= 0;
            end
        end
    end

    // Checker: sample rd_data one cycle after rd_en was asserted & not empty
    reg rd_en_d;
    reg empty_d;
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_en_d <= 0;
            empty_d <= 1;
        end else begin
            rd_en_d <= rd_en;
            empty_d <= empty;
        end
    end

    always @(posedge rd_clk) begin
        if (rd_rst_n && rd_en_d && !empty_d) begin
            if (rd_data !== ref_queue[ref_rd_ptr]) begin
                $display("[%0t] ERROR: rd_data=%0h expected=%0h (idx=%0d)",
                          $time, rd_data, ref_queue[ref_rd_ptr], ref_rd_ptr);
                errors = errors + 1;
            end
            ref_rd_ptr = ref_rd_ptr + 1;
            rd_count   = rd_count + 1;
        end
    end

    //------------------------------------------------------------------
    // Full/empty sanity checks
    //------------------------------------------------------------------
    always @(posedge wr_clk) begin
        if (wr_rst_n && wr_en && full)
            $display("[%0t] WARNING: write attempted while full (should have been blocked)", $time);
    end

    always @(posedge rd_clk) begin
        if (rd_rst_n && rd_en && empty)
            $display("[%0t] WARNING: read attempted while empty (should have been blocked)", $time);
    end

    //------------------------------------------------------------------
    // End of test
    //------------------------------------------------------------------
    initial begin
        wait (wr_count == NUM_WRITES);
        // give the read side time to drain
        wait (ref_rd_ptr == NUM_WRITES);

        repeat (10) @(posedge rd_clk);

        if (errors == 0)
            $display("\n==== TEST PASSED: %0d words written and verified, 0 errors ====\n", NUM_WRITES);
        else
            $display("\n==== TEST FAILED: %0d errors out of %0d words ====\n", errors, NUM_WRITES);

        $finish;
    end

    // Safety timeout
    initial begin
        #200000;
        $display("\n==== TIMEOUT: test did not complete ====\n");
        $display("wr_count=%0d rd_count=%0d ref_rd_ptr=%0d", wr_count, rd_count, ref_rd_ptr);
        $finish;
    end

    //------------------------------------------------------------------
    // Waveform dump
    //------------------------------------------------------------------
    initial begin
        $dumpfile("async_fifo_tb.vcd");
        $dumpvars(0, async_fifo_tb);
    end

endmodule
