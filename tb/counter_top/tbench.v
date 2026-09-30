//=============================================================================
// File        : tb/counter_top/tbench.v
// Description : Directed testbench structured as the condensed checklist in
//               doc/counter_top_vplan.xlsx - five items VP01..VP05 covering
//               all 13 register features, instead of the eight separate
//               testcases the plan was merged from.
//
// DUT         : rtl_demo/{counter_top,register,counter}.v - the FIXED-SIZE
//               variant (no `parameter`) in which CR.count_clr is READABLE.
//               The localparams below only size this bench's own signals.
// Observation : BLACK BOX - every check goes through rdata.
//
// ONE DEVIATION FROM THE PLAN, deliberate:
//   VP03 in doc/counter_top_vplan.xlsx says "reading CR returns 0x0000_0000
//   at every step", which is true of the baseline rtl/ design. This bench
//   drives rtl_demo/, where CR[1] reads back the last value written to it
//   (see demo/doc/cr_readback_design.md). VP03 below therefore expects
//   cr_exp(<last wdata[1]>) instead of a constant zero, and adds the checks
//   for that read path. Everything else follows the plan as written.
//
// Item -> feature coverage (same as the plan):
//   VP01 RESET        F01, F13
//   VP02 BUS & DECODE F02, F03, F04, F05, F12
//   VP03 CR FIELD     F06, F07, F08  (+ CR.count_clr readback)
//   VP04 SR.cnt       F09
//   VP05 SR.overflow  F10, F11
//
// Run         : iverilog -g2005 -s tbench -o sim.out \
//                   ../../rtl_demo/counter_top.v ../../rtl_demo/register.v \
//                   ../../rtl_demo/counter.v tbench.v && vvp sim.out
//=============================================================================

`timescale 1ns/1ps

module tbench;

    localparam CNT_W      = 3;
    localparam ADDR_W     = 10;
    localparam DATA_W     = 32;
    localparam CLK_PERIOD = 10;
    localparam SAMPLE_DLY = 1;
    localparam RST_CYCLES = 2;

    localparam [ADDR_W-1:0] ADDR_CR = 10'h000;
    localparam [ADDR_W-1:0] ADDR_SR = 10'h004;

    localparam NAME_W = 8*56;

    reg               clk;
    reg               rst_n;
    reg               wr_en;
    reg               rd_en;
    reg  [ADDR_W-1:0] addr;
    reg  [DATA_W-1:0] wdata;
    wire [DATA_W-1:0] rdata;

    // rtl_demo/counter_top.v has no parameters, so no override here.
    counter_top u_dut (
        .clk (clk), .rst_n (rst_n),
        .wr_en (wr_en), .rd_en (rd_en),
        .addr (addr), .wdata (wdata), .rdata (rdata)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    //-------------------------------------------------------------------------
    // Scoreboard
    //-------------------------------------------------------------------------
    integer checks_run, checks_fail, it_fail_mark, it_run, it_fail;
    reg [NAME_W-1:0] it_name;
    reg [DATA_W-1:0] rd_val;
    integer i;

    function [DATA_W-1:0] sr_exp;          // {28'h0, overflow, cnt}
        input             ovf;
        input [CNT_W-1:0] cnt;
        begin
            sr_exp = {{(DATA_W-4){1'b0}}, ovf, cnt};
        end
    endfunction

    function [DATA_W-1:0] cr_exp;          // {30'h0, cr_clr_q, 1'b0}
        input clr;
        begin
            cr_exp = {{(DATA_W-2){1'b0}}, clr, 1'b0};
        end
    endfunction

    task score;
        input [NAME_W-1:0] name;
        input [DATA_W-1:0] got;
        input [DATA_W-1:0] exp;
        begin
            checks_run = checks_run + 1;
            if (got === exp)
                $display("    ok   %0s : 0x%08h", name, got);
            else begin
                checks_fail = checks_fail + 1;
                $display("    FAIL %0s : got 0x%08h exp 0x%08h  (t=%0t)",
                         name, got, exp, $time);
            end
        end
    endtask

    task item_begin;
        input [NAME_W-1:0] name;
        begin
            it_name      = name;
            it_fail_mark = checks_fail;
            it_run       = it_run + 1;
            $display("\n--- %0s ---", name);
        end
    endtask

    task item_end;
        begin
            if (checks_fail == it_fail_mark)
                $display("    => %0s PASS", it_name);
            else begin
                it_fail = it_fail + 1;
                $display("    => %0s FAIL (%0d failing checks)",
                         it_name, checks_fail - it_fail_mark);
            end
        end
    endtask

    //-------------------------------------------------------------------------
    // CPU bus BFM. Every task is entered at a negedge and returns at a
    // negedge. A write occupies its drive cycle plus one mandatory gap cycle,
    // so wr_en is never high in two consecutive cycles: the spec does not
    // support back-to-back writes.
    //-------------------------------------------------------------------------
    task cpu_write;
        input [ADDR_W-1:0] a;
        input [DATA_W-1:0] d;
        begin
            wr_en = 1'b1; rd_en = 1'b0; addr = a; wdata = d;
            @(negedge clk);
            wr_en = 1'b0; wdata = {DATA_W{1'b0}};
            @(negedge clk);
        end
    endtask

    // Samples rdata inside the driving cycle, before its rising edge: that is
    // what proves the read path is combinational (F05).
    task cpu_read;
        input  [ADDR_W-1:0] a;
        output [DATA_W-1:0] d;
        begin
            wr_en = 1'b0; rd_en = 1'b1; addr = a;
            #(SAMPLE_DLY);
            d = rdata;
            @(negedge clk);
            rd_en = 1'b0;
        end
    endtask

    task cpu_read_chk;
        input [NAME_W-1:0] name;
        input [ADDR_W-1:0] a;
        input [DATA_W-1:0] exp;
        begin
            cpu_read(a, rd_val);
            score(name, rd_val, exp);
        end
    endtask

    // Write in cycle N and read in cycle N+1 with NO gap - the only way to
    // show SR.cnt is the live count and not a registered copy.
    task cpu_write_then_read_chk;
        input [NAME_W-1:0] name;
        input [ADDR_W-1:0] a_wr;
        input [DATA_W-1:0] d;
        input [ADDR_W-1:0] a_rd;
        input [DATA_W-1:0] exp;
        begin
            wr_en = 1'b1; rd_en = 1'b0; addr = a_wr; wdata = d;
            @(negedge clk);
            wr_en = 1'b0; wdata = {DATA_W{1'b0}};
            rd_en = 1'b1; addr = a_rd;
            #(SAMPLE_DLY);
            score(name, rdata, exp);
            @(negedge clk);
            rd_en = 1'b0;
            @(negedge clk);
        end
    endtask

    task idle_cycles;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) @(negedge clk);
        end
    endtask

    // Drive address/data with wr_en low for n cycles: nothing may be written.
    task hold_no_write;
        input [ADDR_W-1:0] a;
        input [DATA_W-1:0] d;
        input integer      n;
        begin
            wr_en = 1'b0; rd_en = 1'b0; addr = a; wdata = d;
            idle_cycles(n);
            wdata = {DATA_W{1'b0}};
        end
    endtask

    task pulse_n;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) cpu_write(ADDR_CR, 32'h0000_0001);
        end
    endtask

    task do_reset;
        begin
            rst_n = 1'b0; wr_en = 1'b0; rd_en = 1'b0;
            addr  = {ADDR_W{1'b0}}; wdata = {DATA_W{1'b0}};
            idle_cycles(RST_CYCLES);
            rst_n = 1'b1;
        end
    endtask

    //=========================================================================
    // VP01 - RESET                                               F01, F13
    //   Reset readback values, and that rst_n acts without waiting for a
    //   rising clock edge.
    //=========================================================================
    task vp01_reset;
        begin
            item_begin("VP01 RESET");
            do_reset;
            cpu_read_chk("B2a CR reads 0 after reset", ADDR_CR, 32'h0000_0000);
            cpu_read_chk("B2b SR reads 0 after reset", ADDR_SR, 32'h0000_0000);
            idle_cycles(5);
            cpu_read_chk("B3 SR still 0 after idle",   ADDR_SR, 32'h0000_0000);

            pulse_n(8);                                   // wrap, set overflow
            cpu_read_chk("B4 overflow set before reset", ADDR_SR,
                         sr_exp(1'b1, 3'd0));

            // B5: assert rst_n between edges and observe it before the next
            // rising edge. A synchronous reset would still read 0x8 here.
            wr_en = 1'b0;
            rd_en = 1'b1;
            addr  = ADDR_SR;
            #2 rst_n = 1'b0;                 // negedge + 2ns, posedge is +5ns
            #(SAMPLE_DLY);
            score("B5 reset acts before any edge", rdata, 32'h0000_0000);
            @(negedge clk);
            rd_en = 1'b0;
            rst_n = 1'b1;

            cpu_read_chk("B6a CR = 0 after reset", ADDR_CR, 32'h0000_0000);
            cpu_read_chk("B6b SR = 0 after reset", ADDR_SR, 32'h0000_0000);
            cpu_write(ADDR_CR, 32'h0000_0001);
            cpu_read_chk("B6c DUT works after reset", ADDR_SR,
                         sr_exp(1'b0, 3'd1));
            item_end;
        end
    endtask

    //=========================================================================
    // VP02 - BUS & DECODE                       F02, F03, F04, F05, F12
    //   Full 10-bit decode, unmapped addresses, rd_en gating, same-cycle
    //   rdata, wr_en gating.
    //=========================================================================
    task vp02_bus_decode;
        begin
            item_begin("VP02 BUS & DECODE");
            do_reset;
            pulse_n(3);                                          // cnt = 3
            cpu_read_chk("B1 SR shows cnt=3", ADDR_SR, sr_exp(1'b0, 3'd3));

            // B2 - rdata must be gated off when rd_en is low
            wr_en = 1'b0; rd_en = 1'b0; addr = ADDR_SR;
            #(SAMPLE_DLY);
            score("B2 rd_en=0 gates rdata", rdata, 32'h0000_0000);
            @(negedge clk);

            // B4 - writes to alias addresses must not reach CR or SR
            cpu_write(10'h001, 32'h0000_0001);
            cpu_write(10'h002, 32'h0000_0002);
            cpu_write(10'h003, 32'h0000_0003);
            cpu_write(10'h005, 32'h0000_0000);
            cpu_read_chk("B4 alias writes had no effect", ADDR_SR,
                         sr_exp(1'b0, 3'd3));

            // B5 - rdata valid inside the rd_en cycle, before the rising edge
            cpu_read_chk("B5 rdata valid pre-edge", ADDR_SR,
                         sr_exp(1'b0, 3'd3));

            // B3 - alias and unmapped reads. Done with CR holding a NON-ZERO
            // value (cr_clr_q = 1), so a decode fault would leak it out here.
            // Writing 1 to CR[1] also clears the counter, hence cnt = 0.
            cpu_write(ADDR_CR, 32'h0000_0002);
            cpu_read_chk("B3pre CR holds 1",  ADDR_CR, cr_exp(1'b1));
            cpu_read_chk("B3a 0x001 not CR",  10'h001, 32'h0000_0000);
            cpu_read_chk("B3b 0x002 not CR",  10'h002, 32'h0000_0000);
            cpu_read_chk("B3c 0x003 not CR",  10'h003, 32'h0000_0000);
            cpu_read_chk("B3d 0x005 not SR",  10'h005, 32'h0000_0000);
            cpu_read_chk("B3e 0x006 not SR",  10'h006, 32'h0000_0000);
            cpu_read_chk("B3f 0x007 not SR",  10'h007, 32'h0000_0000);
            cpu_read_chk("B3g 0x008 unmapped", 10'h008, 32'h0000_0000);
            cpu_read_chk("B3h 0x00C unmapped", 10'h00C, 32'h0000_0000);
            cpu_read_chk("B3i 0x3FF unmapped", 10'h3FF, 32'h0000_0000);

            // B6 - a write needs wr_en; address and data alone must do nothing
            cpu_write(ADDR_CR, 32'h0000_0001);                   // cnt = 1
            cpu_read_chk("B6pre cnt=1", ADDR_SR, sr_exp(1'b0, 3'd1));
            hold_no_write(ADDR_CR, 32'h0000_0001, 3);
            cpu_read_chk("B6a no pulse without wr_en", ADDR_SR,
                         sr_exp(1'b0, 3'd1));
            hold_no_write(ADDR_CR, 32'h0000_0002, 3);
            cpu_read_chk("B6b no clear without wr_en", ADDR_SR,
                         sr_exp(1'b0, 3'd1));

            // B7 - same for SR: no wr_en, no clear of the overflow flag
            pulse_n(7);                                   // 1 -> 7 -> wrap 0
            cpu_read_chk("B7pre overflow set", ADDR_SR, sr_exp(1'b1, 3'd0));
            hold_no_write(ADDR_SR, 32'h0000_0000, 3);
            cpu_read_chk("B7 no SR clear without wr_en", ADDR_SR,
                         sr_exp(1'b1, 3'd0));

            // B8 - read and write asserted in the same cycle. BEYOND SPEC:
            // recorded so debug does not have to guess. cr_clr_q is 0 here
            // (the last CR write carried wdata[1] = 0), so CR reads 0.
            wr_en = 1'b1; rd_en = 1'b1; addr = ADDR_CR; wdata = 32'h0000_0001;
            #(SAMPLE_DLY);
            score("B8a CR read during write", rdata, cr_exp(1'b0));
            @(negedge clk);
            wr_en = 1'b0; rd_en = 1'b0; wdata = {DATA_W{1'b0}};
            @(negedge clk);
            cpu_read_chk("B8b write still took effect", ADDR_SR,
                         sr_exp(1'b1, 3'd1));
            item_end;
        end
    endtask

    //=========================================================================
    // VP03 - CR FIELD ACCESS                           F06, F07, F08
    //   pulse_en is WO, count_clr is W1P and never sticky, reserved bits are
    //   inert. Plus the CR.count_clr read path of this DUT: CR[1] reads back
    //   the last value written to it, every other CR bit still reads 0.
    //=========================================================================
    task vp03_cr_field;
        begin
            item_begin("VP03 CR FIELD ACCESS");
            do_reset;

            cpu_write(ADDR_CR, 32'h0000_0001);
            cpu_read_chk("B1a CR[1]=0 readback", ADDR_CR, cr_exp(1'b0));
            cpu_read_chk("B1b one pulse landed", ADDR_SR, sr_exp(1'b0, 3'd1));

            cpu_write(ADDR_CR, 32'h0000_0002);
            cpu_read_chk("B2a CR[1]=1 readback", ADDR_CR, cr_exp(1'b1));
            cpu_read_chk("B2b clear took effect", ADDR_SR, sr_exp(1'b0, 3'd0));

            cpu_write(ADDR_CR, 32'h0000_0000);
            cpu_read_chk("B3a CR[1] back to 0", ADDR_CR, cr_exp(1'b0));
            cpu_read_chk("B3b write 0 is inert", ADDR_SR, sr_exp(1'b0, 3'd0));

            pulse_n(2);
            cpu_read_chk("B4 one pulse per write", ADDR_SR, sr_exp(1'b0, 3'd2));

            cpu_write(ADDR_CR, 32'hFFFF_FFFC);              // reserved only
            cpu_read_chk("B5a CR reserved inert", ADDR_SR, sr_exp(1'b0, 3'd2));
            cpu_read_chk("B5b CR reserved reads 0", ADDR_CR, cr_exp(1'b0));

            cpu_write(ADDR_CR, 32'hFFFF_FFFF);              // both commands
            cpu_read_chk("B6a count_clr beats pulse", ADDR_SR,
                         sr_exp(1'b0, 3'd0));
            cpu_read_chk("B6b CR[1] reads 1", ADDR_CR, cr_exp(1'b1));

            // THE decisive check: count_clr must not be a level. A stored RW
            // bit would still be 1 here and would clear instead of count.
            cpu_write(ADDR_CR, 32'h0000_0001);
            cpu_read_chk("B7a counts again after clear", ADDR_SR,
                         sr_exp(1'b0, 3'd1));
            cpu_read_chk("B7b CR[1] overwritten by 0", ADDR_CR, cr_exp(1'b0));

            // B8 - sweep the 30 reserved bits with cnt parked at 5, so both a
            // stray pulse (6) and a stray clear (0) would show up.
            pulse_n(4);                                          // cnt = 5
            cpu_read_chk("B8pre cnt parked at 5", ADDR_SR, sr_exp(1'b0, 3'd5));
            for (i = 2; i < DATA_W; i = i + 1) begin
                cpu_write(ADDR_CR, 32'h0000_0001 << i);
                cpu_read_chk("B8a reserved bit reads 0", ADDR_CR,
                             cr_exp(1'b0));
                cpu_read_chk("B8b reserved bit inert", ADDR_SR,
                             sr_exp(1'b0, 3'd5));
            end
            item_end;
        end
    endtask

    //=========================================================================
    // VP04 - SR.cnt READBACK                                        F09
    //   RO, live value of count[2:0], all eight values swept.
    //=========================================================================
    task vp04_sr_cnt;
        begin
            item_begin("VP04 SR.cnt READBACK");
            do_reset;

            for (i = 1; i <= 8; i = i + 1) begin
                cpu_write(ADDR_CR, 32'h0000_0001);
                if (i < 8)
                    cpu_read_chk("B1 cnt sweep", ADDR_SR,
                                 sr_exp(1'b0, i[CNT_W-1:0]));
                else
                    cpu_read_chk("B1 cnt wraps, ovf set", ADDR_SR,
                                 sr_exp(1'b1, 3'd0));
            end

            cpu_write(ADDR_SR, 32'h0000_0000);              // clear the flag
            pulse_n(5);
            cpu_read_chk("B2 cnt=5 ovf clear", ADDR_SR, sr_exp(1'b0, 3'd5));

            // 7 is deliberately different from the current 5; if they matched
            // the check could not tell RO from writable.
            cpu_write(ADDR_SR, 32'h0000_0007);
            cpu_read_chk("B3 cnt is RO (wrote 7)", ADDR_SR, sr_exp(1'b0, 3'd5));

            cpu_write(ADDR_SR, 32'hFFFF_FFFF);
            cpu_read_chk("B4 SR all-ones inert", ADDR_SR, sr_exp(1'b0, 3'd5));

            cpu_read_chk("B5a read is non-destructive", ADDR_SR,
                         sr_exp(1'b0, 3'd5));
            cpu_read_chk("B5b read is non-destructive", ADDR_SR,
                         sr_exp(1'b0, 3'd5));

            // B6 must be adjacent: with a gap cycle a registered copy of the
            // count would pass this too.
            cpu_write_then_read_chk("B6 cnt live in next cycle",
                                    ADDR_CR, 32'h0000_0001,
                                    ADDR_SR, sr_exp(1'b0, 3'd6));
            item_end;
        end
    endtask

    //=========================================================================
    // VP05 - SR.overflow RW0C                                  F10, F11
    //   Set by the wrap, sticky, write 1 inert, write 0 clears, SR reserved
    //   bits inert, and only bit[3] can clear.
    //=========================================================================
    task vp05_sr_overflow;
        begin
            item_begin("VP05 SR.overflow RW0C");
            do_reset;

            pulse_n(8);
            cpu_read_chk("B1 ovf set by wrap", ADDR_SR, sr_exp(1'b1, 3'd0));

            cpu_write(ADDR_SR, 32'h0000_0008);
            cpu_read_chk("B2a write 1 is inert", ADDR_SR, sr_exp(1'b1, 3'd0));
            cpu_write(ADDR_SR, 32'h0000_000F);
            cpu_read_chk("B2b write 0xF no clear", ADDR_SR, sr_exp(1'b1, 3'd0));

            idle_cycles(5);
            cpu_read_chk("B3 never self-clears", ADDR_SR, sr_exp(1'b1, 3'd0));

            pulse_n(2);
            cpu_read_chk("B4 sticky over pulses", ADDR_SR, sr_exp(1'b1, 3'd2));

            cpu_write(ADDR_SR, 32'h0000_0000);
            cpu_read_chk("B5 write 0 clears, cnt kept", ADDR_SR,
                         sr_exp(1'b0, 3'd2));

            pulse_n(6);                                  // 2 -> 7 -> wrap 0
            cpu_read_chk("B6 can be set again", ADDR_SR, sr_exp(1'b1, 3'd0));

            cpu_write(ADDR_SR, 32'hFFFF_FFF7);
            cpu_read_chk("B7 only bit3 clears", ADDR_SR, sr_exp(1'b0, 3'd0));

            // B8 - every bit except 3 held low in turn: the flag must survive
            // all of them, and only the final write (bit[3] = 0) clears it.
            pulse_n(8);
            cpu_read_chk("B8pre ovf set again", ADDR_SR, sr_exp(1'b1, 3'd0));
            for (i = 0; i < DATA_W; i = i + 1) begin
                if (i != 3) begin
                    cpu_write(ADDR_SR, ~(32'h0000_0001 << i));
                    cpu_read_chk("B8a only bit3 can clear", ADDR_SR,
                                 sr_exp(1'b1, 3'd0));
                end
            end
            cpu_write(ADDR_SR, ~(32'h0000_0001 << 3));
            cpu_read_chk("B8b bit3=0 clears ovf", ADDR_SR, sr_exp(1'b0, 3'd0));
            item_end;
        end
    endtask

    //=========================================================================
    // Main
    //=========================================================================
    initial begin
        checks_run = 0; checks_fail = 0; it_run = 0; it_fail = 0;
        rst_n = 1'b0; wr_en = 1'b0; rd_en = 1'b0;
        addr  = {ADDR_W{1'b0}}; wdata = {DATA_W{1'b0}};

        $display("=========================================================");
        $display(" counter_top register checklist - VP01..VP05");
        $display(" doc/counter_top_vplan.xlsx, DUT rtl_demo (CR readable)");
        $display("=========================================================");

        @(negedge clk);

        vp01_reset;
        vp02_bus_decode;
        vp03_cr_field;
        vp04_sr_cnt;
        vp05_sr_overflow;

        $display("\n=========================================================");
        $display(" items  : %0d run, %0d failed", it_run, it_fail);
        $display(" checks : %0d run, %0d failed", checks_run, checks_fail);
        $display("=========================================================");

        if (checks_fail == 0 && it_fail == 0) $display("[FINISH] PASS");
        else                                  $display("[FINISH] FAIL");

        $finish;
    end

    initial begin
        #200000;
        $display("[FINISH] FAIL  timeout at %0t", $time);
        $finish;
    end

endmodule
