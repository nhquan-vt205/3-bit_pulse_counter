# `demo/` — folder tạm cho bản thử nghiệm

Khu vực **tạm**, tách hẳn khỏi luồng thiết kế chính. Không có gì trong `rtl/`, `doc/`, `tb/`,
`ddoc/` bị thay đổi bởi folder này.

**Nội dung thử nghiệm:** thêm đường đọc cho `CR.count_clr` — bit này trước đây là W1P thuần tổ hợp
nên đọc `CR` luôn trả `32'h0`; bản demo cho phép CPU đọc lại giá trị đã ghi.

## Cấu trúc

```text
demo/
├── README.md                     // file này
├── doc/
│   ├── cr_readback_design.md     // tài liệu thiết kế: vấn đề, 2 phương án, RTL diff
│   └── cr_readback_diagram.html  // sơ đồ thiết kế mới (mở bằng trình duyệt)
├── rtl_demo/
│   ├── counter_top.v             // bản sao y nguyên
│   ├── counter.v                 // bản sao y nguyên
│   └── register.v                // ★ file duy nhất có thay đổi
├── vplan_cr_readback.md          // Vplan mới, 4 directed test
└── tbench.v                      // testbench, implement DTC01..DTC04
```

## Thay đổi so với `rtl/`

Chỉ `register.v`, hai chỗ:

1. Thêm flip-flop `cr_clr_q`, nạp `wdata[1]` mỗi khi có `cr_wr`.
2. Thêm nhánh `cr_sel` vào read mux, trả `cr_clr_q` ở bit[1].

Đường lệnh `count_clr` **không đổi** — vẫn là `cr_wr & wdata[1]`, vẫn one-shot. `cr_clr_q` chỉ là
bộ quan sát, không lái gì ngoài mux đọc. Chi tiết và lý do ở `doc/cr_readback_design.md` §2.

## Chạy

```bash
cd demo
iverilog -g2005 -Wall -s tbench -o sim.out \
    rtl_demo/counter_top.v rtl_demo/register.v rtl_demo/counter.v tbench.v
vvp sim.out
```

Kết quả hiện tại: **4/4 testcase, 23/23 check, `[FINISH] PASS`** (Icarus Verilog 12.0).
Chưa chạy Verilator lint, xvlog/xelab/xsim hay Vivado — không có trong môi trường này.

## Cần bạn xác nhận trước khi đưa vào luồng chính

1. **Cách hiểu yêu cầu.** Bản này hiện thực *"thêm đường đọc"* theo nghĩa **readback shadow**: đọc
   được giá trị đã ghi, nhưng lệnh xoá vẫn là xung one-shot. Nếu ý bạn là biến `CR[1]` thành bit
   **mức** đúng như chữ "RW" trong spec (ghi `1` thì counter bị giữ ở `0` cho tới khi ghi `0`) thì
   đây là thiết kế khác và phải làm lại — xem §2 của tài liệu thiết kế.
2. **Vplan này cố ý nhỏ**, chỉ 4 testcase. Nếu chọn đưa vào luồng chính thì phải **chạy lại đầy
   đủ Vplan cũ** (`doc/counter_top_vplan.md`, 8 testcase / 154 check) trên RTL mới, vì thêm một
   flip-flop vào read mux có thể ảnh hưởng tới các check đó.
3. **Chi phí:** +1 flip-flop trong `u_register` (tổng IP 4 → 5).
