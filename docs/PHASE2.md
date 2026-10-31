# Giai đoạn 2: MVP đủ để publish

Mục tiêu theo [PLAN.md](PLAN.md): game an toàn trước gian lận, lưu được điểm, có hồi sinh bằng Robux, có giao diện thật, người mới hiểu cách chơi trong 15 giây.

## Các mốc

| Mốc | Nội dung | Cần trước | Trạng thái |
|---|---|---|---|
| **M6** Server giữ quyền quyết định | `GameService` chạy `GameSession` trên server, seed bí mật, client dự đoán và đồng bộ lại khi lệch | Không | ✅ Xong |
| **M7** Lưu dữ liệu | ProfileStore (qua Wally): best, số ván, cờ "đã xem tutorial" | Bật *Enable Studio Access to API Services* | |
| **M8** Hồi sinh bằng Robux | Developer Product, `ProcessReceipt` an toàn khi gọi lặp, giá tăng dần | Giá Robux, tạo product, chọn Group hay cá nhân | |
| **M9** Menu, tutorial, gamepad | Màn hình chính, tutorial lần đầu (seed cố định), Input Action System | Ngôn ngữ | |
| **M10** Giao diện thật | Làm lại `Views/` theo mockup, linh vật, SFX/VFX, khay to hơn ở màn ngang | Tên game, linh vật, mockup | |
| **M11** Publish thử và QA | ≥95% test không lỗi, thử người mới, thử mạng chậm | Không | |

## M6: Server giữ quyền quyết định

### Thiết kế

```
Client                                         Server (GameService → GameRuns)
  │ StartGame()  ─────────────────────────────▶  ván mới, seed bí mật (Random.new)
  │ ◀──── GameState(state, "start") ──────────── snapshot ván, runId, best
  │
  │ đặt khối ngay trên GameSession của client (dự đoán)
  │ PlacePiece(runId, moveIndex, slot, x, y) ─▶  giới hạn tần suất → kiểm tra → session:place
  │ ◀──── MoveResult(runId, moveIndex, score, set?, isOver, best)
  │   hoặc
  │ ◀──── GameState(state, "resync") ─────────── nước đi sai hoặc client vượt trước server
  │ RequestState() ───────────────────────────▶  client thấy lệch, hoặc nước đi quá 2 giây chưa được xác nhận
```

- **Remote** (`src/shared/Net.luau`): `StartGame`, `PlacePiece`, `RequestState` (client → server); `GameState`, `MoveResult` (server → client). Plan ban đầu có 3 remote. Mình tách thêm `RequestState` và `MoveResult`, để server không phải tin con số điểm do client gửi lên.
- **`GameSession`:** nguồn bộ khối được phép trả về `nil`. Khi đó khay chờ bộ mới (`awaitingSet`, chưa tính là thua) cho tới khi `receiveSet()` được gọi. Có thêm `snapshot()` và `fromSnapshot()`.
- **`GameRuns`** (`src/server/GameRuns.luau`):
  - Logic thuần; module dùng chung, đồng hồ và seed đều truyền vào qua tham số, nên test được bằng Lune.
  - Kiểm tra `runId` và `moveIndex`: nước có chỉ số cũ thì bỏ qua; client vượt trước server thì gửi lại trạng thái đầy đủ.
  - Giới hạn tần suất bằng token bucket: đặt khối 8 nước/giây, `StartGame` 1 lần mỗi 0,5 giây, `RequestState` 2 lần/giây.
- **`GameService`:** nối remote với `GameRuns`, dọn dữ liệu khi người chơi rời, giữ best trong bộ nhớ (M7 sẽ lưu bằng ProfileStore).
- **`GameController` (client):**
  - Dự đoán từng nước và so điểm, trạng thái thua với `MoveResult`.
  - Lệch thì lặng lẽ lấy trạng thái của server; trong Studio có cảnh báo ra Output.
  - `StartGame` không được trả lời sau 3 giây thì tự gửi lại.
- **Debug chỉ chạy trong Studio:** `ServerStorage.ChikaServerDebug` (lệnh `state`) để so ván phía server với client.

### Quyết định khi review plan M6

| Điểm | Quyết định |
|---|---|
| N. Khi client lệch với server | **Lặng lẽ** đưa bảng về trạng thái của server; chỉ cảnh báo ra Output trong Studio. |
| O. Best ở M6 | **Server giữ trong bộ nhớ**, gửi kèm trạng thái ván. "New best!" do server quyết. |

### Kết quả M6

- **84 test pass** (thêm 21 test):
  - **Lockstep:** 200 ván, 3.912 nước, 1.180 lần nhận bộ khối; client và server giống hệt nhau sau mọi nước.
  - **`GameRuns`:** tham số rác, ván cũ, nước cũ, gửi dồn, nước đi sau khi thua, best qua nhiều ván, người chơi rời.
  - **`RateLimiter`, `Validate`.**

| Kiểm tra trong Studio | Kết quả |
|---|---|
| Ván 65 nước qua đường kéo thả | Client = server: 1.010 điểm, cùng bảng, cùng khay; không có lần đồng bộ lại nào |
| 7 tin rác gửi thẳng lên remote | 4 bị bỏ qua, 3 được trả về trạng thái đầy đủ; ván không đổi |
| 20 `StartGame` liền | Chỉ 1 được chấp nhận |
| 100 `PlacePiece` cho ván cũ | Bỏ qua hết |
| 100 nước hợp lệ bơm vào mà client không biết | Client tự đồng bộ lại ngay khi nhận `MoveResult` lạ; nước thật sau đó được chấp nhận |
| Mạng 4G (ping 127 ms) | Đặt khối tức thì; chờ bộ khối mới trung bình 172 ms, lâu nhất 217 ms; client = server |
| Mạng 3G (ping 390 ms, mất 0,5% gói) | Đặt khối tức thì (lâu nhất 3,2 ms); chờ bộ khối mới trung bình 455 ms, lâu nhất 682 ms; 60 nước client = server |

- **Lỗi phát hiện và đã sửa:**
  - Khi nước đi bị server bỏ (vd. vượt giới hạn tần suất) đúng lúc làm khay trống, client đứng chờ một bộ khối mà server không bao giờ gửi.
  - Đã thêm watchdog: nước nào quá 2 giây chưa được xác nhận thì client tự xin lại trạng thái.
  - Bot test đi theo nhịp người chơi (0,13 giây/nước), dưới giới hạn tần suất của server.
- **Để lại cho M10:** dưới 3G khay trống khoảng nửa giây khi chờ bộ khối mới. Nên có hiệu ứng chờ nhẹ ở ô khay.
- **Network Simulator** đã được trả về 0 sau khi test.
