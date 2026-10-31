# ChikaBlock

Game xếp khối 8x8 trên Roblox. Kế hoạch và các quyết định thiết kế nằm trong [docs/PLAN.md](docs/PLAN.md).

## Cài đặt lần đầu

1. Cài [Rokit](https://github.com/rojo-rbx/rokit) (PowerShell):
   ```powershell
   Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression
   ```
2. Mở lại terminal, sau đó trong thư mục repo chạy:
   ```bash
   rokit install
   wally install
   rojo plugin install
   ```
   `wally install` tải các package (ProfileStore) vào `ServerPackages/` (không commit thư mục này).
3. Mở place ChikaBlocks trong Studio, chạy `.\scripts\serve.ps1` (PowerShell), rồi bấm **Connect** trong plugin Rojo.

> **Rojo 7.7 có thể crash** khi file được lưu kiểu ghi file tạm rồi đổi tên (một số editor và công cụ sửa code làm vậy), xem [rojo-rbx/rojo#1314](https://github.com/rojo-rbx/rojo/issues/1314). `scripts/serve.ps1` tự chạy lại server sau mỗi lần crash. Nếu plugin trong Studio báo *Couldn't connect to the Rojo server*, chỉ cần bấm **Connect** lại.

## Lệnh thường dùng

| Lệnh | Tác dụng |
|---|---|
| `.\scripts\serve.ps1` | Sync code từ `src/` sang Studio (`rojo serve`, tự chạy lại nếu crash) |
| `lune run tests/run.luau` | Chạy unit test cho logic trong `src/shared` |
| `stylua src tests` | Format code |
| `selene src` | Lint |

## Cấu trúc

| Thư mục | Vào Studio tại |
|---|---|
| `src/shared` | `ReplicatedStorage.Shared` (logic dùng chung cho client và server, không phụ thuộc Roblox API để test được bằng Lune) |
| `src/server` | `ServerScriptService.Server` |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` |
