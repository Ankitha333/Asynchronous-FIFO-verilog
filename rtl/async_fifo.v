//======================================================================
// Asynchronous FIFO
// - Dual clock domains (write clock / read clock)
// - Gray-code pointers with 2-flop synchronizers for CDC safety
// - Configurable data width and depth (depth must be power of 2)
//======================================================================

module async_fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4              // FIFO depth = 2^ADDR_WIDTH
) (
    // Write side
    input  wire                     wr_clk,
    input  wire                     wr_rst_n,
    input  wire                     wr_en,
    input  wire [DATA_WIDTH-1:0]    wr_data,
    output reg                      full,

    // Read side
    input  wire                     rd_clk,
    input  wire                     rd_rst_n,
    input  wire                     rd_en,
    output reg  [DATA_WIDTH-1:0]    rd_data,
    output wire                     empty
);

    localparam DEPTH = 1 << ADDR_WIDTH;

    // Memory array
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Binary and Gray pointers (one extra MSB for full/empty distinction)
    reg  [ADDR_WIDTH:0] wr_ptr_bin, wr_ptr_gray;
    reg  [ADDR_WIDTH:0] rd_ptr_bin, rd_ptr_gray;

    // Synchronized pointers (2-flop synchronizers)
    reg  [ADDR_WIDTH:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2; // into rd_clk domain
    reg  [ADDR_WIDTH:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2; // into wr_clk domain

    wire [ADDR_WIDTH:0] wr_ptr_bin_next;
    wire [ADDR_WIDTH:0] wr_ptr_gray_next;
    wire [ADDR_WIDTH:0] rd_ptr_bin_next;
    wire [ADDR_WIDTH:0] rd_ptr_gray_next;

    //------------------------------------------------------------------
    // Write domain
    //------------------------------------------------------------------
    assign wr_ptr_bin_next  = wr_ptr_bin + (wr_en & ~full);
    assign wr_ptr_gray_next = (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr_bin  <= 0;
            wr_ptr_gray <= 0;
        end else begin
            wr_ptr_bin  <= wr_ptr_bin_next;
            wr_ptr_gray <= wr_ptr_gray_next;
        end
    end

    // Write into memory
    always @(posedge wr_clk) begin
        if (wr_en && !full)
            mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
    end

    // Synchronize read pointer into write clock domain
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_ptr_gray_sync1 <= 0;
            rd_ptr_gray_sync2 <= 0;
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    // Full condition: next write pointer (gray) equals read pointer (gray)
    // with top two bits inverted (standard async FIFO full check).
    // Registered (not a continuous assign) so that "full" is only ever
    // computed from its OWN previous cycle's value on the RHS above
    // (wr_ptr_bin_next uses the pre-edge "full") -- this avoids creating
    // a same-cycle combinational loop between full and the pointer logic.
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n)
            full <= 1'b0;
        else
            full <= (wr_ptr_gray_next == {~rd_ptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1],
                                            rd_ptr_gray_sync2[ADDR_WIDTH-2:0]});
    end

    //------------------------------------------------------------------
    // Read domain
    //------------------------------------------------------------------
    assign rd_ptr_bin_next  = rd_ptr_bin + (rd_en & ~empty);
    assign rd_ptr_gray_next = (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr_bin  <= 0;
            rd_ptr_gray <= 0;
        end else begin
            rd_ptr_bin  <= rd_ptr_bin_next;
            rd_ptr_gray <= rd_ptr_gray_next;
        end
    end

    // Read from memory (registered output)
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n)
            rd_data <= 0;
        else if (rd_en && !empty)
            rd_data <= mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
    end

    // Synchronize write pointer into read clock domain
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_ptr_gray_sync1 <= 0;
            wr_ptr_gray_sync2 <= 0;
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end

    // Empty condition: current read pointer (gray) equals synchronized write pointer (gray)
    assign empty = (rd_ptr_gray == wr_ptr_gray_sync2);

endmodule
