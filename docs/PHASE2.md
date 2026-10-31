# Giai đoạn 2: MVP đủ để publish

Mục tiêu theo [PLAN.md](PLAN.md): game an toàn trước gian lận, lưu được điểm, có hồi sinh bằng Robux, có giao diện thật, người mới hiểu cách chơi trong 15 giây.

## Các mốc

| Mốc | Nội dung | Cần trước | Trạng thái |
|---|---|---|---|
| **M6** Server giữ quyền quyết định | `GameService` chạy `GameSession` trên server, seed bí mật, client dự đoán và đồng bộ lại khi lệch | Không | ✅ Xong |
| **M7** Lưu dữ liệu | ProfileStore (qua Wally): best, số ván, cờ "đã xem tutorial" | Bật *Enable Studio Access to API Services* | ✅ Xong |
| **M8** Hồi sinh bằng Robux | Developer Product, `ProcessReceipt` an toàn khi gọi lặp, giá tăng dần | Giá Robux, tạo product, chọn Group hay cá nhân | |
| **M9** Menu, tutorial, gamepad | Màn hình chính, tutorial lần đầu (ván dựng sẵn), bàn phím và tay cầm qua Input Action System | Ngôn ngữ (English) | ✅ Xong |
| **M10** Giao diện thật | Làm lại `Views/` theo mockup, linh vật, SFX/VFX, khay to hơn ở màn ngang | Linh vật, mockup | |
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

## M7: Lưu dữ liệu người chơi

### Thiết kế

- **Dữ liệu** (một profile mỗi người chơi, key `User_{UserId}`): `version`, `bestScore`, `gamesPlayed` (số ván đã thua), `tutorialDone` (dùng ở M9).
- **`PlayerData`** (`src/server/PlayerData.luau`): logic thuần, test bằng Lune. Gồm template, khung migrate theo `version` (hiện chưa có bước migrate nào), `recordScore` và `recordRunEnd`.
- **`DataService`:** bọc ProfileStore 1.0.3 (cài qua Wally, `ServerScriptService.ServerPackages`).
  - Mở session khi người chơi vào: migrate, `Reconcile`, `AddUserId` (để Roblox xoá dữ liệu khi người chơi yêu cầu).
  - Đóng session khi người chơi rời. ProfileStore tự lưu định kỳ và lưu khi server tắt.
- **`GameService`:**
  - `StartGame` chờ dữ liệu tải xong (tối đa 15 giây) rồi lấy best đã lưu.
  - Mỗi nước được chấp nhận thì cập nhật best (ghi vào bộ nhớ, ProfileStore tự lưu). Ván thua thì cộng `gamesPlayed`.
- **Tool:** `rokit.toml` thêm `wally@0.3.2`. `wally.toml` khai báo ProfileStore ở `server-dependencies`, `wally.lock` được commit, thư mục `ServerPackages/` không commit. Rojo map `ServerPackages` dạng `optional`, nên build được cả khi chưa chạy `wally install`.
- Package ProfileStore có kèm một Script test (`ProfileStoreTest.server.luau`). File project của package chỉ đưa `ProfileStore.luau` vào game, nên Script đó không được sync.

### Quyết định khi review plan M7

| Điểm | Quyết định |
|---|---|
| P. Cách đưa ProfileStore vào | **Wally.** |
| Q. Không tải được dữ liệu | **Kick** kèm lời nhắn "We couldn't load your saved data. Please rejoin." |
| R. Store khi test trong Studio | **Tách riêng:** Studio dùng `PlayerData_Dev`, game thật dùng `PlayerData`. |

### Kết quả M7

- **88 test pass** (thêm 4 test cho `PlayerData`).

| Kiểm tra trong Studio | Kết quả |
|---|---|
| Kết nối DataStore | `dataStoreState=Access`; ProfileStore báo "data will be saved" |
| Profile mới | best 0, 0 ván |
| Chơi đến thua (561 điểm) | best 561, 1 ván |
| Dừng play rồi play lại | best 561, 1 ván; server gửi best đúng, HUD hiện "Best 561" |
| Rời giữa ván khi đang có kỷ lục mới (563) | Play lại: best 563; số ván không đổi (ván dở không tính) |
| Output phía server | Không có lỗi DataStore |

- **Chưa kiểm tra được:** khóa session khi hai server cùng mở một người chơi (Studio chỉ có một server). Phần này dựa vào ProfileStore.
- Store `PlayerData_Dev` đang có dữ liệu test của tài khoản dev (best 563). Không ảnh hưởng tới `PlayerData` của game thật.
- **Lưu ý môi trường:** thêm mục mới vào cây trong `default.project.json` (như `ServerPackages`) cần khởi động lại `rojo serve` rồi Connect lại, giống khi đổi `$properties`.

## M9: Menu, tutorial, bàn phím và tay cầm

### Thiết kế

- **Luồng:** vào game thì hiện màn hình chính (tên **ChiikaBlocks**, best, nút Play và How to play). Ván chỉ bắt đầu khi bấm Play. Game Over có thêm nút Menu để về màn hình chính.
  - Play: chơi ván tutorial cho tới khi người chơi xong tutorial một lần, sau đó là ván thường.
  - How to play: luôn mở ván tutorial.
- **Ván tutorial** (`src/shared/Tutorial.luau`): bảng dựng sẵn, hàng dưới cùng chỉ còn khe 3 ô; bộ khối đầu là `I3_H, O2, L3_1`. Thả `I3_H` vào khe thì xóa hàng và bảng vẫn còn khối. Từ bộ thứ hai, ván chạy như ván thường (sinh khối công bằng, có tính điểm và best).
- **Server:** `StartGame(mode)` nhận `"normal"` hoặc `"tutorial"`; mode sai thì bỏ qua. Nước đầu tiên của ván tutorial được chấp nhận thì server bật cờ `tutorialDone` và gửi lại profile (kể cả khi người chơi không đặt theo gợi ý).
- **Remote mới:** `RequestProfile` (client → server), `Profile(best, gamesPlayed, tutorialDone)` (server → client), có giới hạn tần suất.
- **Client:**
  - `MenuController` và `MenuView`: màn hình chính đè lên game. Enter hoặc Space bấm Play; khi dùng tay cầm thì Play được chọn sẵn.
  - `TutorialController` và `TutorialView`: bàn tay trượt lặp lại từ ô khay tới khe, kèm một dòng hướng dẫn trong mép trên của bảng (theo chiều rộng bảng). Câu hướng dẫn đổi theo thiết bị đang dùng (chuột/cảm ứng, bàn phím, tay cầm). Đặt nước đầu thì ẩn gợi ý; xóa hàng đầu tiên thì hiện tip "Full rows and columns clear. Keep the board open!" trong 3 giây.
  - `GamepadController`: Input Action System, context `Gameplay` chỉ bật khi đang chơi (tắt ở menu và ở bảng Game Over để Enter, Space và nút A bấm nút của menu).
  - Khay có viền vàng ở ô đang chọn và dòng gợi ý phím bên dưới, chỉ hiện khi đang dùng bàn phím hoặc tay cầm.
  - Khối cầm bằng phím luôn nằm khít vào ô. Chỗ không đặt được thì khối mờ đi (`Theme.Transparency.Blocked`), bấm đặt sẽ không có tác dụng.

| Hành động | Bàn phím | Tay cầm |
|---|---|---|
| Chọn khối trước / sau | Q / E (hoặc trái / phải khi chưa cầm khối) | LB / RB |
| Di chuyển từng ô (giữ để lặp) | WASD, mũi tên | D-pad, cần trái |
| Nhặt / đặt | Space, Enter | A |
| Trả khối về khay | Backspace | B |

- **Debug chỉ chạy trong Studio:** client có thêm lệnh `play [normal|tutorial]`, `flow` và `touchdrop <slot> <x> <y>` (thả khối qua đường cảm ứng, báo ngón tay phải ở đâu); server có lệnh `resetdata` (đưa best, số ván, `tutorialDone` về 0 để thử lại lần đầu chơi).

### Quyết định khi review plan M9

| Điểm | Quyết định |
|---|---|
| Ngôn ngữ | **English** cho mọi chữ trong game. |
| S. Kiểu tutorial | **Ván dựng sẵn**, nước đầu chắc chắn xóa hàng, có bàn tay chỉ đường. |
| U. Bàn phím | **Có**, dùng chung các action với tay cầm. |
| Tên game | **Giữ ChiikaBlocks** (không dùng tên tạm). |
| Màn hình chính, tutorial | Bản MVP dạng gray-box; làm lại theo mockup ở M10. |

### Kết quả M9

- **99 test pass** (thêm test cho `Tutorial`, ván tutorial trong `GameRuns`, `markTutorialDone`, và `DragMath.touchLift`).

| Kiểm tra trong Studio | Kết quả |
|---|---|
| Lần đầu chơi (sau `resetdata`) | Menu hiện; Play mở ván tutorial có bàn tay và dòng hướng dẫn |
| Kéo theo gợi ý bằng chuột | Xóa hàng, 13 điểm, hiện tip; server lưu `tutorialDone=true` |
| Game Over → Menu → Enter | Về menu; Enter mở ván thường |
| Play lại ở phiên sau | `tutorialDone` vẫn là true; How to play vẫn mở được tutorial |
| Bàn phím | Q/E chọn khối, Space nhặt và đặt, WASD/mũi tên di chuyển, giữ phím thì lặp và dừng ở mép bảng, Backspace trả khối; chỗ sai thì khối mờ và không đặt được; làm tutorial bằng bàn phím được |
| iPhone 17 Pro dọc | Menu, tutorial và kéo cảm ứng đúng ô |
| iPhone 17 Pro ngang | Menu, dòng hướng dẫn và bảng Game Over vừa màn hình |
| Thả vào hàng cuối bằng cảm ứng, iPhone 17 Pro ngang | Trước khi sửa: ngón tay phải ở y=368 (ngoài màn hình, mép ở 323). Sau khi sửa: y=313,6; khối đặt được và xóa hàng |
| Kéo cảm ứng ở iPhone 17 Pro dọc sau khi sửa | Độ nâng giữ nguyên 1,5 ô; khối rơi đúng ô |

- **Lỗi phát hiện và đã sửa:**
  - Khi cầm bằng phím, chỗ không đặt được trông y như chỗ đặt được: thêm hiệu ứng mờ.
  - Câu hướng dẫn chỉ được chọn lúc bắt đầu ván, nên đổi sang bàn phím giữa chừng vẫn ghi "Drag…": giờ được đọc lại mỗi vòng.
  - Ở điện thoại ngang, dòng hướng dẫn rộng hơn bảng và đè lên điểm số: giờ lấy theo chiều rộng bảng.
- **Chưa kiểm tra được:** bấm nút tay cầm thật. Công cụ MCP gửi nút tay cầm như phím bàn phím, còn `VirtualInputManager` cần quyền RobloxScript. Đã kiểm tra các binding được tạo đủ; cần thử bằng **Controller Emulator** của Studio hoặc tay cầm thật.
- **Lỗi có sẵn từ M4, đã sửa:** ở điện thoại ngang, bảng chiếm hết chiều cao màn hình mà khối kéo bằng cảm ứng luôn nằm cao hơn ngón tay 1,5 ô. Trên iPhone 17 Pro, ngón tay chạm sát mép dưới thì khối chỉ xuống tới hàng 6, nên không thả được vào hàng cuối.
  - Cách sửa (`DragMath.touchLift`): chỉ khi ngón tay không thể với tới hàng cuối với độ nâng đầy đủ, độ nâng mới giảm dần trong 3 ô cuối của vùng ngón tay với được. Hàng cuối với tới được ở 0,25 ô trên mép màn hình. Trong vùng này khối đi nhanh hơn ngón tay một chút (khoảng 1,5 lần ở iPhone ngang), và không bao giờ nằm dưới ngón tay.
  - Màn dọc và PC không đổi, vì bên dưới bảng còn khay.
- **Lưu ý khi test:** client giữ best theo kiểu chỉ tăng, nên sau `resetdata` HUD và menu vẫn hiện best cũ cho tới khi vào lại game. Khi chơi thật best không bao giờ giảm nên không ảnh hưởng.
