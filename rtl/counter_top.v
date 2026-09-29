//=============================================================================
// Module      : counter_top
// Description : 3-bit pulse counter controlled over a CPU register interface.
//               Integration level only: instantiates the CSR block and the
//               counter datapath and wires the four internal signals between
//               them. No logic of its own.
// Source      : ddoc/3-bit_pulse_counter_spec.md
//               ddoc/counter_top_proposal.md  (S3, S6)
// Language    : Verilog-2005 (IEEE 1364-2005)
//
// Reset       : ASYNCHRONOUS, active low. This deviates from the global
//               "reset is always synchronous" convention in CLAUDE.md, on
//               purpose: the spec requires an asynchronous reset and the
//               deviation is recorded as open item O6 in the proposal.
//=============================================================================

module counter_top #(
    parameter CNT_W  = 3,   // counter width, fixed at 3 by the register map
    parameter ADDR_W = 10,  // register address width
    parameter DATA_W = 32   // read/write data width
) (
    input  wire              clk,    // system clock, rising edge
    input  wire              rst_n,  // asynchronous reset, active low

    input  wire              wr_en,  // register write enable
    input  wire              rd_en,  // register read enable
    input  wire [ADDR_W-1:0] addr,   // register address
    input  wire [DATA_W-1:0] wdata,  // write data
    output wire [DATA_W-1:0] rdata   // read data
);

    // register <-> counter
    wire             pulse;
    wire             count_clr;
    wire             overflow;
    wire [CNT_W-1:0] count;

    register #(
        .CNT_W     (CNT_W),
        .ADDR_W    (ADDR_W),
        .DATA_W    (DATA_W)
    ) u_register (
        .clk       (clk),
        .rst_n     (rst_n),
        .wr_en     (wr_en),
        .rd_en     (rd_en),
        .addr      (addr),
        .wdata     (wdata),
        .rdata     (rdata),
        .pulse     (pulse),
        .count_clr (count_clr),
        .overflow  (overflow),
        .count     (count)
    );

    counter #(
        .CNT_W     (CNT_W)
    ) u_counter (
        .clk       (clk),
        .rst_n     (rst_n),
        .pulse     (pulse),
        .count_clr (count_clr),
        .overflow  (overflow),
        .count     (count)
    );

endmodule
