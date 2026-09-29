# `counter` — Module Documentation

> RTL: `rtl/counter.v`
> Source of truth: `ddoc/counter_top_proposal.md` §5.1, §5.2, §7 · `ddoc/3-bit_pulse_counter_spec.md`

## Overview

`counter` is the counting datapath of `counter_top`. It holds the 3-bit count value, advances it by
one on every `pulse`, clears it on `count_clr`, and raises a one-cycle `overflow` event when a pulse
arrives while the count is already at its maximum value.

The module has no bus interface: all control comes from `register` as single-cycle strobes.

## Parameters

| Name    | Default | Description |
|---------|---------|-------------|
| `CNT_W` | `3`     | Counter width in bits. Effectively fixed at 3: the register map in `register` places `SR.cnt` at `[2:0]` and `SR.overflow` at `[3]`, so a wider counter would collide with the flag bit. |

## Ports

| Port        | Dir | Width   | Description |
|-------------|-----|---------|-------------|
| `clk`       | in  | 1       | System clock, rising edge. Single clock domain. |
| `rst_n`     | in  | 1       | **Asynchronous** reset, active low. Clears `count` to `0`. |
| `pulse`     | in  | 1       | Count strobe, one cycle wide. |
| `count_clr` | in  | 1       | Clear strobe, one cycle wide. |
| `overflow`  | out | 1       | Overflow event, combinational, one cycle wide. |
| `count`     | out | `CNT_W` | Current count value, straight from the flip-flops. |

## Functional description

### Next state

```
count_nxt = count_clr ? 0
          : pulse     ? count + 1
          :             count
```

- **Priority is `count_clr` > `pulse` > hold.** If the CPU writes `CR = 0x3` (both `count_clr` and
  `pulse_en` set in the same write), the clear wins and `count` goes to `0` (locked decision O2).
- **Wrap-around, not saturation.** The incrementer keeps only `CNT_W` bits, so `3'b111 + 1` is
  `3'b000`. Nothing stops the counter at its maximum value; this matches the reference waveform in
  the spec (`3'h7 → 3'h0`).

### Overflow detect

```
cnt_max  = &count
overflow = pulse & ~count_clr & cnt_max
```

- `overflow` is **combinational** and asserted in the *same* cycle as the pulse that causes the
  wrap. The sticky user-visible flag `SR.overflow` lives in `register` and therefore appears one
  cycle later.
- `~count_clr` keeps the detector consistent with the next-state priority: a simultaneous clear
  command means no increment happens, so no overflow is reported.

## Timing

| Item | Value |
|------|-------|
| Clock | `clk`, rising edge, one domain |
| Reset | `rst_n`, asynchronous, active low, `count → 0` |
| Sequential elements | 3 flip-flops (`count[2:0]`) |
| Latency | `count` updates on the clock edge that ends the cycle in which `pulse` is high |
| `overflow` | combinational from `pulse`, `count_clr`, `count`; 1 cycle wide |
| Throughput | one pulse per cycle is supported by this module; back-to-back CPU writes are out of scope at IP level |

## Design notes

- All outputs are functions of the current state and the input strobes only — there is no internal
  sequencing, no handshake, and no back-pressure.
- `overflow` is produced here rather than inferred in `register`, matching the internal signal
  directions fixed by the spec.

## Limitations

- `CNT_W` other than 3 is outside the scope of the spec and will break the `SR` field layout.
- No saturating mode and no count-down mode.
