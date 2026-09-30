// =============================================================================
// Module : register
// Project: 3-bit Pulse Counter
// Source : ddoc/counter_top_proposal.md §4
// Desc   : CSR register block.
//          - Address decode for CR (0x000) and SR (0x004).
//          - Combinational one-shot generation of `pulse` and `count_clr`.
//          - SR.overflow flip-flop (RW0C): clear beats set when concurrent.
//          - CR.count_clr is READABLE: a shadow flip-flop records the last
//            value written to CR[1] so the CPU can read it back. The clear
//            itself stays a one-shot pulse - see §4.3b.
//          - Read mux: CR reads {30'h0, cr_clr_q, 1'b0},
//                      SR reads {28'h0, sr_overflow, count}.
//          - rdata gated by rd_en (0 when rd_en deasserted).
//          Contains 2 flip-flops (sr_overflow, cr_clr_q).
//          Async active-low reset.
// Design : demo/doc/cr_readback_design.md
// =============================================================================

module register (
    input  wire        clk,
    input  wire        rst_n,

    // CPU bus
    input  wire        wr_en,
    input  wire        rd_en,
    input  wire [9:0]  addr,
    input  wire [31:0] wdata,
    output wire [31:0] rdata,

    // Interface to/from u_counter
    output wire        pulse,
    output wire        count_clr,
    input  wire        overflow,
    input  wire [2:0]  count
);

    // Addresses are compared over all 10 bits: 0x001..0x003 do NOT hit CR.
    localparam [9:0] ADDR_CR = 10'h000;
    localparam [9:0] ADDR_SR = 10'h004;

    localparam CR_PULSE_BIT = 0;
    localparam CR_CLR_BIT   = 1;
    localparam SR_OVF_BIT   = 3;

    wire        cr_sel;
    wire        sr_sel;
    wire        cr_wr;
    wire        sr_wr;
    wire        sr_ovf_clr;
    wire        sr_ovf_nxt;
    reg         sr_overflow;
    reg         cr_clr_q;      // readback shadow of CR.count_clr
    reg  [31:0] rd_word;

    // =========================================================================
    // §4.1 Address decode and write strobes
    // =========================================================================
    assign cr_sel = (addr == ADDR_CR);
    assign sr_sel = (addr == ADDR_SR);
    assign cr_wr  = wr_en & cr_sel;
    assign sr_wr  = wr_en & sr_sel;

    // =========================================================================
    // §4.2 Pulse generation — combinational one-shot (no FF)
    //   pulse = cr_wr & wdata[CR_PULSE_BIT]   (CR.pulse_en, WO)
    // =========================================================================
    assign pulse = cr_wr & wdata[CR_PULSE_BIT];

    // =========================================================================
    // §4.3 Count-clear generation — combinational one-shot (no FF)
    //   count_clr = cr_wr & wdata[CR_CLR_BIT]   (CR.count_clr, W1P)
    // =========================================================================
    assign count_clr = cr_wr & wdata[CR_CLR_BIT];

    // =========================================================================
    // §4.3b CR.count_clr readback shadow
    //   Records what the CPU last wrote to CR[1] so the bit can be read back.
    //   It is a PURE OBSERVER: `count_clr` above is still taken straight from
    //   cr_wr & wdata[1], so the clear stays a one-shot pulse, and this
    //   flip-flop drives nothing except the read mux below.
    //
    //   Do NOT rewrite the line above as `count_clr = cr_clr_q`. That would
    //   turn the clear into a level: after one write of 1 the counter would be
    //   pinned at 0 until the CPU wrote 0 back - the failure mode that made
    //   this field a one-shot in the first place.
    //
    //   Async active-low reset → cr_clr_q = 0
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)     cr_clr_q <= 1'b0;
        else if (cr_wr) cr_clr_q <= wdata[CR_CLR_BIT];
    end

    // =========================================================================
    // §4.4 SR.overflow flip-flop (RW0C)
    //   sr_ovf_clr sits on the final gate, so a CPU write of 0 overrides both
    //   the set path and the hold path: clear wins over set in the same cycle.
    //
    //   Async active-low reset → sr_overflow = 0
    // =========================================================================
    assign sr_ovf_clr = sr_wr & ~wdata[SR_OVF_BIT];
    assign sr_ovf_nxt = (overflow | sr_overflow) & ~sr_ovf_clr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sr_overflow <= 1'b0;
        else        sr_overflow <= sr_ovf_nxt;
    end

    // =========================================================================
    // §4.5 Read mux — combinational
    //   Unmapped addresses read back all zeros, the default assignment below.
    //   SR.cnt is taken straight from the counter output, so it is real-time.
    //   The cr_sel branch returns cr_clr_q on bit[1] and leaves every other
    //   bit at 0, so CR.pulse_en and the reserved bits still read back 0.
    // =========================================================================
    always @(*) begin
        rd_word = 32'h0;
        if (cr_sel) begin
            rd_word[CR_CLR_BIT] = cr_clr_q;
        end else if (sr_sel) begin
            rd_word[2:0]        = count;
            rd_word[SR_OVF_BIT] = sr_overflow;
        end
    end

    assign rdata = rd_en ? rd_word : 32'h0;

endmodule
