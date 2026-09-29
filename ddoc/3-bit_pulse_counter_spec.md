# 3-bit Pulse Counter (Register Design Practice) — Requirement

> Source: `ic_overview_session13_register_practice.pdf` — Session 13: Register Design Practice
> Course: ICTC – Fundamentals of IC Design (RTL Design and Verification)

## Overview
The `counter_top` module is a **3-bit pulse counter** with an **asynchronous reset**, controlled through a **Register** block (CSR – Control/Status Register interface). The module consists of 2 sub-blocks:
- **Register**: decodes the address, handles CR/SR read/write, generates control signals (`pulse`, `count_clr`) down to the `counter`, and receives status (`overflow`, `count[2:0]`) from the `counter` to reflect into the SR on read.
- **counter**: the actual 3-bit counting logic, handling pulse, clear, and overflow detection.

## Parameters
*Note: the original document does not define explicit parameters — this is a fixed-width design. The values below are constants inferred from the spec, listed in "Parameters" format to match the template structure.*

| Name   | Default | Description                                    |
|--------|---------|-------------------------------------------------|
| CNT_W  | 3       | counter width (bits)                           |
| ADDR_W | 10      | register address width (`addr[9:0]`)           |
| DATA_W | 32      | read/write data width                          |
| RS_LV  | 0       | reset active level (0 = active-low, async)     |

## Top-level ports

| Port         | Dir | Width | Description                    |
|--------------|-----|-------|----------------------------------|
| clk          | in  | 1     | System clock                    |
| rst_n        | in  | 1     | Asynchronous reset, active low  |
| wr_en        | in  | 1     | Register write enable           |
| rd_en        | in  | 1     | Register read enable            |
| addr[9:0]    | in  | 10    | Register address                |
| wdata[31:0]  | in  | 32    | Write data                       |
| rdata[31:0]  | out | 32    | Read data                        |

### Internal signals (Register ↔ counter)
*Not a top-level port, but needed for the internal logic diagram.*

| Signal      | Direction            | Description                                                                 |
|-------------|-----------------------|-------------------------------------------------------------------------------|
| pulse       | Register → counter    | Pulse generated when `1` is written to `CR.pulse_en`                          |
| count_clr   | Register → counter    | Clears the counter when `1` is written to `CR.count_clr`                     |
| overflow    | counter → Register    | Indicates a count overflow when the counter is at its max value and a pulse command still occurs |
| count[2:0]  | counter → Register    | Current count value, reflected into `SR.cnt`                                 |

## Register map

| Addr  | Name | Access     | Description |
|-------|------|------------|--------------|
| 0x000 | CR   | RW / WO    | Control register. bit[1] `count_clr` (RW) — write 1 to clear the counter, write 0 has no effect; bit[0] `pulse_en` (WO) — write 1 to generate one pulse, read always returns 0; bit[31:2] reserved |
| 0x004 | SR   | RW0C / RO  | Status register. bit[3] `overflow` (RW0C) — set to 1 when an overflow occurs, stays set until cleared by writing 0 (writing 1 has no effect); bit[2:0] `cnt` (RO) — current counter value; bit[31:4] reserved |

## Functional behavior
- Writing `1` to `CR.pulse_en` → generates a `pulse` and the counter increments by 1.
- The module **does not support continuous (back-to-back) writes** — only one write command is allowed at a time.
- Writing `CR.count_clr = 1` → clears the counter to `0` (via the `count_clr` signal).
- If a pulse is generated while the counter is already at its maximum value (`3'b111`) → an **overflow** occurs: `SR.overflow` is set to `1` and stays set until cleared by writing `0` to `SR.overflow`.
- The current counter value is always reflected (real-time, read-only) through `SR.cnt[2:0]`.

## Timing / performance
- Asynchronous reset, active low (`rst_n` = 0).
- System clock frequency: **not specified** in the source document.
- `SR.overflow` does not self-clear on the next clock cycle or the next pulse — it can only be cleared by an explicit CPU write of `0`.

## Out of scope
- RTL code, testbench, and the verification plan (Vplan) — these are **homework** requirements and are not part of this functional spec (see Appendix).
- The full logic diagram implementing the waveform — students must draw this themselves per the assignment; it is not included in the spec.
- Running multiple counter instances in parallel, or a counter width other than 3 bits, are not supported within the scope of this assignment.

---

## Appendix — Original source reference material
*This section keeps the original document's content that does not fit the standard IP-spec template structure, but is still needed for the practice session / homework.*

### Block diagram (counter_top)

```
                      counter_top
        ┌──────────────────────────────────────┐
        │                                        │
wr_en ─►│                        pulse ─────────►│
rd_en ─►│                                        │
addr[9:0]─►│         Register     count_clr ────►│   counter
wdata[31:0]─►│                    overflow ◄──────│
        │                        count[2:0] ◄─────│
        │                                        │
        │◄────────────────────── rdata[31:0]      │
        └──────────────────────────────────────┘
```

### Sample waveform (WaveDrom) — initial state, used as a template

```js
{signal: [
  {name: 'clk',          wave: 'p........................'},
  {name: 'rst_n',        wave: '01.......................'},
  {name: 'addr[9:0]',    wave: '=........................', data:["0x0"]},
  {name: 'wr_en',        wave: '0........................'},
  {name: 'wdata[31:0]',  wave: '=........................', data:["0x0"]},
  {name: 'pulse',        wave: '0........................'},
  {name: 'cnt[2:0]',     wave: '=........................', data:["3'h0"]},
  {name: 'overflow',     wave: '0........................'},
  {name: 'SR.overflow',  wave: '0........................'},
]}
```

### Worked-out waveform (illustrating pulse_en → increment → overflow)

```js
{signal: [
  {name: 'clk',          wave: 'p................................................'},
  {name: 'rst_n',        wave: '0.1..............................................'},
  {name: 'addr[9:0]',    wave: '=.=.==.==.==.==.==.==.==.=.......................', data: ["0x0", "0x0", "0x0", "0x0", "0x0", "0x0", "0x0", "0x0", "0x0", "0x0", "0x0", "0x0", "0x0", "0x0", "0x0", "0x0", "0x0"]},
  {name: 'wr_en',        wave: '0..10.10.10.10.10.10.10.10.......................'},
  {name: 'wdata[31:0]',  wave: '=.=.==.==.==.==.==.==.==.=.......................', data: ["0x0", "0x1", "0x0", "0x1", "0x0", "0x1", "0x0", "0x1", "0x0", "0x1","0x0", "0x1", "0x0", "0x1", "0x0", "0x1", "0x0"]},
  {name: 'pulse_en',     wave: '0..10.10.10.10.10.10.10.10.......................'},
  {name: 'cnt[2:0]',     wave: '=...=..=..=..=..=..=..=..=.......................', data: ["3'h0", "3'h1", "3'h2", "3'h3", "3'h4", "3'h5", "3'h6", "3'h7", "3'h0"]},
  {name: 'overflow',     wave: '0........................10......................'},
  {name: 'SR.overflow',  wave: '0.........................1......................'}
]}
```

Students still need to draw a waveform illustrating all cases required by the functional spec (writing pulse_en → pulse + count increment; writing count_clr → reset count; pulse when count = max → overflow sets SR.overflow; writing 0 to SR.overflow → clear).

### In-class practice flow

| Step | Content | Time |
|---|---|---|
| 1 | Self-study the specification | 10 min (19:10–19:20) |
| 2 | Q&A with the instructor to clarify requirements | 15 min (19:20–19:35) |
| 3 | Draw the waveform based on the template | 15 min (19:35–19:50) |
| 4 | Present and explain the waveform to the class (instructor picks 1–2 students) | 10 min (19:50–20:00) |
| 5 | Instructor explains the sample waveform, Q&A | 15 min (20:00–20:15) |
| 6 | Draw the logic diagram implementing the above waveform (logic generating pulse from a write command; logic for SR.overflow) | 15 min (20:15–20:30) |
| 7 | Present and explain the logic diagram | 10 min (20:30–20:40) |
| 8 | Instructor explains the sample diagram | 15 min (20:40–20:55) |

The RTL code and testbench will be completed as part of the homework.

### Homework requirements

Create a folder named `13_ss13` under the home directory, and inside it create a folder named `pulse_counter` containing the following (20 points total; the first 10 points cover the standard level, the rest is the advanced level):

| Requirement | Points |
|---|---|
| Redraw the waveform | 2p |
| Draw the **full** logic diagram of the module | 4p |
| Complete the RTL code | 6p |
| Create a Vplan (verification plan) | 2p |
| Generate a testbench and verify the design | 6p |

Submit all documents — including the waveform, logic diagram, and Vplan — in the report.
