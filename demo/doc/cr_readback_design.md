# Thiết kế mới — bổ sung logic đọc cho `CR.count_clr`

> **Trạng thái:** bản thử nghiệm trong folder tạm `demo/`. **Không** thay thế thiết kế chính trong
> `rtl/`, `doc/`, `tb/`.
> **Gốc:** `ddoc/3-bit_pulse_counter_spec.md` · `ddoc/counter_top_proposal.md` · `rtl/register.v`
> **Sơ đồ:** `demo/doc/cr_readback_diagram.html`
> **RTL:** `rtl_demo/register.v` (chỉ file này đổi) · **Bench:** `tb/counter_top/tbench.v`

---

## 1. Vấn đề

Trong thiết kế hiện tại, `CR[1] count_clr` là **W1P thuần tổ hợp, không có phần tử lưu**:

```
count_clr = cr_wr & wdata[1]        // one-shot
read CR   = 32'h0                   // luôn luôn 0
```

Hệ quả: **CPU không có cách nào đọc lại xem mình đã ghi gì vào `CR[1]`**. Với firmware, đây là điểm
khó chịu quen thuộc — không read-modify-write được, không tự kiểm tra được lệnh ghi có tới đích
không, và không debug được qua register dump.

Nhắc lại vì sao ban đầu nó không có readback: `spec.md` §Register map ghi access là `RW`, nhưng phần
mô tả lại nói *"write 1 to clear the counter, write 0 has no effect"*. Nếu hiện thực đúng nghĩa `RW`
— tức là bit có flip-flop **và** flip-flop đó lái `count_clr` — thì sau khi ghi `1` bit sẽ dính `1`
vĩnh viễn và **giữ counter ở 0 mãi mãi**. Đó là lý do quyết định **O1** chọn one-shot và coi chữ
"RW" là lỗi soạn thảo.

## 2. Hai phương án

| | **A — `RW` đúng nghĩa** | **B — shadow readback** (chọn) |
|---|---|---|
| Phần tử lưu | 1 FF | 1 FF |
| FF lái gì | `count_clr = cr_clr_q` | **không lái gì** ngoài read mux |
| `count_clr` | mức, giữ `1` cho tới khi ghi `0` | vẫn one-shot như cũ |
| Đọc `CR[1]` | giá trị đang lưu | giá trị **ghi lần cuối** |
| Counter sau khi ghi `1` | **kẹt ở 0 vĩnh viễn** | đếm bình thường trở lại |
| Phá vỡ O1 | **có** | không |
| Tương thích ngược | **không** — đổi hành vi đếm | **có** — chỉ thêm đường đọc |

**Chọn B.** Yêu cầu đặt ra là *"bổ sung logic đọc"*, không phải *"đổi cách xoá counter"*. Phương án B
làm đúng một việc đó: thêm một flip-flop **chỉ để quan sát**, còn đường lệnh `count_clr` giữ nguyên
không đụng tới.

> **Giả định cần bạn xác nhận:** nếu ý bạn thực sự là phương án A (biến `CR[1]` thành bit mức đúng
> như chữ "RW" trong spec, chấp nhận counter bị giữ ở 0 cho tới khi ghi `0`) thì đây là **thiết kế
> khác hẳn** và tôi phải làm lại. Bản này cố ý **không** đi theo hướng đó vì nó lật lại O1 mà bạn đã
> chốt ngày 2026-09-29.

## 3. Thay đổi RTL

Chỉ `rtl_demo/register.v`. Hai chỗ:

**(a) Thêm flip-flop shadow** — nạp giá trị `wdata[1]` mỗi khi có lệnh ghi vào `CR`:

```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)     cr_clr_q <= 1'b0;
    else if (cr_wr) cr_clr_q <= wdata[CR_CLR_BIT];
end
```

**(b) Thêm nhánh `cr_sel` vào read mux** — trước đây nhánh này không tồn tại nên `CR` rơi vào default
`32'h0`:

```verilog
always @(*) begin
    rd_word = {DATA_W{1'b0}};
    if (cr_sel) begin
        rd_word[CR_CLR_BIT] = cr_clr_q;      // MỚI
    end else if (sr_sel) begin
        rd_word[CNT_W-1:0]  = count;
        rd_word[SR_OVF_BIT] = sr_overflow;
    end
end
```

**Đường lệnh không đổi một dòng nào:**

```verilog
assign pulse     = cr_wr & wdata[CR_PULSE_BIT];
assign count_clr = cr_wr & wdata[CR_CLR_BIT];     // vẫn là one-shot tổ hợp
```

Đây là điểm mấu chốt cần review kỹ: `cr_clr_q` **không** xuất hiện ở vế phải của `count_clr`. Nếu ai
đó "dọn dẹp" code và nối `count_clr = cr_clr_q` thì lập tức thành phương án A và counter kẹt ở 0.

## 4. Register map sau thay đổi

| Addr | Reg | Bits | Field | Access cũ | **Access mới** | Readback |
|---|---|---|---|---|---|---|
| `0x000` | `CR` | `[31:2]` | reserved | RO 0 | RO 0 | `0` |
| `0x000` | `CR` | `[1]` | `count_clr` | W1P | **RW1P** | **giá trị ghi lần cuối** |
| `0x000` | `CR` | `[0]` | `pulse_en` | WO | WO | `0` |
| `0x004` | `SR` | `[31:4]` | reserved | RO 0 | RO 0 | `0` |
| `0x004` | `SR` | `[3]` | `overflow` | RW0C | RW0C | FF |
| `0x004` | `SR` | `[2:0]` | `cnt` | RO | RO | `count[2:0]` |

`RW1P` = đọc được giá trị đã ghi, nhưng tác dụng xoá vẫn là xung một cycle khi ghi `1`.

## 5. Bảng hành vi

Xuất phát từ reset, `cnt = 0`:

| # | Lệnh | `count_clr` xung? | `cnt` sau đó | Đọc `CR` |
|---|---|---|---|---|
| 1 | reset | — | `0` | `0x0000_0000` |
| 2 | ghi `CR = 0x1` (pulse) | không | `1` | `0x0000_0000` — bit[1] ghi `0` |
| 3 | ghi `CR = 0x2` (clear) | **có** | `0` | **`0x0000_0002`** ← mới |
| 4 | ghi `CR = 0x1` | không | `1` | `0x0000_0000` |
| 5 | ghi `CR = 0x3` (cả hai) | **có** | `0` | **`0x0000_0002`** — bit[0] vẫn đọc `0` |
| 6 | ghi `CR = 0x0` | không | giữ | `0x0000_0000` |
| 7 | ghi `CR = 0xFFFF_FFFF` | **có** | `0` | **`0x0000_0002`** — reserved vẫn đọc `0` |
| 8 | ghi `SR = ...` | không | giữ | **không đổi** — `cr_clr_q` chỉ nạp khi `cr_wr` |

Dòng 4 là dòng quan trọng nhất: sau khi ghi `1` ở dòng 3, counter **vẫn đếm được**. Đó là bằng chứng
`cr_clr_q` không lái `count_clr`.

## 6. Ảnh hưởng

| Hạng mục | Trước | Sau |
|---|---|---|
| FF trong `u_register` | 1 (`sr_overflow`) | **2** (`sr_overflow`, `cr_clr_q`) |
| FF toàn IP | 4 | **5** |
| Đường tổ hợp `pulse` / `count_clr` | không đổi | không đổi |
| Độ trễ `rdata` | tổ hợp, cùng cycle | không đổi |
| Waveform mẫu của spec | khớp | vẫn khớp |
| Decode địa chỉ | không đổi | không đổi |

## 7. Những gì **không** đổi

- `rtl/`, `doc/`, `ddoc/` và `tb/counter_top/test_bench.v` của luồng chính — thay đổi chỉ nằm trong
  `rtl_demo/register.v` và `tb/counter_top/tbench.v`.
- `rtl_demo/counter.v` và `rtl_demo/counter_top.v` không đổi.
- Toàn bộ hành vi của `SR`, của bộ đếm, và của `CR.pulse_en`.
- Các quyết định O2 (clear thắng pulse), O3 (clear thắng set), O4, O5, O6.

## 8. Trạng thái kiểm tra

| Hạng mục | Kết quả |
|---|---|
| `iverilog -g2005 -Wall` trên `rtl_demo/` | sạch, không cảnh báo |
| `tb/counter_top/tbench.v` (checklist `doc/counter_top_vplan.xlsx`) | 5/5 item VP01–VP05, 158/158 check, `[FINISH] PASS` |
| Regression TC01–TC08 cũ trên RTL mới | 153/154 pass; 1 fail là TC03 check 3, đúng như mong đợi |
| Verilator lint / xsim / Vivado | **chưa chạy** — không có trong môi trường |
