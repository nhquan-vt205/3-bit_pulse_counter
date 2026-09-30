//=============================================================================
// DEMO VARIANT - not the production RTL. See demo/README.md.
// Differs from rtl/register.v by ONE feature: CR.count_clr is readable.
//=============================================================================
// Module      : register
// Description : CSR block of counter_top. Decodes the CPU bus, generates the
//               one-shot `pulse` / `count_clr` commands for the counter, holds
//               the sticky SR.overflow flag, and drives the read data path.
// Source      : ddoc/counter_top_proposal.md  (S4.1 - S4.5, S7)
//               demo/doc/cr_readback_design.md  (the added read path)
// Language    : Verilog-2005 (IEEE 1364-2005)
//
// Register map
//   0x000 CR : [1] count_clr  RW1P write 1 clears the counter, write 0 no-op,
//                                  READS BACK the last value written to it
//                                  (shadow flip-flop, see below)
//              [0] pulse_en   WO   write 1 emits exactly one pulse,
//                                  reads back 0 (no storage element)
//              [31:2] reserved, reads 0
//   0x004 SR : [3] overflow   RW0C set by the counter, cleared by writing 0,
//                                  writing 1 has no effect, never self-clears
//              [2:0] cnt      RO   live value of count[2:0]
//              [31:4] reserved, reads 0
//=============================================================================

module register #(
    parameter CNT_W  = 3,   // counter width, mirrors `counter`
    parameter ADDR_W = 10,  // register address width
    parameter DATA_W = 32   // read/write data width
) (
    input  wire              clk,        // system clock, rising edge
    input  wire              rst_n,      // asynchronous reset, active low

    // CPU bus
    input  wire              wr_en,      // write enable, one cycle wide
    input  wire              rd_en,      // read enable, one cycle wide
    input  wire [ADDR_W-1:0] addr,       // register address
    input  wire [DATA_W-1:0] wdata,      // write data
    output wire [DATA_W-1:0] rdata,      // read data, combinational

    // to / from counter
    output wire              pulse,      // one-cycle count strobe
    output wire              count_clr,  // one-cycle clear strobe
    input  wire              overflow,   // one-cycle overflow event
    input  wire [CNT_W-1:0]  count       // live count value
);

    // Addresses are compared over all ADDR_W bits: 0x001..0x003 do NOT hit CR.
    localparam [ADDR_W-1:0] ADDR_CR = 10'h000;
    localparam [ADDR_W-1:0] ADDR_SR = 10'h004;

    localparam CR_PULSE_BIT = 0;
    localparam CR_CLR_BIT   = 1;
    localparam SR_OVF_BIT   = 3;

    wire             cr_sel;
    wire             sr_sel;
    wire             cr_wr;
    wire             sr_wr;
    wire             sr_ovf_clr;
    wire             sr_ovf_nxt;
    reg              sr_overflow;
    reg              cr_clr_q;      // DEMO: readback shadow of CR.count_clr
    reg  [DATA_W-1:0] rd_word;

    //-------------------------------------------------------------------------
    // Address decode and write strobes (S4.1)
    //-------------------------------------------------------------------------
    assign cr_sel = (addr == ADDR_CR);
    assign sr_sel = (addr == ADDR_SR);
    assign cr_wr  = wr_en & cr_sel;
    assign sr_wr  = wr_en & sr_sel;

    //-------------------------------------------------------------------------
    // CR command generation (S4.2, S4.3)
    //   Purely combinational, no flip-flop: both strobes are exactly as wide as
    //   `wr_en`, so the counter updates on the clock edge that ends the write
    //   cycle. Inserting a flip-flop here would delay `count` by one cycle and
    //   break the reference waveform in the spec.
    //   CR.pulse_en has no storage element, so it still reads back 0.
    //-------------------------------------------------------------------------
    assign pulse     = cr_wr & wdata[CR_PULSE_BIT];
    assign count_clr = cr_wr & wdata[CR_CLR_BIT];

    //-------------------------------------------------------------------------
    // DEMO FEATURE - readback shadow for CR.count_clr
    //   The flip-flop records what the CPU last wrote to CR[1] so the bit can
    //   be read back. It is a PURE OBSERVER: `count_clr` above is still taken
    //   straight from `cr_wr & wdata[1]`, so the clear stays a one-shot pulse
    //   and this flip-flop drives nothing except the read mux.
    //   That is the whole point of the shadow: if `count_clr` were driven from
    //   cr_clr_q instead, a write of 1 would latch the clear high and pin the
    //   counter at 0 forever - the failure mode that decision O1 rejected.
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)     cr_clr_q <= 1'b0;
        else if (cr_wr) cr_clr_q <= wdata[CR_CLR_BIT];
    end

    //-------------------------------------------------------------------------
    // SR.overflow flag, RW0C (S4.4)
    //   sr_ovf_clr sits on the final gate, so a CPU write of 0 overrides both
    //   the set path and the hold path: clear wins over set in the same cycle
    //   (locked decision O3 - an overflow event coinciding with the clearing
    //   write is not recorded).
    //   There is no other path to 0: only rst_n or an explicit write of 0.
    //-------------------------------------------------------------------------
    assign sr_ovf_clr = sr_wr & ~wdata[SR_OVF_BIT];
    assign sr_ovf_nxt = (overflow | sr_overflow) & ~sr_ovf_clr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sr_overflow <= 1'b0;
        else        sr_overflow <= sr_ovf_nxt;
    end

    //-------------------------------------------------------------------------
    // Read mux (S4.5)
    //   Combinational: rdata is valid in the same cycle as rd_en.
    //   Unmapped addresses read all zeros, which is the default assignment
    //   below. SR.cnt is taken straight from the counter output, so it is a
    //   real-time value.
    //   DEMO: the cr_sel branch is new. It returns cr_clr_q on bit[1] and
    //   leaves every other bit at 0, so CR.pulse_en and the reserved bits
    //   still read back 0 exactly as before.
    //-------------------------------------------------------------------------
    always @(*) begin
        rd_word = {DATA_W{1'b0}};
        if (cr_sel) begin
            rd_word[CR_CLR_BIT] = cr_clr_q;
        end else if (sr_sel) begin
            rd_word[CNT_W-1:0]  = count;
            rd_word[SR_OVF_BIT] = sr_overflow;
        end
    end

    assign rdata = rd_en ? rd_word : {DATA_W{1'b0}};

endmodule
