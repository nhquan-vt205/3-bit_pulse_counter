# `register` — Module Documentation

> RTL: `rtl/register.v`
> Source of truth: `ddoc/counter_top_proposal.md` §4.1–§4.5, §7 · `ddoc/3-bit_pulse_counter_spec.md`

## Overview

`register` is the CSR block of `counter_top`. It decodes the CPU bus, turns CR writes into the
one-shot `pulse` and `count_clr` commands for the counter, holds the sticky `SR.overflow` flag, and
drives the combinational read data path.

## Parameters

| Name     | Default | Description |
|----------|---------|-------------|
| `CNT_W`  | `3`     | Counter width; must match `counter`. Fixed at 3 by the `SR` field layout. |
| `ADDR_W` | `10`    | Register address width. |
| `DATA_W` | `32`    | Read/write data width. |

## Ports

| Port        | Dir | Width    | Description |
|-------------|-----|----------|-------------|
| `clk`       | in  | 1        | System clock, rising edge. |
| `rst_n`     | in  | 1        | **Asynchronous** reset, active low. Clears `SR.overflow`. |
| `wr_en`     | in  | 1        | Write enable, one cycle wide. |
| `rd_en`     | in  | 1        | Read enable, one cycle wide. |
| `addr`      | in  | `ADDR_W` | Register address. |
| `wdata`     | in  | `DATA_W` | Write data. |
| `rdata`     | out | `DATA_W` | Read data, combinational, valid in the same cycle as `rd_en`. |
| `pulse`     | out | 1        | Count strobe to `counter`, one cycle wide. |
| `count_clr` | out | 1        | Clear strobe to `counter`, one cycle wide. |
| `overflow`  | in  | 1        | Overflow event from `counter`, one cycle wide. |
| `count`     | in  | `CNT_W`  | Live count value from `counter`. |

## Register map

| Addr    | Name | Bits     | Field       | Access | Reset | Behaviour |
|---------|------|----------|-------------|--------|-------|-----------|
| `0x000` | `CR` | `[31:2]` | reserved    | RO 0   | —     | Reads `0` |
| `0x000` | `CR` | `[1]`    | `count_clr` | W1P    | —     | Write `1` clears the counter; write `0` has no effect; reads back `0`. No storage element. |
| `0x000` | `CR` | `[0]`    | `pulse_en`  | WO     | —     | Write `1` emits exactly one pulse; reads back `0`. No storage element. |
| `0x004` | `SR` | `[31:4]` | reserved    | RO 0   | —     | Reads `0` |
| `0x004` | `SR` | `[3]`    | `overflow`  | RW0C   | `0`   | Set by `overflow` from the counter. Write `0` clears it; write `1` has no effect. Never self-clears. Clear wins over set in the same cycle. 1 flip-flop. |
| `0x004` | `SR` | `[2:0]`  | `cnt`       | RO     | `0`   | Live value of `count[2:0]`, no separate flip-flop. |

## Functional description

### Address decode (§4.1)

```
cr_sel = (addr == 10'h000)
sr_sel = (addr == 10'h004)
cr_wr  = wr_en & cr_sel
sr_wr  = wr_en & sr_sel
```

The comparison covers **all `ADDR_W` bits** — `0x001..0x003` do *not* hit `CR` (locked decision O5).

### Command generation (§4.2, §4.3)

```
pulse     = cr_wr & wdata[0]
count_clr = cr_wr & wdata[1]
```

Both paths are **purely combinational, with no flip-flop**. That makes each strobe exactly as wide
as `wr_en`, so `count` updates on the clock edge that ends the write cycle — matching the reference
waveform in the spec. A flip-flop on these paths would add one cycle of latency and break it.
Having no storage element is also what makes both CR bits read back `0`.

### `SR.overflow` (§4.4)

```
sr_ovf_clr = sr_wr & ~wdata[3]                       // RW0C: writing 0 clears
sr_ovf_nxt = (overflow | sr_overflow) & ~sr_ovf_clr  // CLEAR OVERRIDES SET
```

1. **No self-clear path.** The bit returns to `0` only via `rst_n = 0` or an explicit CPU write of
   `0` to `SR[3]`. Time and later pulses do not clear it.
2. **Writing `1` has no effect.** With `wdata[3] = 1`, `sr_ovf_clr` is `0` and the value is held
   through the `OR` feedback path.
3. **Clear wins over set.** `sr_ovf_clr` sits on the final gate, so it forces `sr_ovf_nxt = 0`
   regardless of `overflow`. Consequence: an overflow event landing in the same cycle as the
   clearing write **is not recorded** (locked decision O3 — the CPU write always wins). The spec
   does not define this case.

### Read path (§4.5)

```
rd_word = sr_sel ? {28'h0, sr_overflow, count[2:0]} : 32'h0
rdata   = rd_en ? rd_word : 32'h0
```

Combinational, so `rdata` is valid in the same cycle `rd_en` is asserted (assumption O4 — the spec
gives no read waveform). `CR` and unmapped addresses both read all zeros. `SR.cnt` is taken
straight from the `counter` output, making it a real-time value.

## Timing

| Item | Value |
|------|-------|
| Clock | `clk`, rising edge, one domain |
| Reset | `rst_n`, asynchronous, active low, `sr_overflow → 0` |
| Sequential elements | 1 flip-flop (`sr_overflow`) |
| `pulse` / `count_clr` | combinational from `wr_en`, `addr`, `wdata`; 1 cycle wide |
| `rdata` | combinational; same-cycle response to `rd_en` |
| Write throughput | one write command at a time; back-to-back writes are not supported (no FIFO, no handshake, no `ready`) |

## Limitations

- No write-response or read-valid handshake; the bus is assumed to be a simple enable/address/data
  interface driven one transaction at a time.
- Reserved bits are dropped on write and read back as `0`; there is no error response for writes to
  unmapped addresses.
