# Module Specification: 3-bit Pulse Counter (Register Design Practice)

> Nguồn: `ic_overview_session13_register_practice.pdf` — Session 13: Register Design Practice
> Khóa học: ICTC – Thiết kế vi mạch cơ bản (RTL Design and Verification)

## 1. Tổng quan module

Module là một **bộ đếm xung 3-bit (3-bit pulse counter)** có **reset bất đồng bộ (async reset)**, được điều khiển thông qua một khối **Register** (CSR – Control/Status Register interface).

### Sơ đồ khối (counter_top)

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

Module `counter_top` gồm 2 khối con:
- **Register**: giải mã địa chỉ, xử lý đọc/ghi CR/SR, sinh các tín hiệu điều khiển (`pulse`, `count_clr`) đưa xuống `counter`, đồng thời nhận trạng thái (`overflow`, `count[2:0]`) từ `counter` để phản ánh vào SR khi đọc.
- **counter**: logic đếm 3-bit thực tế, xử lý pulse, clear, và phát hiện overflow.

### Danh sách tín hiệu top-level (counter_top)

| Tên tín hiệu | Hướng | Độ rộng | Mô tả |
|---|---|---|---|
| `clk` | input | 1 | Xung clock hệ thống |
| `rst_n` | input | 1 | Reset bất đồng bộ, tích cực mức thấp |
| `wr_en` | input | 1 | Enable ghi vào register |
| `rd_en` | input | 1 | Enable đọc từ register |
| `addr[9:0]` | input | 10 | Địa chỉ thanh ghi |
| `wdata[31:0]` | input | 32 | Dữ liệu ghi |
| `rdata[31:0]` | output | 32 | Dữ liệu đọc ra |

### Tín hiệu nội bộ giữa Register và counter

| Tên tín hiệu | Hướng (từ Register → counter, hoặc ngược lại) | Mô tả |
|---|---|---|
| `pulse` | Register → counter | Xung tạo ra khi ghi 1 vào `CR.pulse_en` |
| `count_clr` | Register → counter | Xung/mức xóa bộ đếm khi ghi 1 vào `CR.count_clr` |
| `overflow` | counter → Register | Báo hiệu tràn số đếm (pulse) khi counter đang ở giá trị max mà vẫn có lệnh pulse |
| `count[2:0]` | counter → Register | Giá trị đếm hiện tại, phản ánh vào `SR.cnt` |

## 2. Yêu cầu chức năng (Functional Requirements)

### 2.1. Pulse generation & increment
- Khi ghi giá trị `1` vào `CR.pulse_en`, module sinh ra một xung (`pulse`) và bộ đếm (`counter`) tăng thêm 1.
- Module **không hỗ trợ ghi liên tục** (continuous write) — chỉ cho phép xảy ra **1 lệnh ghi tại một thời điểm**.

### 2.2. Clear counter
- Ghi `CR.count_clr = 1` sẽ xóa bộ đếm về `0` (thể hiện qua tín hiệu `count_clr`).

### 2.3. Overflow condition
- Nếu một pulse được sinh ra (ghi 1 vào `CR.pulse_en`) trong khi bộ đếm **đã ở giá trị lớn nhất** (`3'b111`), thì xảy ra **overflow** (thể hiện qua tín hiệu `overflow`).
- Khi overflow xảy ra: `SR.overflow` được set lên `1` và **giữ nguyên giá trị 1** cho đến khi bị xóa bằng cách **ghi 0** vào nó (ghi 0 vào `SR.overflow`).

### 2.4. Status monitoring
- Giá trị bộ đếm hiện tại có thể được giám sát/đọc thông qua `SR.cnt[2:0]`.

## 3. Đặc tả thanh ghi (Register Specification)

### 3.1. CR – Control Register (addr = 10'h0)

| Bit | Name | Type | Default | Mô tả |
|---|---|---|---|---|
| 31:2 | Reserved | RO | 30'b0 | Reserved |
| 1 | count_clr | RW | 1'b0 | Counter clear.<br>0: không xóa counter<br>1: xóa counter |
| 0 | pulse_en | WO | 1'b0 | Ghi 1 để sinh 1 pulse.<br>Ghi 0 không có tác dụng.<br>Đọc luôn trả về 0 |

### 3.2. SR – Status Register (addr = 10'h4)

| Bit | Name | Type | Default | Mô tả |
|---|---|---|---|---|
| 31:4 | Reserved | RO | 28'b0 | Reserved |
| 3 | overflow | RW0C | 1'b0 | 1: overflow đã xảy ra<br>0: chưa có overflow<br>Ghi 0 để xóa (clear). Ghi 1 không có tác dụng. |
| 2:0 | cnt | RO | 3'h0 | Giá trị hiện tại của bộ đếm |

**Ghi chú về register type:**
- `RO` (Read Only): chỉ đọc.
- `RW` (Read/Write): đọc/ghi bình thường.
- `WO` (Write Only): chỉ ghi, đọc luôn trả về giá trị mặc định (0).
- `RW0C` (Read/Write 1 to Clear... nhưng ở đây quy ước ngược: Write-0-to-Clear): đọc trả về giá trị hiện tại; ghi `0` sẽ xóa bit về 0; ghi `1` không có tác dụng.

## 4. Waveform mẫu (trạng thái khởi tạo, dùng làm template)

Định dạng WaveDrom, dùng làm khung sườn để vẽ waveform minh họa các case: pulse_en, count_clr, overflow.

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

Học viên cần tự vẽ tiếp waveform minh họa đầy đủ các case theo yêu cầu chức năng ở mục 2 (ghi pulse_en → pulse + tăng count; ghi count_clr → reset count; pulse khi count=max → overflow set SR.overflow; ghi 0 vào SR.overflow → clear).

### Waveform tự vẽ (minh họa case pulse_en → increment → overflow)

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

Học viên cần tự vẽ tiếp waveform minh họa đầy đủ các case theo yêu cầu chức năng ở mục 2 (ghi pulse_en → pulse + tăng count; ghi count_clr → reset count; pulse khi count=max → overflow set SR.overflow; ghi 0 vào SR.overflow → clear).

## 5. Quy trình thực hành trên lớp (Practice Flow)

| Bước | Nội dung | Thời gian |
|---|---|---|
| 1 | Tự nghiên cứu specification | 10 phút (19h10–19h20) |
| 2 | Q&A với giảng viên để hiểu rõ yêu cầu | 15 phút (19h20–19h35) |
| 3 | Vẽ waveform theo template | 15 phút (19h35–19h50) |
| 4 | Trình bày và giải thích waveform trước lớp (GV chọn 1-2 SV) | 10 phút (19h50–20h00) |
| 5 | Giảng viên giải thích waveform mẫu, Q&A | 15 phút (20h00–20h15) |
| 6 | Vẽ logic diagram hiện thực hóa waveform trên (logic sinh pulse từ write command; logic của SR.overflow) | 15 phút (20h15–20h30) |
| 7 | Trình bày và giải thích logic diagram | 10 phút (20h30–20h40) |
| 8 | Giảng viên giải thích diagram mẫu | 15 phút (20h40–20h55) |

RTL code và testbench sẽ được hoàn thành trong phần bài tập về nhà (homework).

## 6. Yêu cầu bài tập về nhà (Homework)

Tạo thư mục `13_ss13` dưới home directory, và bên trong tạo thư mục `pulse_counter` chứa các nội dung sau (tổng 20 điểm, 10 điểm đầu tính mức chuẩn, phần còn lại là mức nâng cao):

| Yêu cầu | Điểm |
|---|---|
| Vẽ lại waveform | 2p |
| Vẽ **đầy đủ (full)** logic diagram của module | 4p |
| Hoàn thành RTL code | 6p |
| Tạo Vplan (verification plan) | 2p |
| Sinh testbench và verify cho thiết kế | 6p |

Nộp toàn bộ tài liệu bao gồm: waveform, logic diagram, Vplan trong báo cáo (report).
