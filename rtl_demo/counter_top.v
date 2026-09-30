// =============================================================================
// Module : counter_top
// Project: 3-bit Pulse Counter
// Source : ddoc/counter_top_proposal.md §3
// Desc   : Top-level wrapper. Instantiates:
//            - u_register : CSR decode, pulse/count_clr gen, SR.overflow FF,
//                           read mux.
//            - u_counter  : 3-bit count FF, incrementer, clear, overflow detect.
//          Total sequential elements: 4 flip-flops
//            (3 × count[2:0] + 1 × SR.overflow).
//          Single clock domain, async active-low reset.
// =============================================================================

module counter_top (
    input  wire        clk,
    input  wire        rst_n,

    // CPU bus
    input  wire        wr_en,
    input  wire        rd_en,
    input  wire [9:0]  addr,
    input  wire [31:0] wdata,
    output wire [31:0] rdata
);

    // =========================================================================
    // Internal signals between u_register and u_counter (§2.2)
    // =========================================================================
    wire        pulse;          // u_register → u_counter, combinational 1-cycle
    wire        count_clr;      // u_register → u_counter, combinational 1-cycle
    wire        overflow;       // u_counter  → u_register, combinational 1-cycle
    wire [2:0]  count;          // u_counter  → u_register, FF output (real-time)

    // =========================================================================
    // u_register instance (§4)
    // =========================================================================
    register u_register (
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

    // =========================================================================
    // u_counter instance (§5)
    // =========================================================================
    counter u_counter (
        .clk       (clk),
        .rst_n     (rst_n),
        .pulse     (pulse),
        .count_clr (count_clr),
        .overflow  (overflow),
        .count     (count)
    );

endmodule
