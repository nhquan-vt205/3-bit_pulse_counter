# `demo/` — folder tạm chứa tài liệu thiết kế mới

Folder **tạm**, chỉ chứa **tài liệu**. Code nằm ở đúng vị trí thật của nó trong repo.

**Nội dung thử nghiệm:** thêm đường đọc cho `CR.count_clr` — bit này trước đây là W1P thuần tổ hợp
nên đọc `CR` luôn trả `32'h0`; bản này cho phép CPU đọc lại giá trị đã ghi.

## Tài liệu ở đây

```text
demo/
├── README.md                     // file này
├── doc/
│   ├── cr_readback_design.md     // tài liệu thiết kế: vấn đề, 2 phương án, RTL diff
│   └── cr_readback_diagram.html  // sơ đồ thiết kế mới (mở bằng trình duyệt)
└── vplan_cr_readback.md          // Vplan mới, 4 directed test
```

## Code ở đâu

| File | Vai trò |
|---|---|
| `rtl_demo/register.v` | **file RTL duy nhất thay đổi** — thêm `cr_clr_q` và nhánh đọc `cr_sel` |
| `rtl_demo/counter_top.v`, `rtl_demo/counter.v` | không đổi |
| `tb/counter_top/tbench.v` | testbench, 5 item `VP01`–`VP05` theo `doc/counter_top_vplan.xlsx` |
| `tb/counter_top/test_bench.v` | regression TC01–TC08 cũ, **không đổi**, vẫn chạy trên `rtl/` |
| `rtl/`, `doc/`, `ddoc/` | **không đụng tới** |

## Thay đổi RTL

Chỉ `rtl_demo/register.v`, hai chỗ:

1. Thêm flip-flop `cr_clr_q`, nạp `wdata[1]` mỗi khi có `cr_wr` (§4.3b).
2. Thêm nhánh `cr_sel` vào read mux, trả `cr_clr_q` ở bit[1] (§4.5).

Đường lệnh `count_clr` **không đổi** — vẫn `cr_wr & wdata[1]`, vẫn one-shot. `cr_clr_q` chỉ là bộ
quan sát, không lái gì ngoài mux đọc. Lý do ở `doc/cr_readback_design.md` §2.

## Chạy

```bash
cd tb/counter_top
iverilog -g2005 -Wall -s tbench -o sim.out \
    ../../rtl_demo/counter_top.v ../../rtl_demo/register.v \
    ../../rtl_demo/counter.v tbench.v
vvp sim.out
```

Kết quả: **5/5 item, 158/158 check, `[FINISH] PASS`** (Icarus Verilog 12.0).
Chưa chạy Verilator lint, xvlog/xelab/xsim hay Vivado — không có trong môi trường này.

## Tác động lên regression cũ

Đã chạy bộ TC01–TC08 (bản trước đây nằm trong `tbench.v`) trên RTL mới:
**153/154 check pass, đúng 1 check fail.**

| Check fail | Giá trị | Kết luận |
|---|---|---|
| TC03 check 3 — *"CR readback 0 (W1P)"* | nhận `0x0000_0002`, kỳ vọng `0x0000_0000` | **Đúng như mong đợi.** Check này khẳng định hành vi **cũ** (đọc `CR` luôn trả 0). Chính nó là thứ tính năng mới cố tình thay đổi. |

Không có check nào khác bị ảnh hưởng ⇒ thay đổi khoanh vùng gọn, không rò sang `SR`, decode, gate
`rd_en`/`wr_en`, hay reset.

## Cần bạn xác nhận

1. **Cách hiểu yêu cầu.** Bản này hiện thực *"thêm đường đọc"* theo nghĩa **readback shadow**: đọc
   được giá trị đã ghi, nhưng lệnh xoá vẫn là xung one-shot. Nếu ý bạn là biến `CR[1]` thành bit
   **mức** đúng như chữ "RW" trong spec (ghi `1` thì counter bị giữ ở `0` cho tới khi ghi `0`) thì
   đây là thiết kế khác và phải làm lại — xem §2 tài liệu thiết kế.
2. **Nếu đưa tính năng này vào `rtl/`** (bản có parameter) thì phải sửa `tb/counter_top/test_bench.v`
   TC03 check 3 cho khớp hành vi mới, và chạy lại toàn bộ 154 check.
3. **Chi phí:** +1 flip-flop trong `register` (toàn IP 4 → 5).
