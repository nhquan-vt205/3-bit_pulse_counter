//=============================================================================
// File        : demo/tbench.v
// Description : Directed testbench for the DEMO variant of counter_top, the
//               one where CR.count_clr is readable.
//               Implements demo/vplan_cr_readback.md, DTC01..DTC04.
//
// DUT         : demo/rtl_demo/{counter_top,register,counter}.v
// Observation : BLACK BOX - every check goes through rdata.
//
// Run         : iverilog -g2005 -s tbench -o sim.out \
//                   rtl_demo/counter_top.v rtl_demo/register.v \
//                   rtl_demo/counter.v tbench.v && vvp sim.out
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

    counter_top #(
        .CNT_W (CNT_W), .ADDR_W (ADDR_W), .DATA_W (DATA_W)
    ) u_dut (
        .clk (clk), .rst_n (rst_n),
        .wr_en (wr_en), .rd_en (rd_en),
        .addr (addr), .wdata (wdata), .rdata (rdata)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    //-------------------------------------------------------------------------
    // Scoreboard
    //-------------------------------------------------------------------------
    integer checks_run, checks_fail, tc_fail_mark, tc_run, tc_fail;
    reg [NAME_W-1:0] tc_name;
    reg [DATA_W-1:0] rd_val;
    integer i;

    // expected readback words
    function [DATA_W-1:0] sr_exp;
        input             ovf;
        input [CNT_W-1:0] cnt;
        begin
            sr_exp = {{(DATA_W-4){1'b0}}, ovf, cnt};
        end
    endfunction

    function [DATA_W-1:0] cr_exp;
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
            if (checks_fail == tc_fail_mark)
                $display("    => %0s PASS", tc_name);
            else begin
                tc_fail = tc_fail + 1;
                $display("    => %0s FAIL (%0d failing checks)",
                         tc_name, checks_fail - tc_fail_mark);
            end
        end
    endtask

    //-------------------------------------------------------------------------
    // CPU bus BFM - same convention as tb/counter_top/test_bench.v: every task
    // is entered at a negedge and returns at a negedge. A write occupies its
    // drive cycle plus one mandatory gap cycle, so wr_en is never high in two
    // consecutive cycles (the spec has no back-to-back writes).
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

    task idle_cycles;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) @(negedge clk);
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
    // DTC01 - reset values
    //=========================================================================
    task dtc01_reset_value;
        begin
            tc_begin("DTC01 reset_value");
            do_reset;
            cpu_read_chk("1 CR reads 0 after reset", ADDR_CR, 32'h0000_0000);
            cpu_read_chk("2 SR reads 0 after reset", ADDR_SR, 32'h0000_0000);
            tc_end;
        end
    endtask

    //=========================================================================
    // DTC02 - the new CR.count_clr read path
    //=========================================================================
    task dtc02_cr_readback;
        begin
            tc_begin("DTC02 cr_count_clr_readback");
            do_reset;

            cpu_write(ADDR_CR, 32'h0000_0002);
            cpu_read_chk("1 CR[1] reads back 1",  ADDR_CR, cr_exp(1'b1));

            cpu_write(ADDR_CR, 32'h0000_0000);
            cpu_read_chk("2 CR[1] reads back 0",  ADDR_CR, cr_exp(1'b0));

            cpu_write(ADDR_CR, 32'h0000_0001);
            cpu_read_chk("3 pulse_en stays WO",   ADDR_CR, cr_exp(1'b0));

            cpu_write(ADDR_CR, 32'h0000_0003);
            cpu_read_chk("4 only bit1 readable",  ADDR_CR, cr_exp(1'b1));

            cpu_write(ADDR_CR, 32'hFFFF_FFFF);
            cpu_read_chk("5 reserved still 0",    ADDR_CR, cr_exp(1'b1));

            cpu_read_chk("6 read is non-destructive", ADDR_CR, cr_exp(1'b1));

            // writing SR must not load the CR shadow
            cpu_write(ADDR_SR, 32'h0000_0000);
            cpu_read_chk("7 SR write leaves CR",  ADDR_CR, cr_exp(1'b1));

            // the new readback must not leak onto neighbouring addresses
            cpu_read_chk("8a 0x001 is not CR", 10'h001, 32'h0000_0000);
            cpu_read_chk("8b 0x002 is not CR", 10'h002, 32'h0000_0000);
            cpu_read_chk("8c 0x003 is not CR", 10'h003, 32'h0000_0000);
            tc_end;
        end
    endtask

    //=========================================================================
    // DTC03 - regression: count_clr must still be a one-shot pulse
    //=========================================================================
    task dtc03_clr_still_one_shot;
        begin
            tc_begin("DTC03 count_clr_still_one_shot");
            do_reset;

            pulse_n(3);
            cpu_read_chk("1 cnt = 3",            ADDR_SR, sr_exp(1'b0, 3'd3));

            cpu_write(ADDR_CR, 32'h0000_0002);
            cpu_read_chk("2 clear took effect",  ADDR_SR, sr_exp(1'b0, 3'd0));
            cpu_read_chk("3 shadow holds 1",     ADDR_CR, cr_exp(1'b1));

            // The decisive check. cr_clr_q is still 1 during this write, so a
            // design that drove count_clr from cr_clr_q would clear instead of
            // count and this would read back 0.
            cpu_write(ADDR_CR, 32'h0000_0001);
            cpu_read_chk("4 counts again after clear",
                         ADDR_SR, sr_exp(1'b0, 3'd1));

            cpu_write(ADDR_CR, 32'h0000_0001);
            cpu_read_chk("5 keeps counting",     ADDR_SR, sr_exp(1'b0, 3'd2));
            cpu_read_chk("6 shadow overwritten", ADDR_CR, cr_exp(1'b0));
            tc_end;
        end
    endtask

    //=========================================================================
    // DTC04 - SR path and address decode unchanged
    //=========================================================================
    task dtc04_sr_unchanged;
        begin
            tc_begin("DTC04 sr_and_decode_unchanged");
            do_reset;

            pulse_n(8);
            cpu_read_chk("1 wrap sets overflow", ADDR_SR, sr_exp(1'b1, 3'd0));

            cpu_write(ADDR_SR, 32'h0000_0008);
            cpu_read_chk("2 write 1 no effect",  ADDR_SR, sr_exp(1'b1, 3'd0));

            cpu_write(ADDR_SR, 32'h0000_0000);
            cpu_read_chk("3 write 0 clears",     ADDR_SR, sr_exp(1'b0, 3'd0));

            // rd_en gating matters more now: CR has non-zero content to leak
            cpu_write(ADDR_CR, 32'h0000_0002);
            wr_en = 1'b0; rd_en = 1'b0; addr = ADDR_CR;
            #(SAMPLE_DLY);
            score("4 rd_en=0 gates rdata", rdata, 32'h0000_0000);
            @(negedge clk);

            cpu_read_chk("5 0x008 unmapped",     10'h008, 32'h0000_0000);
            tc_end;
        end
    endtask

    //=========================================================================
    // Main
    //=========================================================================
    initial begin
        checks_run = 0; checks_fail = 0; tc_run = 0; tc_fail = 0;
        rst_n = 1'b0; wr_en = 1'b0; rd_en = 1'b0;
        addr  = {ADDR_W{1'b0}}; wdata = {DATA_W{1'b0}};

        $display("=========================================================");
        $display(" counter_top DEMO - CR.count_clr readback");
        $display(" implements demo/vplan_cr_readback.md DTC01..DTC04");
        $display("=========================================================");

        @(negedge clk);

        dtc01_reset_value;
        dtc02_cr_readback;
        dtc03_clr_still_one_shot;
        dtc04_sr_unchanged;

        $display("\n=========================================================");
        $display(" testcases : %0d run, %0d failed", tc_run, tc_fail);
        $display(" checks    : %0d run, %0d failed", checks_run, checks_fail);
        $display("=========================================================");

        if (checks_fail == 0 && tc_fail == 0) $display("[FINISH] PASS");
        else                                  $display("[FINISH] FAIL");

        $finish;
    end

    initial begin
        #100000;
        $display("[FINISH] FAIL  timeout at %0t", $time);
        $finish;
    end

endmodule
