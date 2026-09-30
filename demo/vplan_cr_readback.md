# Vplan (demo) — `counter_top` với `CR.count_clr` đọc được

> **DUT:** `demo/rtl_demo/` · **Bench:** `demo/tbench.v` · **Thiết kế:** `demo/doc/cr_readback_design.md`
> **Phạm vi:** vài directed test đơn giản theo đúng tinh thần Vplan cũ
> (`doc/counter_top_vplan.md`), **cộng thêm** phần kiểm tra đường đọc mới của `CR`.
> Bản này **không** phủ lại toàn bộ 13 feature của Vplan cũ — xem §5.

---

## 1. Mục tiêu

1. Đường đọc **mới** của `CR.count_clr` trả đúng giá trị ghi lần cuối.
2. `CR.pulse_en` và bit reserved của `CR` **vẫn** đọc về `0` — thêm readback cho bit[1] không được
   làm rò rỉ các bit khác.
3. **Không hồi quy:** `count_clr` vẫn là xung one-shot, counter **không** bị kẹt ở `0` sau khi ghi
   `1` vào `CR[1]`.
4. Đường `SR` và giải mã địa chỉ không bị ảnh hưởng.

## 2. Môi trường

Giống Vplan cũ: black-box qua CPU bus, clock 10 ns, lái ở `negedge`, lấy mẫu `rdata` trong cùng
cycle `rd_en`, mỗi TC tự reset DUT ở đầu, một token `[FINISH] PASS` / `[FINISH] FAIL` cho cả lần
chạy. Không ghi back-to-back.

Ký hiệu: `SR(ovf, cnt)` = `{28'h0, ovf, cnt}`. `CR(clr)` = `clr << 1`.

## 3. Danh sách testcase

### DTC01 — Giá trị reset

| # | Stimulus | Exp |
|---|---|---|
| 1 | Sau reset: đọc `CR` | `0x0000_0000` |
| 2 | Đọc `SR` | `0x0000_0000` |

*Ý nghĩa:* flip-flop shadow mới phải reset về `0`, không để giá trị rác.

### DTC02 — Đường đọc mới của `CR.count_clr` **(tính năng mới)**

| # | Stimulus | Exp |
|---|---|---|
| 1 | Ghi `CR = 0x2`, đọc `CR` | **`0x0000_0002`** |
| 2 | Ghi `CR = 0x0`, đọc `CR` | `0x0000_0000` |
| 3 | Ghi `CR = 0x1`, đọc `CR` | `0x0000_0000` — bit[1] ghi `0`; bit[0] là WO nên không hiện |
| 4 | Ghi `CR = 0x3`, đọc `CR` | `0x0000_0002` — chỉ bit[1] đọc được |
| 5 | Ghi `CR = 0xFFFF_FFFF`, đọc `CR` | `0x0000_0002` — reserved vẫn đọc `0` |
| 6 | Đọc `CR` lần nữa (không ghi gì) | `0x0000_0002` — đọc không phá giá trị |
| 7 | Ghi `SR = 0x0`, đọc `CR` | `0x0000_0002` — ghi `SR` **không** nạp shadow |
| 8 | Đọc `0x001`, `0x002`, `0x003` | `0x0000_0000` mỗi địa chỉ |

*Ý nghĩa:* check 3–5 chốt rằng chỉ bit[1] đọc được. Check 7 chốt rằng shadow chỉ nạp khi `cr_wr`.
Check 8 quan trọng hơn trước: giờ `CR` có nội dung khác `0`, nên lỗi decode sẽ **rò rỉ** ra địa chỉ
lân cận — điều mà Vplan cũ không thể phát hiện vì `CR` luôn đọc `0`.

### DTC03 — Không hồi quy: `count_clr` vẫn one-shot **(quan trọng nhất)**

| # | Stimulus | Exp |
|---|---|---|
| 1 | Từ reset, ghi `CR = 0x1` ba lần, đọc `SR` | `SR(0,3)` = `0x0000_0003` |
| 2 | Ghi `CR = 0x2`, đọc `SR` | `SR(0,0)` = `0x0000_0000` — đã xoá |
| 3 | Đọc `CR` | `0x0000_0002` — shadow đang giữ `1` |
| 4 | Ghi `CR = 0x1`, đọc `SR` | **`SR(0,1)` = `0x0000_0001`** |
| 5 | Ghi `CR = 0x1`, đọc `SR` | `SR(0,2)` |
| 6 | Đọc `CR` | `0x0000_0000` — shadow đã bị ghi đè bởi `wdata[1] = 0` |

*Ý nghĩa:* **check 4 là check sống còn của bản thiết kế này.** Tại cycle ghi ở check 4, `cr_clr_q`
vẫn đang là `1` (nó chỉ cập nhật ở cạnh kết thúc cycle đó). Nếu ai đó nối `count_clr = cr_clr_q`
(tức là rơi về phương án A trong tài liệu thiết kế), thì `count_clr` sẽ là `1` ngay trong cycle đó,
thắng `pulse`, và `SR` sẽ đọc về `0x0` thay vì `0x1` ⇒ check fail. Đây chính là cơ chế phát hiện
lỗi mà shadow phải vượt qua.

### DTC04 — `SR` và giải mã địa chỉ không đổi

| # | Stimulus | Exp |
|---|---|---|
| 1 | Từ reset, ghi `CR = 0x1` tám lần, đọc `SR` | `SR(1,0)` = `0x0000_0008` — wrap + set cờ |
| 2 | Ghi `SR = 0x0000_0008` (ghi `1`), đọc `SR` | `0x0000_0008` — không tác dụng |
| 3 | Ghi `SR = 0x0000_0000`, đọc `SR` | `0x0000_0000` — clear |
| 4 | `rd_en = 0` với `addr = 0x000` | `0x0000_0000` — `rdata` vẫn bị gate |
| 5 | Đọc `0x008` (không map) | `0x0000_0000` |

*Ý nghĩa:* check 4 đáng giá hơn trước — với readback mới, nếu quên gate `rd_en` thì `CR` sẽ rò ra
ngoài ngay cả khi không có lệnh đọc.

## 4. Truy vết mục tiêu ↔ testcase

| Mục tiêu (§1) | DTC01 | DTC02 | DTC03 | DTC04 |
|---|:---:|:---:|:---:|:---:|
| 1 — đọc được `CR.count_clr` | ✔ | ✔ | ✔ | |
| 2 — bit khác vẫn đọc `0` | | ✔ | | |
| 3 — không hồi quy one-shot | | | ✔ | |
| 4 — `SR` và decode không đổi | | ✔ | | ✔ |

## 5. Ngoài phạm vi

Bản Vplan này **cố ý nhỏ**. Những thứ sau đã được phủ bởi Vplan cũ và **không** lặp lại ở đây:
quét từng bit `wdata` (TC07 cũ), gate `wr_en` (TC06 cũ), reset bất đồng bộ giữa cycle (TC08 cũ),
quét đủ 8 giá trị `cnt` (TC04 cũ), toàn bộ `RW0C` của `SR.overflow` (TC05 cũ).

Nếu bản demo này được chọn để đưa vào luồng chính thì phải **chạy lại đầy đủ Vplan cũ** trên RTL
mới, không chỉ Vplan này — thêm một flip-flop vào read mux là thay đổi có thể ảnh hưởng tới các
check đó.

Vẫn không verify được: va chạm `set`/`clear` của `SR.overflow` (R1 của Vplan cũ) — nguyên nhân
không đổi.

## 6. Tiêu chí PASS/FAIL

Mỗi check self-check trong `demo/tbench.v`; in một dòng PASS/FAIL cho từng DTC và **đúng một** token
`[FINISH] PASS` / `[FINISH] FAIL` ở cuối. Một DTC PASS khi toàn bộ check của nó đúng.

## 7. Trạng thái

| Hạng mục | Trạng thái |
|---|---|
| Vplan | Hoàn thành (tài liệu này) |
| Bench | `demo/tbench.v` |
| Kết quả chạy | **4/4 DTC PASS, 23/23 check PASS**, `[FINISH] PASS` (Icarus Verilog 12.0) |
| Kiểm tra khả năng bắt lỗi | Tiêm bug `count_clr = cr_clr_q` (phương án A) vào bản copy RTL → **DTC03 fail ở check 4 và 5**, `[FINISH] FAIL`. Ba DTC còn lại vẫn PASS, đúng như mong đợi: chỉ DTC03 được thiết kế để bắt ca này |
| Verilator / xsim / Vivado | Chưa chạy — không có trong môi trường |
