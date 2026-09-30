// =============================================================================
// Module : counter
// Project: 3-bit Pulse Counter
// Source : ddoc/counter_top_proposal.md §5
// Desc   : 3-bit counter with incrementer, clear, and overflow detection.
//          Contains 3 flip-flops (count[2:0]).
//          - count_clr has highest priority (forces count to 0).
//          - pulse increments count by 1 (wraps 7 → 0).
//          - overflow = pulse & ~count_clr & (count == 3'b111), combinational.
//          - Async active-low reset.
// =============================================================================

module counter (
    input  wire       clk,
    input  wire       rst_n,

    // From u_register
    input  wire       pulse,
    input  wire       count_clr,

    // To u_register
    output wire       overflow,
    output wire [2:0] count
);

    // =========================================================================
    // Internal signals
    // =========================================================================
    reg  [2:0] count_r;
    reg  [2:0] count_nxt;
    wire       cnt_max;     // count == 3'b111

    // =========================================================================
    // Next-state priority mux (§5.1)
    //   Priority: count_clr > pulse > hold.
    //   The incrementer keeps only 3 bits, so the count wraps
    //   3'b111 -> 3'b000 instead of saturating.
    // =========================================================================
    always @(*) begin
        if (count_clr)  count_nxt = 3'b000;
        else if (pulse) count_nxt = count_r + 1'b1;
        else            count_nxt = count_r;
    end

    // =========================================================================
    // 3-bit count register — async active-low reset to 3'b000
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) count_r <= 3'b000;
        else        count_r <= count_nxt;
    end

    assign count = count_r;

    // =========================================================================
    // Overflow detection (§5.2) — combinational, 1-cycle pulse
    //   cnt_max  = count[2] & count[1] & count[0]    (== 3'b111)
    //   overflow = pulse & ~count_clr & cnt_max
    //
    //   ~count_clr ensures that if count_clr and pulse are both asserted
    //   (same cycle), no overflow is reported — consistent with count_clr
    //   priority in the next-state mux.
    // =========================================================================
    assign cnt_max  = &count_r;                       // count == 3'b111
    assign overflow = pulse & ~count_clr & cnt_max;

endmodule
