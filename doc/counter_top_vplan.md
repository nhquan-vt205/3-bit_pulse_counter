# `counter_top` — Vplan: Directed test khả năng đọc/ghi register

> **DUT:** `rtl/counter_top.v` (+ `rtl/register.v`, `rtl/counter.v`)
> **Tài liệu tham chiếu:** `ddoc/3-bit_pulse_counter_spec.md` · `ddoc/counter_top_proposal.md` ·
> `doc/counter_top.md` · `doc/register.md`
> **Phạm vi bản Vplan này:** **chỉ** kiểm tra khả năng **đọc/ghi register** qua CPU bus ở mức
> `counter_top`, bằng **directed test đơn giản**. Chức năng đếm/tràn chỉ được dùng làm *phương tiện
> quan sát*, không phải mục tiêu verify của bản này (xem §9 Ngoài phạm vi).

---

## 1. Mục tiêu

Chứng minh khối register trong `counter_top` hành xử đúng hợp đồng truy cập (access contract) của
reg-map:

1. Địa chỉ được giải mã đúng, không alias sang địa chỉ lân cận.
2. Mỗi field trả về đúng giá trị readback theo kiểu truy cập của nó (`WO`, `W1P`, `RO`, `RW0C`).
3. Bit reserved ghi vào không có tác dụng, đọc ra luôn `0`.
4. `rdata` chỉ hợp lệ khi `rd_en = 1`, và hợp lệ **ngay trong cycle đó** (tổ hợp).
5. Lệnh ghi chỉ có tác dụng khi `wr_en = 1`.
6. Reset bất đồng bộ đưa toàn bộ giá trị đọc về được về `0`.

## 2. Reg-map cần verify

| Addr    | Reg  | Bits     | Field       | Access | Readback kỳ vọng |
|---------|------|----------|-------------|--------|------------------|
| `0x000` | `CR` | `[31:2]` | reserved    | RO 0   | `0` |
| `0x000` | `CR` | `[1]`    | `count_clr` | W1P    | `0` (không có phần tử lưu) |
| `0x000` | `CR` | `[0]`    | `pulse_en`  | WO     | `0` (không có phần tử lưu) |
| `0x004` | `SR` | `[31:4]` | reserved    | RO 0   | `0` |
| `0x004` | `SR` | `[3]`    | `overflow`  | RW0C   | giá trị flip-flop |
| `0x004` | `SR` | `[2:0]`  | `cnt`       | RO     | `count[2:0]` real-time |

Công thức readback dùng xuyên suốt Vplan:

```
read CR  ->  32'h0000_0000                       (mọi lúc, mọi wdata đã ghi trước đó)
read SR  ->  {28'h0, SR.overflow, count[2:0]}    == 32'h8 * overflow + cnt
read khác->  32'h0000_0000
rd_en=0  ->  32'h0000_0000
```

## 3. Ràng buộc quan trọng của môi trường verify

**`CR` không có readback.** Cả hai bit của `CR` là one-shot không có phần tử lưu, nên đọc `CR` luôn
trả `0`. Hệ quả trực tiếp cho Vplan: **không thể xác nhận một lệnh ghi `CR` bằng cách đọc lại `CR`**.
Cách duy nhất để biết lệnh ghi có tới đích là quan sát **hiệu ứng phụ qua `SR`**:

| Ghi vào `CR` | Bằng chứng đọc được qua `SR` |
|---|---|
| `CR.pulse_en = 1` | `SR.cnt` tăng 1 ở lần đọc kế tiếp |
| `CR.count_clr = 1` | `SR.cnt` về `0` |
| `CR = 0` hoặc chỉ reserved | `SR.cnt` không đổi |

Vì vậy mọi testcase ghi `CR` đều gồm 2 phần kiểm tra: (a) readback `CR` phải là `0`, và (b) hiệu ứng
phụ đúng/không có hiệu ứng phụ qua `SR`.

## 4. Môi trường và cách chạy

| Hạng mục | Lựa chọn |
|---|---|
| Mức verify | IP-level, chỉ qua CPU bus của `counter_top` (`wr_en`/`rd_en`/`addr`/`wdata`/`rdata`) |
| Vị trí bench | `tb/counter_top/` theo cấu trúc `CLAUDE.md` (`Makefile`, `script/`, `clock.vh`, `dut.vh`, `tb_*.sv`, `tc_list.md`) |
| Clock | 10 ns (100 MHz). Spec không quy định tần số ⇒ giá trị này là giả định của bench, không phải yêu cầu |
| Reset | `rst_n` giữ `0` ≥ 2 cycle rồi nhả; các TC riêng sẽ assert lại giữa cycle |
| BFM | `cpu_write(addr, wdata)`, `cpu_read(addr, rdata)`, `cpu_read_check(addr, exp, name)` trong `dut.vh`; mỗi lệnh chiếm đúng 1 cycle, **không ghi liên tiếp back-to-back** (spec không hỗ trợ) |
| Thời điểm lái tín hiệu | lái ở `negedge clk`, lấy mẫu `rdata` trong cùng cycle `rd_en = 1` |
| Self-check | so sánh trong bench; kết thúc in đúng một token `[FINISH] PASS` hoặc `[FINISH] FAIL` |
| Quan sát | **black-box** qua `rdata`. Không dùng probe nội bộ (`u_register.sr_overflow`, `count`) trong các TC của bản Vplan này |

## 5. Danh sách feature cần verify

| ID | Feature | Nguồn |
|----|---------|-------|
| F01 | Giá trị đọc về sau reset của `CR` và `SR` | spec §Register map, §Timing |
| F02 | Giải mã `addr` đủ 10 bit, không alias (`0x001`–`0x003`, `0x005`–`0x007`) | proposal §4.1, O5 |
| F03 | Địa chỉ không map đọc trả `0`, ghi không có tác dụng | proposal §4.5 |
| F04 | `rdata` bị gate bởi `rd_en` | proposal §4.5, O4 |
| F05 | `rdata` hợp lệ ngay trong cycle có `rd_en` (tổ hợp, không pipeline) | proposal O4 |
| F06 | `CR.pulse_en` là `WO`: ghi `1` sinh đúng 1 pulse, đọc lại `0` | spec §Register map |
| F07 | `CR.count_clr` là `W1P`: ghi `1` xoá, ghi `0` không tác dụng, đọc lại `0`, không dính mức | spec §Functional behavior, O1 |
| F08 | Bit reserved của `CR` ghi vào không có tác dụng | proposal §2.3 |
| F09 | `SR.cnt` là `RO`, phản ánh real-time `count[2:0]`, ghi không đổi được | spec §Functional behavior |
| F10 | `SR.overflow` là `RW0C`: ghi `0` clear, ghi `1` vô hiệu, không tự clear | spec §Timing, proposal §4.4 |
| F11 | Bit reserved của `SR` ghi vào không có tác dụng, đọc `0` | proposal §2.3 |
| F12 | Lệnh ghi chỉ có tác dụng khi `wr_en = 1` | proposal §4.1 |
| F13 | Reset bất đồng bộ đưa `SR` đọc về `0` | spec §Timing, O6 |

## 6. Danh sách testcase directed

8 testcase, mỗi testcase là một file `tb/counter_top/tb_<name>.sv`. Cột "Exp" là giá trị `rdata`
kỳ vọng.

### TC01 — `tb_reg_reset_value` · Giá trị reset (F01)

| # | Stimulus | Exp |
|---|---|---|
| 1 | Sau khi nhả reset: đọc `0x000` | `0x0000_0000` |
| 2 | Đọc `0x004` | `0x0000_0000` |
| 3 | Đọc lại `0x004` sau 5 cycle idle (không có lệnh nào) | `0x0000_0000` |

*Pass:* cả 3 check đúng ⇒ counter và cờ overflow đều khởi tạo `0`, không có giá trị rác.

### TC02 — `tb_reg_rd_path` · Đường đọc: gate, alias, địa chỉ không map (F02–F05)

Chuẩn bị: ghi `CR = 0x1` ba lần để `cnt = 3` (tạo dữ liệu đọc khác `0`).

| # | Stimulus | Exp |
|---|---|---|
| 1 | Đọc `0x004` | `0x0000_0003` |
| 2 | `rd_en = 0`, `addr = 0x004` | `0x0000_0000` |
| 3 | Đọc `0x001`, `0x002`, `0x003` (alias của `CR`) | `0x0000_0000` mỗi địa chỉ |
| 4 | Đọc `0x005`, `0x006`, `0x007` (alias của `SR`) | `0x0000_0000` mỗi địa chỉ |
| 5 | Đọc `0x008`, `0x00C`, `0x3FF` (không map) | `0x0000_0000` mỗi địa chỉ |
| 6 | Ghi `0x001 = 0x1`, `0x002 = 0x2`, `0x003 = 0x3`, `0x005 = 0x0`, rồi đọc `0x004` | `0x0000_0003` (không đổi) |
| 7 | Đọc `0x004` ngay trong cycle `rd_en` lên (lấy mẫu giữa cycle, không chờ cạnh clock) | `0x0000_0003` |

*Pass:* check 3–6 chứng minh decode đủ 10 bit; check 2 chứng minh gate `rd_en`; check 7 chứng minh
`rdata` tổ hợp, không pipeline.

### TC03 — `tb_reg_cr_write` · `CR` là WO/W1P, reserved vô hại (F06–F08)

| # | Stimulus | Exp |
|---|---|---|
| 1 | Ghi `CR = 0x0000_0001`, đọc `CR` | `0x0000_0000` (WO) |
| 2 | Đọc `SR` | `0x0000_0001` (pulse đã tới) |
| 3 | Ghi `CR = 0x0000_0002`, đọc `CR` | `0x0000_0000` |
| 4 | Đọc `SR` | `0x0000_0000` (đã xoá) |
| 5 | Ghi `CR = 0x0000_0000`, đọc `SR` | `0x0000_0000` (ghi `0` không tác dụng) |
| 6 | Ghi `CR = 0x0000_0001` hai lần, đọc `SR` | `0x0000_0002` (mỗi lệnh đúng **một** pulse) |
| 7 | Ghi `CR = 0xFFFF_FFFC` (chỉ reserved), đọc `SR` | `0x0000_0002` (không đổi) |
| 8 | Đọc `CR` | `0x0000_0000` |
| 9 | Ghi `CR = 0xFFFF_FFFF`, đọc `SR` | `0x0000_0000` (`count_clr` thắng `pulse`, O2) |
| 10 | Ghi `CR = 0x0000_0001`, đọc `SR` | `0x0000_0001` (`count_clr` **không dính mức**: vẫn đếm được sau khi xoá — bằng chứng W1P, O1) |

*Pass:* check 10 là check quan trọng nhất của TC này. Nếu `count_clr` bị hiện thực thành bit `RW` có
phần tử lưu thì nó sẽ giữ `1` và `SR.cnt` sẽ mãi là `0` ⇒ check 10 fail.

### TC04 — `tb_reg_sr_cnt_ro` · `SR.cnt` là RO và real-time (F09, F11)

| # | Stimulus | Exp |
|---|---|---|
| 1 | Từ reset, ghi `CR = 0x1` và đọc `SR` lặp 8 lần | `0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7`, rồi `0x8` (wrap về `cnt = 0`, overflow set) |
| 2 | Ghi `SR = 0x0` để clear cờ; ghi `CR = 0x1` 5 lần; đọc `SR` | `0x0000_0005` |
| 3 | Ghi `SR = 0x0000_0007` (định ghi `cnt = 7`, bit[3] = 0), đọc `SR` | `0x0000_0005` — `cnt` **không đổi** |
| 4 | Ghi `SR = 0xFFFF_FFFF`, đọc `SR` | `0x0000_0005` — reserved và `cnt` đều không ghi được |
| 5 | Đọc `SR` hai lần liên tiếp không có lệnh ghi xen vào | `0x0000_0005` cả hai lần |
| 6 | Ghi `CR = 0x1`, rồi đọc `SR` **ở cycle ngay sau** cycle ghi, **không có cycle trống ở giữa** | `0x0000_0006` (giá trị mới thấy được ngay, không trễ thêm cycle) |

> **Lưu ý cho người viết bench ở check 6:** phải là *liền kề* — ghi ở cycle N, `rd_en` lên ở cycle
> N+1. Nếu BFM chèn một cycle trống giữa write và read thì check này **mất tác dụng**: một hiện thực
> sai lấy `SR.cnt` từ flip-flop (thay vì `count` real-time) vẫn sẽ pass. Đây là lỗi thật đã gặp khi
> implement bench, phát hiện được nhờ mutation test (§13, M7).

*Pass:* check 3 và 4 dùng giá trị ghi (`7`) **khác** giá trị hiện tại (`5`) nên phân biệt được "RO"
với "ghi được"; nếu đảo thứ tự để hai giá trị trùng nhau thì check mất ý nghĩa.

### TC05 — `tb_reg_sr_ovf_rw0c` · `SR.overflow` là RW0C (F10, F11)

| # | Stimulus | Exp |
|---|---|---|
| 1 | Từ reset, ghi `CR = 0x1` 8 lần, đọc `SR` | `0x0000_0008` (cờ set, `cnt` wrap về 0) |
| 2 | Ghi `SR = 0x0000_0008` (ghi `1`), đọc `SR` | `0x0000_0008` — ghi `1` **không tác dụng** |
| 3 | Ghi `SR = 0x0000_000F`, đọc `SR` | `0x0000_0008` — bit[3] = 1 nên vẫn không clear |
| 4 | Đợi 5 cycle idle, đọc `SR` | `0x0000_0008` — **không tự clear theo thời gian** |
| 5 | Ghi `CR = 0x1` hai lần (pulse không tràn), đọc `SR` | `0x0000_000A` — cờ vẫn set, `cnt = 2` |
| 6 | Ghi `SR = 0x0000_0000`, đọc `SR` | `0x0000_0002` — ghi `0` clear cờ, `cnt` giữ nguyên |
| 7 | Ghi `CR = 0x1` 6 lần (2→7→wrap 0), đọc `SR` | `0x0000_0008` — set lại được sau khi clear |
| 8 | Ghi `SR = 0xFFFF_FFF7` (bit[3] = 0, mọi bit khác `1`), đọc `SR` | `0x0000_0000` — chỉ bit[3] bị clear, reserved vô hại |

*Pass:* check 4 và 5 chứng minh tính sticky; check 2, 3 chứng minh ghi `1` vô hiệu; check 6, 8 chứng
minh ghi `0` clear.

### TC06 — `tb_reg_wr_en_gate` · Lệnh ghi bị gate bởi `wr_en` (F12)

| # | Stimulus | Exp |
|---|---|---|
| 1 | Ghi `CR = 0x1` (đưa `cnt = 1`), đọc `SR` | `0x0000_0001` |
| 2 | Giữ `wr_en = 0`, đặt `addr = 0x000`, `wdata = 0x1` trong 3 cycle, đọc `SR` | `0x0000_0001` — không sinh pulse |
| 3 | Giữ `wr_en = 0`, `addr = 0x000`, `wdata = 0x2` trong 3 cycle, đọc `SR` | `0x0000_0001` — không xoá |
| 4 | Giữ `wr_en = 0`, `addr = 0x004`, `wdata = 0x0`, sau khi đã set cờ overflow, đọc `SR` | cờ vẫn set |
| 5 | `wr_en = 1` và `rd_en = 1` cùng cycle ở `addr = 0x000`: lấy mẫu `rdata` | `0x0000_0000` |
| 6 | Đọc `SR` ở cycle sau check 5 | `cnt` đã tăng 1 — lệnh ghi vẫn có tác dụng khi đọc đồng thời |

*Pass:* check 2–4 là các check chống "ghi nhầm khi không có `wr_en`". Check 5–6 là hành vi **ngoài
spec** (spec không định nghĩa đọc/ghi đồng thời); ghi lại kỳ vọng ở đây để tránh phải đoán khi debug,
và đánh dấu là *assumption*, không phải requirement.

### TC07 — `tb_reg_bit_sweep` · Quét từng bit `wdata` để bắt lệch bit-mapping (F06–F11)

| # | Stimulus | Exp |
|---|---|---|
| 1 | Với `i = 2..31`: ghi `CR = (1 << i)`, đọc `CR` rồi đọc `SR` | `CR` → `0`; `SR` → **không đổi** với mọi `i` (chỉ bit 0 và 1 của `CR` có tác dụng) |
| 2 | Với `i = 0..2` và `i = 4..31`: đặt cờ overflow rồi ghi `SR = 0xFFFF_FFFF & ~(1 << i)`, đọc `SR` | cờ **vẫn set** — chỉ bit[3] mới clear được |
| 3 | Đặt cờ overflow, ghi `SR = ~(1 << 3)` (`0xFFFF_FFF7`), đọc `SR` | cờ **clear** |

*Pass:* TC này bắt lỗi "lệch một bit" trong decode field — dạng lỗi mà các TC ở trên có thể bỏ qua vì
chỉ dùng vài giá trị cố định.

### TC08 — `tb_reg_reset_async` · Reset bất đồng bộ (F13)

| # | Stimulus | Exp |
|---|---|---|
| 1 | Ghi `CR = 0x1` 8 lần (`cnt` wrap, cờ overflow set), đọc `SR` | `0x0000_0008` |
| 2 | Hạ `rst_n = 0` **giữa cycle**, cách cạnh lên clock ≥ 2 ns; vẫn giữ `rst_n = 0`, đọc `SR` | `0x0000_0000` |
| 3 | Nhả `rst_n = 1`, đọc `CR` và `SR` | `0x0000_0000` cả hai |
| 4 | Ghi `CR = 0x1`, đọc `SR` | `0x0000_0001` — DUT hoạt động lại bình thường sau reset |

*Pass:* check 2 phải quan sát được **trong khi `rst_n` vẫn thấp** và tại thời điểm **không có cạnh
clock** — đó là điểm phân biệt reset bất đồng bộ (O6) với reset đồng bộ.

## 7. Ma trận truy vết feature ↔ testcase

| Feature | TC01 | TC02 | TC03 | TC04 | TC05 | TC06 | TC07 | TC08 |
|---------|:----:|:----:|:----:|:----:|:----:|:----:|:----:|:----:|
| F01 giá trị reset        | ✔ |   |   |   |   |   |   | ✔ |
| F02 decode 10 bit        |   | ✔ |   |   |   |   |   |   |
| F03 addr không map       |   | ✔ |   |   |   |   |   |   |
| F04 gate `rd_en`         |   | ✔ |   |   |   |   |   |   |
| F05 `rdata` tổ hợp       |   | ✔ |   | ✔ |   |   |   |   |
| F06 `pulse_en` WO        |   |   | ✔ | ✔ |   |   | ✔ |   |
| F07 `count_clr` W1P      |   |   | ✔ |   |   | ✔ | ✔ |   |
| F08 reserved `CR`        |   |   | ✔ |   |   |   | ✔ |   |
| F09 `cnt` RO real-time   |   | ✔ |   | ✔ | ✔ |   |   |   |
| F10 `overflow` RW0C      |   |   |   | ✔ | ✔ |   | ✔ |   |
| F11 reserved `SR`        |   |   |   | ✔ | ✔ |   | ✔ |   |
| F12 gate `wr_en`         |   |   |   |   |   | ✔ |   |   |
| F13 reset bất đồng bộ    |   |   |   |   |   |   |   | ✔ |

Mọi feature F01–F13 đều có ít nhất một testcase phủ.

## 8. Coverage mục tiêu (functional, đếm thủ công trong bench)

| Hạng mục | Mục tiêu |
|---|---|
| Địa chỉ được truy cập | `0x000`, `0x004`, alias `0x001`–`0x003`, `0x005`–`0x007`, ngoài map `0x008`, `0x00C`, `0x3FF` |
| Giá trị `SR.cnt` đọc được | đủ 8 giá trị `0`–`7` (TC04 check 1) |
| `SR.overflow` | cả hai mức `0`/`1`; chuyển `0→1` và `1→0`; giữ mức qua ≥ 5 cycle |
| Tổ hợp `wr_en`/`rd_en` | `00`, `01`, `10`, `11` |
| Bit `wdata` đã quét | toàn bộ 32 bit trên cả `CR` và `SR` (TC07) |
| Reset | 1 lần lúc khởi động (đồng bộ với cạnh) + 1 lần giữa cycle (TC08) |

## 9. Ngoài phạm vi của bản Vplan này

- **Chức năng đếm/tràn** như một mục tiêu verify riêng (wrap `7→0`, độ rộng `overflow` đúng 1 cycle,
  ưu tiên `count_clr` > `pulse`). Ở đây chúng chỉ được dùng để *quan sát* lệnh ghi `CR`. Cần một
  Vplan/bộ TC riêng cho phần datapath.
- **Ghi liên tiếp (back-to-back)** — spec ghi rõ không hỗ trợ.
- **Kiểm tra mức waveform/timing** (setup/hold, độ rộng xung ở mức ns), STA, CDC: một clock domain duy
  nhất, không có gì để check.
- **Random/constrained-random, functional coverage tự động, formal, assertion (SVA)**: bản này chỉ
  directed.
- **Tham số khác `CNT_W = 3`, `ADDR_W = 10`, `DATA_W = 32`** — ngoài phạm vi spec.
- **`rdata` dạng pipeline** — giả định O4 chốt là tổ hợp; nếu sau này đổi sang có pipeline thì TC02
  check 7 và TC04 check 6 phải viết lại.

## 10. Rủi ro và điểm không verify được bằng directed test ở IP level

| # | Vấn đề | Ghi chú |
|---|---|---|
| R1 | **Không tạo được va chạm `set` vs `clear` của `SR.overflow` (O3)** qua CPU bus. Event `overflow` chỉ sinh trong cycle có lệnh ghi `CR = 0x1`, còn lệnh clear là ghi vào `SR` — hai địa chỉ khác nhau nên **không thể cùng một cycle** trên một bus đơn. Quyết định O3 ("CPU ghi thắng") do đó **không quan sát được** ở mức này. | Muốn verify phải dùng white-box (force `overflow` hoặc bench ở mức `register`), hoặc chấp nhận để lại dạng *unverifiable by construction* và ghi vào báo cáo. Bản Vplan này chọn ghi nhận, không cố dựng. |
| R2 | `CR` không readback ⇒ mọi kết luận về lệnh ghi `CR` là **suy ra gián tiếp** qua `SR`. Nếu cả `register` và `counter` cùng sai một cách bù trừ nhau thì directed test ở IP level không phát hiện được. | Rủi ro chấp nhận được với thiết kế 4 flip-flop; bench mức submodule (`tb/register/`) sẽ khép lại nếu cần. |
| R3 | Tần số clock là giả định của bench (100 MHz), spec không quy định. | Không ảnh hưởng kết quả functional vì mọi check đều tính theo cycle. |
| R4 | TC06 check 5–6 (đọc/ghi đồng thời) kiểm tra hành vi **ngoài spec**. | Nếu sau này spec định nghĩa khác, TC này phải sửa — nó không phải bằng chứng vi phạm requirement. |

## 11. Tiêu chí PASS/FAIL và cách chạy

- Mỗi testcase self-check, in **đúng một** token kết luận ở cuối: `[FINISH] PASS` hoặc `[FINISH] FAIL`.
  `vtestrun` và `Makefile` của bench chỉ quyết định pass/fail dựa trên token này (theo `CLAUDE.md`).
- Mỗi check fail phải in: tên check, `addr`, `wdata` (nếu là ghi), giá trị nhận được, giá trị kỳ vọng,
  thời điểm `$time`.
- Một testcase PASS khi **toàn bộ** check của nó đúng. Vplan này coi là hoàn thành khi TC01–TC08 đều
  PASS.
- Chạy: `make` trong `tb/counter_top/` (dispatcher tự phát hiện `tb_*.sv`), hoặc `make TC=<tên>` cho
  một testcase.

## 12. Trạng thái

| Hạng mục | Trạng thái |
|---|---|
| Vplan | **Hoàn thành** (tài liệu này) |
| Bench | **Hoàn thành**: `tb/counter_top/test_bench.v` — một file Verilog-2005 chứa cả TC01–TC08 |
| Kết quả chạy | **8/8 testcase PASS, 154/154 check PASS**, token `[FINISH] PASS` (Icarus Verilog 12.0) |
| Công cụ | `iverilog -g2005 -Wall` + `vvp`. **Chưa chạy** Verilator lint, xvlog/xelab/xsim, Vivado — không có trong môi trường |

Bench được implement thành **một file duy nhất** (`test_bench.v`) theo yêu cầu, thay vì cấu trúc
`tb/<ip>/tb_<name>.sv` một-file-một-testcase mà `CLAUDE.md` quy định. Hệ quả: chỉ có **một** token
`[FINISH]` cho toàn bộ lần chạy, kèm dòng tóm tắt PASS/FAIL riêng cho từng TC. Mỗi TC tự reset DUT ở
đầu nên vẫn độc lập với nhau.

Các giá trị `Exp` trong §6 **không phải phỏng đoán**: chúng đã được đối chiếu với `rtl/` bằng bench
probe tạm trong lúc soạn Vplan, và sau đó bởi chính `test_bench.v`. Chúng vẫn là ràng buộc lấy từ
spec/proposal, nên nếu một check fail thì phải truy lại spec chứ không mặc định sửa kỳ vọng theo RTL.

## 13. Mutation test — đo khả năng phát hiện lỗi của bench

Bench pass trên RTL đúng **không** chứng minh nó bắt được lỗi. Để đo, 7 bug được tiêm vào bản copy
của `rtl/` (chạy ngoài repo, RTL trong repo không bị sửa) rồi chạy lại `test_bench.v`:

| # | Bug được tiêm | Kết quả | TC bắt được |
|---|---|---|---|
| M1 | `CR.count_clr` thành bit `RW` có phần tử lưu (phá O1) | **bắt được** | TC03 |
| M2 | `rdata` thành có pipeline (phá O4) | **bắt được** | TC02–TC08 |
| M3 | `SR.overflow`: `set` đè `clear` (phá O3) | **KHÔNG bắt được** | — |
| M4 | Decode word-aligned, bỏ 2 bit thấp (phá O5) | **bắt được** | TC02 |
| M5 | Reset thành đồng bộ (phá O6) | **bắt được** | TC08 |
| M6 | `SR.overflow` tự clear khi có pulse kế tiếp | **bắt được** | TC04–TC08 |
| M7 | `SR.cnt` readback lấy từ flip-flop thay vì `count` real-time | **bắt được** | TC04 |

**Tỷ lệ bắt: 6/7.** Trường hợp duy nhất trượt là **M3**, và đó **đúng như rủi ro R1 đã dự đoán**:
không thể dựng được va chạm `set`/`clear` của `SR.overflow` trên một bus CPU đơn, nên bench ở mức IP
về nguyên tắc không phân biệt được O3 đúng hay sai. Kết quả mutation test này là bằng chứng thực
nghiệm cho R1, không phải một lỗ hổng mới.

M7 ban đầu **cũng trượt** ở phiên bản bench đầu tiên vì BFM chèn một cycle trống giữa write và read.
Đã sửa bằng task `cpu_write_then_read_chk` (write cycle N, read cycle N+1, không gap) — xem lưu ý ở
TC04 check 6.
