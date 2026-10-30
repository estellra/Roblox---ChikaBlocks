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
   rojo plugin install
   ```
3. Mở place ChikaBlocks trong Studio, chạy `rojo serve`, rồi bấm **Connect** trong plugin Rojo.

## Lệnh thường dùng

| Lệnh | Tác dụng |
|---|---|
| `rojo serve` | Sync code từ `src/` sang Studio |
| `lune run tests/run.luau` | Chạy unit test cho logic trong `src/shared` |
| `stylua src tests` | Format code |
| `selene src` | Lint |

## Cấu trúc

| Thư mục | Vào Studio tại |
|---|---|
| `src/shared` | `ReplicatedStorage.Shared` (logic dùng chung cho client và server, không phụ thuộc Roblox API để test được bằng Lune) |
| `src/server` | `ServerScriptService.Server` |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` |
