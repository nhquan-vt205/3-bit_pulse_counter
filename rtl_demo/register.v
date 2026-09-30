// =============================================================================
// Module : register
// Project: 3-bit Pulse Counter
// Source : ddoc/counter_top_proposal.md §4
// Desc   : CSR register block.
//          - Address decode for CR (0x000) and SR (0x004).
//          - Combinational one-shot generation of `pulse` and `count_clr`.
//          - SR.overflow flip-flop (RW0C): clear beats set when concurrent.
//          - Read mux: CR reads back 0, SR reads {28'h0, sr_overflow, count}.
//          - rdata gated by rd_en (0 when rd_en deasserted).
//          Contains 1 flip-flop (sr_overflow).
//          Async active-low reset.
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
    //   CR and unmapped addresses both read back all zeros, which is the
    //   default assignment below. SR.cnt is taken straight from the counter
    //   output, so it is a real-time value.
    // =========================================================================
    always @(*) begin
        rd_word = 32'h0;
        if (sr_sel) begin
            rd_word[2:0]        = count;
            rd_word[SR_OVF_BIT] = sr_overflow;
        end
    end

    assign rdata = rd_en ? rd_word : 32'h0;

endmodule
