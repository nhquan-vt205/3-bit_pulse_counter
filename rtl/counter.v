//=============================================================================
// Module      : counter
// Description : 3-bit pulse counter datapath. Counts one step per `pulse`,
//               clears on `count_clr`, and flags `overflow` when a pulse
//               arrives while the count is already at its maximum value.
// Source      : ddoc/counter_top_proposal.md  (S5.1, S5.2, S7)
// Language    : Verilog-2005 (IEEE 1364-2005)
//=============================================================================

module counter #(
    // Counter width. Fixed at 3 by the register map of `register`
    // (SR.cnt occupies bit[2:0], SR.overflow sits at bit[3]).
    parameter CNT_W = 3
) (
    input  wire              clk,        // system clock, rising edge
    input  wire              rst_n,      // asynchronous reset, active low

    input  wire              pulse,      // one-cycle count strobe
    input  wire              count_clr,  // one-cycle clear strobe

    output wire              overflow,   // one-cycle overflow event
    output wire [CNT_W-1:0]  count       // current count value
);

    reg  [CNT_W-1:0] count_r;
    reg  [CNT_W-1:0] count_nxt;
    wire             cnt_max;

    //-------------------------------------------------------------------------
    // Next-state mux (S5.1)
    //   Priority: count_clr > pulse > hold.
    //   The incrementer keeps only CNT_W bits, so the count wraps
    //   3'b111 -> 3'b000 instead of saturating.
    //-------------------------------------------------------------------------
    always @(*) begin
        if (count_clr)  count_nxt = {CNT_W{1'b0}};
        else if (pulse) count_nxt = count_r + 1'b1;
        else            count_nxt = count_r;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) count_r <= {CNT_W{1'b0}};
        else        count_r <= count_nxt;
    end

    assign count = count_r;

    //-------------------------------------------------------------------------
    // Overflow detect (S5.2)
    //   Combinational, one cycle wide, asserted in the same cycle as the pulse
    //   that causes the wrap. `~count_clr` keeps this consistent with the
    //   next-state priority: a clear command means no increment, hence no
    //   overflow.
    //-------------------------------------------------------------------------
    assign cnt_max  = &count_r;
    assign overflow = pulse & ~count_clr & cnt_max;

endmodule
