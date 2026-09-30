//=============================================================================
// File        : tb/counter_top/tbench.v
// Description : Directed testbench implementing doc/counter_top_vplan.md.
//               Verifies the CPU-bus read/write access contract of the
//               registers inside counter_top: TC01..TC08 of the Vplan.
//
// DUT         : rtl_demo/counter_top.v — the FIXED-SIZE variant (no
//               `parameter`). Environment widths below are not overridden
//               into the DUT; they only size this bench's own signals:
//               count 3-bit, wdata/rdata 32-bit, addr 10-bit.
//               This file is a copy of tb/counter_top/test_bench.v (which
//               targets the parameterized rtl/counter_top.v) with the DUT
//               instantiation changed to drop the parameter override. All 8
//               testcases are unchanged.
//
// Scope       : Register access only. The counting datapath is exercised only
//               as the observation path for CR writes (CR has no readback),
//               per Vplan S3.
//
// Observation : BLACK BOX. Every check goes through `rdata`; no internal
//               hierarchical probe is used, per Vplan S4.
//
// Structure   : CLAUDE.md defines the canonical bench layout as
//               tb/<ip>/tb_<name>.sv (one file per testcase, SystemVerilog).
//               This file is the single-file Verilog-2005 form that was
//               requested instead; all 8 testcases live here and one
//               [FINISH] token is printed for the whole run.
//
// Run         : iverilog -g2005 -s test_bench -o sim.out \
//                   ../../rtl_demo/counter_top.v ../../rtl_demo/register.v \
//                   ../../rtl_demo/counter.v tbench.v && vvp sim.out
//=============================================================================

`timescale 1ns/1ps

module test_bench;

    //-------------------------------------------------------------------------
    // Parameters of the environment (Vplan S4)
    //-------------------------------------------------------------------------
    localparam CNT_W      = 3;
    localparam ADDR_W     = 10;
    localparam DATA_W     = 32;

    localparam CLK_PERIOD = 10;        // 10 ns / 100 MHz. Bench assumption:
                                       // the spec does not fix a frequency.
    localparam SAMPLE_DLY = 1;         // when to sample combinational rdata
                                       // inside the driving cycle
    localparam RST_CYCLES = 2;         // rst_n held low for >= 2 cycles

    localparam [ADDR_W-1:0] ADDR_CR = 10'h000;
    localparam [ADDR_W-1:0] ADDR_SR = 10'h004;

    localparam NAME_W = 8*56;          // width of a check-name string

    //-------------------------------------------------------------------------
    // DUT connections
    //-------------------------------------------------------------------------
    reg               clk;
    reg               rst_n;
    reg               wr_en;
    reg               rd_en;
    reg  [ADDR_W-1:0] addr;
    reg  [DATA_W-1:0] wdata;
    wire [DATA_W-1:0] rdata;

    // rtl_demo/counter_top is fixed-size: no parameter list to override.
    counter_top u_dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .wr_en  (wr_en),
        .rd_en  (rd_en),
        .addr   (addr),
        .wdata  (wdata),
        .rdata  (rdata)
    );

    //-------------------------------------------------------------------------
    // Clock
    //-------------------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    //-------------------------------------------------------------------------
    // Scoreboard
    //-------------------------------------------------------------------------
    integer checks_run;
    integer checks_fail;
    integer tc_fail_mark;
    integer tc_run;
    integer tc_fail;
    reg [NAME_W-1:0] tc_name;
    reg [DATA_W-1:0] rd_val;
    integer i;

    // Expected SR readback: {28'h0, overflow, cnt}
    function [DATA_W-1:0] sr_exp;
        input            ovf;
        input [CNT_W-1:0] cnt;
        begin
            sr_exp = {{(DATA_W-4){1'b0}}, ovf, cnt};
        end
    endfunction

    task score;
        input [NAME_W-1:0] name;
        input [DATA_W-1:0] got;
        input [DATA_W-1:0] exp;
        begin
            checks_run = checks_run + 1;
            if (got === exp) begin
                $display("    ok   %0s : 0x%08h", name, got);
            end else begin
                checks_fail = checks_fail + 1;
                $display("    FAIL %0s : got 0x%08h exp 0x%08h  (t=%0t)",
                         name, got, exp, $time);
            end
        end
    endtask

    task tc_begin;
        input [NAME_W-1:0] name;
        begin
            tc_name      = name;
            tc_fail_mark = checks_fail;
            tc_run       = tc_run + 1;
            $display("\n--- %0s ---", name);
        end
    endtask

    task tc_end;
        begin
            if (checks_fail == tc_fail_mark) begin
                $display("    => %0s PASS", tc_name);
            end else begin
                tc_fail = tc_fail + 1;
                $display("    => %0s FAIL (%0d failing checks)",
                         tc_name, checks_fail - tc_fail_mark);
            end
        end
    endtask

    //-------------------------------------------------------------------------
    // CPU bus BFM
    //
    // Timing convention: every BFM task is ENTERED at a negedge of clk and
    // RETURNS at a negedge, so consecutive calls land on consecutive cycles
    // with no hidden gap. Signals are driven on the falling edge and rdata is
    // sampled SAMPLE_DLY later, i.e. inside the driving cycle and before its
    // rising edge - that is what proves the read path is combinational
    // (Vplan F05).
    //-------------------------------------------------------------------------

    // One write = 1 drive cycle + 1 mandatory gap cycle, so wr_en is never
    // high in two consecutive cycles: the spec does not support back-to-back
    // writes (Vplan S4).
    task cpu_write;
        input [ADDR_W-1:0] a;
        input [DATA_W-1:0] d;
        begin
            wr_en = 1'b1;
            rd_en = 1'b0;
            addr  = a;
            wdata = d;
            @(negedge clk);
            wr_en = 1'b0;
            wdata = {DATA_W{1'b0}};
            @(negedge clk);
        end
    endtask

    task cpu_read;
        input  [ADDR_W-1:0] a;
        output [DATA_W-1:0] d;
        begin
            wr_en = 1'b0;
            rd_en = 1'b1;
            addr  = a;
            #(SAMPLE_DLY);
            d = rdata;
            @(negedge clk);
            rd_en = 1'b0;
        end
    endtask

    task cpu_read_chk;
        input [NAME_W-1:0]  name;
        input [ADDR_W-1:0]  a;
        input [DATA_W-1:0]  exp;
        begin
            cpu_read(a, rd_val);
            score(name, rd_val, exp);
        end
    endtask

    // Write in cycle N and read in cycle N+1, with NO gap between them. This
    // is the only way to check that a value written through CR is visible at
    // SR in the immediately following cycle; the plain cpu_write/cpu_read pair
    // leaves a gap cycle in between and would pass even if the readback came
    // from a flop instead of the live count.
    task cpu_write_then_read_chk;
        input [NAME_W-1:0]  name;
        input [ADDR_W-1:0]  a_wr;
        input [DATA_W-1:0]  d;
        input [ADDR_W-1:0]  a_rd;
        input [DATA_W-1:0]  exp;
        begin
            wr_en = 1'b1;
            rd_en = 1'b0;
            addr  = a_wr;
            wdata = d;
            @(negedge clk);
            wr_en = 1'b0;
            wdata = {DATA_W{1'b0}};
            rd_en = 1'b1;                  // read starts the very next cycle
            addr  = a_rd;
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
            wr_en = 1'b0;
            rd_en = 1'b0;
            addr  = a;
            wdata = d;
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

    // Each testcase starts from reset so it is independent of the others,
    // matching the Vplan where every TC is its own file.
    task do_reset;
        begin
            rst_n = 1'b0;
            wr_en = 1'b0;
            rd_en = 1'b0;
            addr  = {ADDR_W{1'b0}};
            wdata = {DATA_W{1'b0}};
            idle_cycles(RST_CYCLES);
            rst_n = 1'b1;
        end
    endtask

    //=========================================================================
    // TC01 - reset values (F01)
    //=========================================================================
    task tc01_reset_value;
        begin
            tc_begin("TC01 tb_reg_reset_value");
            do_reset;
            cpu_read_chk("1 CR reads 0 after reset", ADDR_CR, 32'h0000_0000);
            cpu_read_chk("2 SR reads 0 after reset", ADDR_SR, 32'h0000_0000);
            idle_cycles(5);
            cpu_read_chk("3 SR still 0 after idle", ADDR_SR, 32'h0000_0000);
            tc_end;
        end
    endtask

    //=========================================================================
    // TC02 - read path: rd_en gate, aliasing, unmapped, combinational (F02-F05)
    //=========================================================================
    task tc02_rd_path;
        begin
            tc_begin("TC02 tb_reg_rd_path");
            do_reset;
            pulse_n(3);                                   // cnt = 3
            cpu_read_chk("1 SR shows cnt=3", ADDR_SR, sr_exp(1'b0, 3'd3));

            // 2 - rdata must be gated off when rd_en is low
            wr_en = 1'b0;
            rd_en = 1'b0;
            addr  = ADDR_SR;
            #(SAMPLE_DLY);
            score("2 rd_en=0 gates rdata", rdata, 32'h0000_0000);
            @(negedge clk);

            // 3 - CR aliases
            cpu_read_chk("3a read 0x001 is not CR", 10'h001, 32'h0000_0000);
            cpu_read_chk("3b read 0x002 is not CR", 10'h002, 32'h0000_0000);
            cpu_read_chk("3c read 0x003 is not CR", 10'h003, 32'h0000_0000);

            // 4 - SR aliases
            cpu_read_chk("4a read 0x005 is not SR", 10'h005, 32'h0000_0000);
            cpu_read_chk("4b read 0x006 is not SR", 10'h006, 32'h0000_0000);
            cpu_read_chk("4c read 0x007 is not SR", 10'h007, 32'h0000_0000);

            // 5 - unmapped addresses
            cpu_read_chk("5a read 0x008 unmapped", 10'h008, 32'h0000_0000);
            cpu_read_chk("5b read 0x00C unmapped", 10'h00C, 32'h0000_0000);
            cpu_read_chk("5c read 0x3FF unmapped", 10'h3FF, 32'h0000_0000);

            // 6 - writes to alias addresses must not reach CR or SR
            cpu_write(10'h001, 32'h0000_0001);
            cpu_write(10'h002, 32'h0000_0002);
            cpu_write(10'h003, 32'h0000_0003);
            cpu_write(10'h005, 32'h0000_0000);
            cpu_read_chk("6 alias writes had no effect", ADDR_SR,
                         sr_exp(1'b0, 3'd3));

            // 7 - rdata valid within the rd_en cycle, before the rising edge
            //     (cpu_read samples at SAMPLE_DLY after negedge)
            cpu_read_chk("7 rdata valid pre-edge", ADDR_SR, sr_exp(1'b0, 3'd3));
            tc_end;
        end
    endtask

    //=========================================================================
    // TC03 - CR is WO / W1P, reserved bits inert (F06-F08)
    //=========================================================================
    task tc03_cr_write;
        begin
            tc_begin("TC03 tb_reg_cr_write");
            do_reset;

            cpu_write(ADDR_CR, 32'h0000_0001);
            cpu_read_chk("1 CR readback 0 (WO)",    ADDR_CR, 32'h0000_0000);
            cpu_read_chk("2 pulse reached counter", ADDR_SR, sr_exp(1'b0, 3'd1));

            cpu_write(ADDR_CR, 32'h0000_0002);
            cpu_read_chk("3 CR readback 0 (W1P)",   ADDR_CR, 32'h0000_0000);
            cpu_read_chk("4 count_clr cleared cnt", ADDR_SR, sr_exp(1'b0, 3'd0));

            cpu_write(ADDR_CR, 32'h0000_0000);
            cpu_read_chk("5 CR=0 has no effect",    ADDR_SR, sr_exp(1'b0, 3'd0));

            pulse_n(2);
            cpu_read_chk("6 one pulse per write",   ADDR_SR, sr_exp(1'b0, 3'd2));

            cpu_write(ADDR_CR, 32'hFFFF_FFFC);
            cpu_read_chk("7 CR reserved inert",     ADDR_SR, sr_exp(1'b0, 3'd2));
            cpu_read_chk("8 CR still readback 0",   ADDR_CR, 32'h0000_0000);

            cpu_write(ADDR_CR, 32'hFFFF_FFFF);
            cpu_read_chk("9 count_clr beats pulse", ADDR_SR, sr_exp(1'b0, 3'd0));

            // The decisive W1P check: a stored RW bit would stay 1 and pin the
            // counter at 0 forever, so this read would come back 0.
            cpu_write(ADDR_CR, 32'h0000_0001);
            cpu_read_chk("10 count_clr not sticky", ADDR_SR, sr_exp(1'b0, 3'd1));
            tc_end;
        end
    endtask

    //=========================================================================
    // TC04 - SR.cnt is RO and real-time (F09, F11)
    //=========================================================================
    task tc04_sr_cnt_ro;
        begin
            tc_begin("TC04 tb_reg_sr_cnt_ro");
            do_reset;

            // 1 - sweep all 8 values; the 8th pulse wraps and sets overflow
            for (i = 1; i <= 8; i = i + 1) begin
                cpu_write(ADDR_CR, 32'h0000_0001);
                if (i < 8)
                    cpu_read_chk("1 cnt sweep", ADDR_SR, sr_exp(1'b0, i[CNT_W-1:0]));
                else
                    cpu_read_chk("1 cnt wraps, ovf set", ADDR_SR, sr_exp(1'b1, 3'd0));
            end

            // 2 - clear the flag, then take cnt to a value distinct from the
            //     value the RO checks below will try to write
            cpu_write(ADDR_SR, 32'h0000_0000);
            pulse_n(5);
            cpu_read_chk("2 cnt=5 ovf clear", ADDR_SR, sr_exp(1'b0, 3'd5));

            // 3 - try to write cnt=7 over cnt=5: RO must ignore it
            cpu_write(ADDR_SR, 32'h0000_0007);
            cpu_read_chk("3 cnt is RO (wrote 7)", ADDR_SR, sr_exp(1'b0, 3'd5));

            // 4 - all-ones write: reserved and cnt both unwritable
            cpu_write(ADDR_SR, 32'hFFFF_FFFF);
            cpu_read_chk("4 SR all-ones inert", ADDR_SR, sr_exp(1'b0, 3'd5));

            // 5 - a read must not disturb the value
            cpu_read_chk("5a read is non-destructive", ADDR_SR, sr_exp(1'b0, 3'd5));
            cpu_read_chk("5b read is non-destructive", ADDR_SR, sr_exp(1'b0, 3'd5));

            // 6 - the new value is visible in the cycle right after the write
            //     cycle, with no gap: SR.cnt must be the live count, not a
            //     registered copy of it
            cpu_write_then_read_chk("6 cnt live in next cycle",
                                    ADDR_CR, 32'h0000_0001,
                                    ADDR_SR, sr_exp(1'b0, 3'd6));
            tc_end;
        end
    endtask

    //=========================================================================
    // TC05 - SR.overflow is RW0C (F10, F11)
    //=========================================================================
    task tc05_sr_ovf_rw0c;
        begin
            tc_begin("TC05 tb_reg_sr_ovf_rw0c");
            do_reset;

            pulse_n(8);
            cpu_read_chk("1 ovf set by wrap",   ADDR_SR, sr_exp(1'b1, 3'd0));

            cpu_write(ADDR_SR, 32'h0000_0008);
            cpu_read_chk("2 write 1 no effect", ADDR_SR, sr_exp(1'b1, 3'd0));

            cpu_write(ADDR_SR, 32'h0000_000F);
            cpu_read_chk("3 write 0xF no clear", ADDR_SR, sr_exp(1'b1, 3'd0));

            idle_cycles(5);
            cpu_read_chk("4 ovf never self-clears", ADDR_SR, sr_exp(1'b1, 3'd0));

            pulse_n(2);
            cpu_read_chk("5 ovf sticky over pulses", ADDR_SR, sr_exp(1'b1, 3'd2));

            cpu_write(ADDR_SR, 32'h0000_0000);
            cpu_read_chk("6 write 0 clears, cnt kept", ADDR_SR, sr_exp(1'b0, 3'd2));

            pulse_n(6);                                 // 2->7 then wrap to 0
            cpu_read_chk("7 ovf can be set again", ADDR_SR, sr_exp(1'b1, 3'd0));

            cpu_write(ADDR_SR, 32'hFFFF_FFF7);
            cpu_read_chk("8 only bit3 clears", ADDR_SR, sr_exp(1'b0, 3'd0));
            tc_end;
        end
    endtask

    //=========================================================================
    // TC06 - writes are gated by wr_en (F12)
    //=========================================================================
    task tc06_wr_en_gate;
        begin
            tc_begin("TC06 tb_reg_wr_en_gate");
            do_reset;

            cpu_write(ADDR_CR, 32'h0000_0001);
            cpu_read_chk("1 cnt=1", ADDR_SR, sr_exp(1'b0, 3'd1));

            hold_no_write(ADDR_CR, 32'h0000_0001, 3);
            cpu_read_chk("2 no pulse without wr_en", ADDR_SR, sr_exp(1'b0, 3'd1));

            hold_no_write(ADDR_CR, 32'h0000_0002, 3);
            cpu_read_chk("3 no clear without wr_en", ADDR_SR, sr_exp(1'b0, 3'd1));

            pulse_n(7);                                 // 1->7 then wrap: ovf set
            cpu_read_chk("4a ovf set, cnt=0", ADDR_SR, sr_exp(1'b1, 3'd0));
            hold_no_write(ADDR_SR, 32'h0000_0000, 3);
            cpu_read_chk("4b no clear without wr_en", ADDR_SR, sr_exp(1'b1, 3'd0));

            // 5/6 - simultaneous read and write. BEYOND SPEC (Vplan R4):
            // recorded so debug does not have to guess, not a requirement.
            wr_en = 1'b1;
            rd_en = 1'b1;
            addr  = ADDR_CR;
            wdata = 32'h0000_0001;
            #(SAMPLE_DLY);
            score("5 CR read during write", rdata, 32'h0000_0000);
            @(negedge clk);
            wr_en = 1'b0;
            rd_en = 1'b0;
            wdata = {DATA_W{1'b0}};
            @(negedge clk);
            // the write still landed: cnt 0 -> 1, and ovf is still set
            cpu_read_chk("6 write took effect", ADDR_SR, sr_exp(1'b1, 3'd1));
            tc_end;
        end
    endtask

    //=========================================================================
    // TC07 - per-bit sweep of wdata, to catch off-by-one field decode
    //=========================================================================
    task tc07_bit_sweep;
        begin
            tc_begin("TC07 tb_reg_bit_sweep");

            // Phase A - CR: only bit0 and bit1 may do anything. cnt is parked
            // at 5 so that a stray pulse (6) or a stray clear (0) both show up.
            do_reset;
            pulse_n(5);
            cpu_read_chk("A0 cnt parked at 5", ADDR_SR, sr_exp(1'b0, 3'd5));
            for (i = 2; i < DATA_W; i = i + 1) begin
                cpu_write(ADDR_CR, 32'h0000_0001 << i);
                cpu_read_chk("A CR reserved bit readback", ADDR_CR, 32'h0000_0000);
                cpu_read_chk("A CR reserved bit inert",    ADDR_SR,
                             sr_exp(1'b0, 3'd5));
            end

            // Phase B - SR: only a 0 on bit3 may clear the flag. Every write
            // below holds bit3 high, so the flag must survive all of them.
            do_reset;
            pulse_n(8);
            cpu_read_chk("B0 ovf set", ADDR_SR, sr_exp(1'b1, 3'd0));
            for (i = 0; i < DATA_W; i = i + 1) begin
                if (i != 3) begin
                    cpu_write(ADDR_SR, ~(32'h0000_0001 << i));
                    cpu_read_chk("B only bit3 can clear", ADDR_SR,
                                 sr_exp(1'b1, 3'd0));
                end
            end

            // Phase C - the one write that must clear it
            cpu_write(ADDR_SR, ~(32'h0000_0001 << 3));
            cpu_read_chk("C bit3=0 clears ovf", ADDR_SR, sr_exp(1'b0, 3'd0));
            tc_end;
        end
    endtask

    //=========================================================================
    // TC08 - asynchronous reset (F13)
    //=========================================================================
    task tc08_reset_async;
        begin
            tc_begin("TC08 tb_reg_reset_async");
            do_reset;

            pulse_n(8);
            cpu_read_chk("1 ovf set, cnt wrapped", ADDR_SR, sr_exp(1'b1, 3'd0));

            // Assert rst_n between clock edges and observe the effect BEFORE
            // the next rising edge: that is what makes the reset asynchronous
            // rather than synchronous.
            wr_en = 1'b0;
            rd_en = 1'b1;
            addr  = ADDR_SR;
            #2 rst_n = 1'b0;                 // t_negedge + 2ns, posedge is +5ns
            #(SAMPLE_DLY);
            score("2 reset acts before any edge", rdata, 32'h0000_0000);
            @(negedge clk);
            rd_en = 1'b0;

            rst_n = 1'b1;
            cpu_read_chk("3a CR reads 0 after reset", ADDR_CR, 32'h0000_0000);
            cpu_read_chk("3b SR reads 0 after reset", ADDR_SR, 32'h0000_0000);

            cpu_write(ADDR_CR, 32'h0000_0001);
            cpu_read_chk("4 DUT works after reset", ADDR_SR, sr_exp(1'b0, 3'd1));
            tc_end;
        end
    endtask

    //=========================================================================
    // Main
    //=========================================================================
    initial begin
        checks_run  = 0;
        checks_fail = 0;
        tc_run      = 0;
        tc_fail     = 0;

        rst_n = 1'b0;
        wr_en = 1'b0;
        rd_en = 1'b0;
        addr  = {ADDR_W{1'b0}};
        wdata = {DATA_W{1'b0}};

        $display("=========================================================");
        $display(" counter_top register access testbench (rtl_demo, fixed-size)");
        $display(" implements doc/counter_top_vplan.md TC01..TC08");
        $display("=========================================================");

        // Align to a negedge once; every BFM task keeps that alignment.
        @(negedge clk);

        tc01_reset_value;
        tc02_rd_path;
        tc03_cr_write;
        tc04_sr_cnt_ro;
        tc05_sr_ovf_rw0c;
        tc06_wr_en_gate;
        tc07_bit_sweep;
        tc08_reset_async;

        $display("\n=========================================================");
        $display(" testcases : %0d run, %0d failed", tc_run, tc_fail);
        $display(" checks    : %0d run, %0d failed", checks_run, checks_fail);
        $display("=========================================================");

        // Vplan S11 / CLAUDE.md: exactly one verdict token per run.
        if (checks_fail == 0 && tc_fail == 0)
            $display("[FINISH] PASS");
        else
            $display("[FINISH] FAIL");

        $finish;
    end

    // Safety net so a broken handshake cannot hang the regression.
    initial begin
        #200000;
        $display("[FINISH] FAIL  timeout at %0t", $time);
        $finish;
    end

endmodule
