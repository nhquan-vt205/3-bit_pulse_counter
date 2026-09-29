# `counter_top` — Module Documentation

> RTL: `rtl/counter_top.v` (integration only) · `rtl/register.v` · `rtl/counter.v`
> Source of truth: `ddoc/3-bit_pulse_counter_spec.md` · `ddoc/counter_top_proposal.md`

## Overview

`counter_top` is a 3-bit pulse counter driven over a CPU register interface. A write of `1` to
`CR.pulse_en` advances the count by one; a write of `1` to `CR.count_clr` clears it; a pulse while
the count is already `3'b111` wraps the count to `0` and sets the sticky `SR.overflow` flag, which
stays set until the CPU writes `0` to it.

The top level contains **no logic of its own** — it only instantiates the two sub-blocks and wires
the four internal signals between them.

| Sub-block  | Instance     | Role | Doc |
|------------|--------------|------|-----|
| `register` | `u_register` | Address decode, `pulse`/`count_clr` generation, `SR.overflow` flag, read mux | [`doc/register.md`](register.md) |
| `counter`  | `u_counter`  | `count[2:0]` flip-flops, incrementer, clear, overflow detect | [`doc/counter.md`](counter.md) |

## Parameters

| Name     | Default | Description |
|----------|---------|-------------|
| `CNT_W`  | `3`     | Counter width. Fixed at 3 by the `SR` field layout (`cnt` at `[2:0]`, `overflow` at `[3]`). |
| `ADDR_W` | `10`    | Register address width. |
| `DATA_W` | `32`    | Read/write data width. |

`RS_LV` from the spec's parameter table is **not** exposed: the reset polarity and style are fixed
(asynchronous, active low) rather than configurable — see *Reset* below.

## Ports

| Port    | Dir | Width    | Description |
|---------|-----|----------|-------------|
| `clk`   | in  | 1        | System clock, rising edge. Single clock domain. |
| `rst_n` | in  | 1        | **Asynchronous** reset, active low. |
| `wr_en` | in  | 1        | Register write enable, one cycle wide. |
| `rd_en` | in  | 1        | Register read enable, one cycle wide. |
| `addr`  | in  | `ADDR_W` | Register address. |
| `wdata` | in  | `DATA_W` | Write data. |
| `rdata` | out | `DATA_W` | Read data, combinational, valid in the same cycle as `rd_en`. |

### Internal signals (`u_register` ↔ `u_counter`)

| Signal      | Direction              | Width   | Type | Description |
|-------------|------------------------|---------|------|-------------|
| `pulse`     | `u_register` → `u_counter` | 1   | comb, 1 cycle | Count strobe, from a write of `1` to `CR.pulse_en` |
| `count_clr` | `u_register` → `u_counter` | 1   | comb, 1 cycle | Clear strobe, from a write of `1` to `CR.count_clr` |
| `overflow`  | `u_counter` → `u_register` | 1   | comb, 1 cycle | Pulse arrived while `count == 3'b111` |
| `count`     | `u_counter` → `u_register` | `CNT_W` | flip-flop output | Live count value, reflected into `SR.cnt` |

## Register map

| Addr    | Name | Bits     | Field       | Access | Reset | Behaviour |
|---------|------|----------|-------------|--------|-------|-----------|
| `0x000` | `CR` | `[31:2]` | reserved    | RO 0   | —     | Reads `0` |
| `0x000` | `CR` | `[1]`    | `count_clr` | W1P    | —     | Write `1` clears the counter; write `0` has no effect; reads back `0` |
| `0x000` | `CR` | `[0]`    | `pulse_en`  | WO     | —     | Write `1` emits exactly one pulse; reads back `0` |
| `0x004` | `SR` | `[31:4]` | reserved    | RO 0   | —     | Reads `0` |
| `0x004` | `SR` | `[3]`    | `overflow`  | RW0C   | `0`   | Write `0` clears; write `1` no effect; never self-clears; clear wins over set |
| `0x004` | `SR` | `[2:0]`  | `cnt`       | RO     | `0`   | Live `count[2:0]` |

## Behaviour summary

| Stimulus | Result |
|----------|--------|
| Write `CR = 0x1` | `pulse` for one cycle, `count + 1` on the next clock edge |
| Write `CR = 0x2` | `count → 0` on the next clock edge |
| Write `CR = 0x3` | Clear wins: `count → 0`, no overflow counted that cycle |
| Write `CR = 0x0` | No effect |
| Write `CR = 0x1` while `count == 3'b111` | `count` wraps to `0`, `overflow` high for one cycle, `SR.overflow` set on the next edge |
| Write `SR = 0x0` | `SR.overflow → 0` |
| Write `SR = 0x8` | No effect (writing `1` does not set or clear) |
| Write `SR = 0x0` in the same cycle as an `overflow` event | `SR.overflow → 0`; that event is lost (decision O3) |
| Read `CR` | `rdata = 32'h0` |
| Read `SR` | `rdata = {28'h0, SR.overflow, count[2:0]}`, `cnt` real-time |
| `rst_n = 0` | `count = 3'b000`, `SR.overflow = 0`, applied asynchronously |
| Address other than `0x000` / `0x004` | Writes ignored, reads return `32'h0` |

## Timing

| Item | Value |
|------|-------|
| Clock | `clk`, rising edge; single clock domain; frequency not specified by the spec |
| Reset | `rst_n`, **asynchronous**, active low |
| Sequential elements | **4 flip-flops** = 3 (`count[2:0]`) + 1 (`SR.overflow`) |
| Write latency | `count` updates on the clock edge that ends the write cycle |
| `SR.overflow` visibility | one cycle after the causing pulse (the flag is registered) |
| Read latency | 0 — `rdata` is combinational and valid during the `rd_en` cycle |
| Write throughput | one write command at a time; back-to-back writes are not supported |

## Reset

Asynchronous, active low, applied to all four flip-flops. This **deviates from the global
`CLAUDE.md` convention** (*"Reset: always synchronous"*) on purpose: the spec requires an
asynchronous reset, and the deviation is recorded as open item **O6** in the proposal.

## Design decisions carried from the proposal

| # | Decision | Rationale |
|---|----------|-----------|
| O1 | `CR[1] count_clr` is **W1P / one-shot**, not a stored RW bit | The spec's access column says `RW` but its description says *"write 1 to clear, write 0 has no effect"*. A stored bit would latch `1` and hold the counter at `0` forever. The spec text is treated as authoritative; `spec.md` was left unchanged. |
| O2 | `count_clr` beats `pulse` when `wdata[1:0] = 2'b11` | Clear is the stronger command; no overflow is counted in that cycle. |
| O3 | On `SR.overflow`, **clear beats set** in the same cycle | The CPU write always wins. Trade-off: an overflow coinciding with the clearing write is lost. |
| O4 | `rdata` is combinational, not pipelined | Spec gives no read waveform; same-cycle read keeps the block flat. |
| O5 | `addr` decode compares **all 10 bits** | `0x001..0x003` do not alias onto `CR`. Needs a misaligned-address testcase. |
| O6 | Asynchronous, active-low reset | Required by the spec; intentionally diverges from the project-wide convention. |

## Verification status

**Partially checked — not verified.**

| Check | Tool | Result |
|-------|------|--------|
| Elaboration, strict Verilog-2005 | `iverilog -g2005 -Wall` | Clean, no warnings |
| Directed sanity simulation | `iverilog` / `vvp` | 44/44 checks pass |
| Lint | Verilator | **Not run** — not installed |
| IP-level simulation | xvlog / xelab / xsim | **Not run** — not installed |
| Synthesis | Vivado | **Not run** — not installed |

The sanity simulation was a **throwaway bench run outside the repository**, covering the §8 oracle
trace (8 pulses, wrap `3'h7 → 3'h0`, one-cycle `overflow`, `SR.overflow` set one cycle later and
held), CR/SR/unmapped reads, RW0C behaviour of `SR.overflow`, the one-shot nature of `count_clr`,
decisions O2/O3/O5, and asynchronous reset applied away from a clock edge. It is **not** the
verification of record: the Vplan and the bench under `tb/counter_top/` belong to the `VERIFY`
phase and do not exist yet.

## Out of scope

- Widths other than `CNT_W = 3`, and multiple counter instances running in parallel.
- Back-to-back (continuous) write commands.
- Any bus handshake, error response, or read-valid signalling.
