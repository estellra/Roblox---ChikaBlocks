# Giai đoạn 2: MVP đủ để publish

Mục tiêu theo [PLAN.md](PLAN.md): game an toàn trước gian lận, lưu được điểm, có hồi sinh bằng Robux, có giao diện thật, người mới hiểu cách chơi trong 15 giây.

## Các mốc

| Mốc | Nội dung | Cần trước | Trạng thái |
|---|---|---|---|
| **M6** Server giữ quyền quyết định | `GameService` chạy `GameSession` trên server, seed bí mật, client dự đoán và đồng bộ lại khi lệch | Không | ✅ Xong |
| **M7** Lưu dữ liệu | ProfileStore (qua Wally): best, số ván, cờ "đã xem tutorial" | Bật *Enable Studio Access to API Services* | ✅ Xong |
| **M8** Hồi sinh bằng Robux | Developer Product, `ProcessReceipt` an toàn khi gọi lặp, giá tăng dần | Đã có giá và 3 product | ✅ Xong |
| **M9** Menu, tutorial, gamepad | Màn hình chính, tutorial lần đầu (ván dựng sẵn), bàn phím và tay cầm qua Input Action System | Ngôn ngữ (English) | ✅ Xong |
| **M10** Giao diện thật | Làm lại `Views/` theo mockup Figma, linh vật (âm thanh để sau) | Không | ✅ Xong (âm thanh để sau) |
| **M11** Publish thử và QA | ≥95% test không lỗi, thử người mới, thử mạng chậm | Bạn publish và mời người thử ([QA.md](QA.md)) | 🟡 Đã publish và thử trên PC. Còn: điện thoại thật, tay cầm thật, mua Robux thật (hồi sinh, xoay, donate), mạng yếu thật, người mới (xem [QA.md](QA.md)) |

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


## M8: Hồi sinh bằng Robux

### Đầu vào đã có

- Game thuộc **tài khoản cá nhân**.
- **3 Developer Product**, giá tăng dần theo số lần hồi sinh trong cùng một ván:

| Lần hồi sinh trong ván | Giá | Product ID |
|---|---|---|
| 1 | 10 R$ | `3727116317` |
| 2 | 15 R$ | `3727116434` |
| 3 trở đi | 25 R$ | `3727116486` |

### Điểm khác với plan cũ

Plan cũ giới hạn **tối đa 2 lần hồi sinh mỗi ván** (`MAX_REVIVES_PER_RUN = 2`). Việc bạn đặt giá cho "các lần sau" nghĩa là không giới hạn (quyết định AJ, đã duyệt).

### Thiết kế

Server quyết định mọi thứ về tiền: client chỉ xin hồi sinh, không bao giờ chọn product hay tự hồi sinh.

```
Client                                              Server
  │ (game over) ◀──── ReviveOffer(runId, offer) ───── giá lần này, số lượt đã mua còn dư
  │ bấm Revive
  │ RequestRevive(runId) ─────────────────────────▶  kiểm tra ván đã thua, chưa hồi sinh quá,
  │                                                  không phải ván tutorial, giới hạn tần suất
  │                                                  còn lượt đã mua? → hồi sinh ngay
  │                                                  không → PromptProductPurchase(product của lần này)
  │                                  (hộp thoại mua của Roblox)
  │                                                  ProcessReceipt: cấp 1 lượt, lưu xong mới báo OK,
  │                                                  rồi dùng lượt đó hồi sinh ván đang chờ
  │ ◀──── GameState(state, "revive") ──────────────  bảng đã xoá vùng 4×4, bộ khối mới
  │ ◀──── ReviveResult(runId, false) ──────────────  người chơi huỷ mua (để nút hết "đang xử lý")
```

- **`PurchaseService`** (server): đặt `MarketplaceService.ProcessReceipt` (chỉ một nơi duy nhất).
  - Logic thuần tách riêng (`Purchases.luau`, test bằng Lune): nhận biên lai và các hàm truyền vào (lấy dữ liệu người chơi, lưu xong chưa, cấp thưởng).
  - **Không cấp trùng:** mỗi `PurchaseId` đã xử lý được ghi vào profile (`purchaseIds`, giữ 100 cái gần nhất); biên lai gọi lại chỉ trả "đã cấp".
  - **Chỉ báo thành công khi đã lưu:** cấp xong thì `profile:Save()` và chờ lưu thành công. Lưu lỗi thì trả `NotProcessedYet` để Roblox gọi lại sau (kể cả lần vào game kế tiếp). Danh sách `PurchaseId` chống cấp hai lần khi gọi lại.
  - Người chơi chưa vào được hoặc dữ liệu chưa tải: `NotProcessedYet`. Product không có trong danh sách: cũng `NotProcessedYet` kèm cảnh báo.
- **Mua xong là cấp một "lượt hồi sinh đã mua"** (`reviveTokens` trong profile), rồi dùng ngay cho ván đang chờ. Nếu lúc đó không dùng được (người chơi đã thoát ván, đổi ván, mất kết nối), lượt vẫn nằm trong profile và hiện ở lần game over sau ("Revive · Free", còn N lượt). Tiền không bao giờ mất mà không được gì. Xem quyết định AK.
- **`GameRuns.revive(key, runId)`**: kiểm tra ván còn, đã thua, là ván thường; gọi `GameSession:revive()` (đã có từ M1: xoá vùng 4×4 giữa bảng, cho bộ khối chắc chắn đặt được, tăng `revivesUsed`).
- **Giá hiển thị** lấy từ Roblox (`GetProductInfoAsync`, cache theo server), không ghi cứng trong code. Gửi cho client trong `ReviveOffer`.
- **Một ván chỉ tính một lần kết thúc** khi thống kê: hồi sinh rồi thua lại không cộng thêm `gamesPlayed`, không log thêm sự kiện `RunScore` (cần sửa `GameRuns` và `GameService`).
- **Client:** `Hud.setRevive` đã có từ M10c; nút gọi `RequestRevive`, hiện trạng thái "đang xử lý" tới khi có `GameState "revive"` hoặc `ReviveResult(false)`. `GameState` có thêm lý do `"revive"` (không cảnh báo "resync" trong Studio).
- **Analytics** (làm nốt phần đã hứa ở M12): funnel `ReviveOffer` gồm 4 bước: thấy lời mời, mở hộp mua, mua xong, đã hồi sinh (`LogFunnelStepEvent`).
- **`Config`:** thêm `REVIVE_PRODUCTS = { 3727116317, 3727116434, 3727116486 }`; `MAX_REVIVES_PER_RUN` thành không giới hạn nhưng vẫn là một số chỉnh được.
- **Debug (chỉ Studio):** lệnh server `fakepurchase [productId]` giả một biên lai (dùng được hai lần cùng `PurchaseId` để thử chống cấp trùng); `data` hiện thêm `reviveTokens`.

### Quyết định cần chốt

| Điểm | Câu hỏi | Đề xuất |
|---|---|---|
| **AJ.** Số lần hồi sinh tối đa mỗi ván | Bạn đặt giá cho "các lần sau" nên không còn giới hạn 2 lần | **Không giới hạn** (`MAX_REVIVES_PER_RUN` vô hạn, đổi được trong `Config`). Giá lần 3 trở đi giữ 25 R$. Nếu muốn có trần (vd. 5 lần) thì nói số |
| **AK.** Mua xong mà không hồi sinh được | Người chơi thoát ván hoặc mất mạng giữa chừng | **Giữ lại thành lượt đã mua** trong profile, dùng ở lần game over kế tiếp |
| **AL.** Dòng gợi ý dưới nút Revive | Mockup ghi "1 of 2 left", giờ không còn giới hạn | Chỉ ghi **"Clears the center 4×4"**; khi dùng lượt đã mua thì ghi thêm số lượt còn |

### Kiểm thử

- Lune: biên lai gọi hai lần (cấp một lần), lưu lỗi (trả `NotProcessedYet`, gọi lại thì cấp đúng một lần), người chơi chưa tải dữ liệu, product lạ; chọn product theo số lần đã hồi sinh (10 / 15 / 25); `revive` chỉ khi đã thua và là ván thường; hồi sinh nhiều lần không cộng thêm `gamesPlayed`; test tuần tự `GameSession` cập nhật theo AJ.
- Studio: hiện lời mời đúng giá sau khi thua, bấm Revive mở hộp mua của Roblox (xem ảnh chụp), `fakepurchase` hồi sinh thật qua đường `ProcessReceipt`, biên lai trùng không cấp thêm, ván thua lần hai hiện giá lần sau.
- **Chưa thử được:** giao dịch Robux thật trên server đã publish (cần M11). Trong Studio, hộp thoại mua là bản thử không trừ Robux.

### Kết quả M8

- **Quyết định:** AJ (không giới hạn số lần hồi sinh), AK (mua xong mà không dùng được thì giữ thành lượt đã mua) và AL (dòng gợi ý chỉ ghi "Clears the center 4×4") đều theo đề xuất.
- **`Purchases.luau`** (logic thuần, test bằng Lune): chọn product theo số lần đã hồi sinh (10 / 15 / 25 R$) và xử lý biên lai: chỉ cấp một lần cho mỗi `PurchaseId`, chỉ báo "granted" khi đã xác nhận lưu xong, người chơi chưa vào được hoặc product lạ thì `NotProcessedYet`, nhớ 100 giao dịch gần nhất.
- **`PurchaseService`** (server): đặt `ProcessReceipt` (một nơi duy nhất); đọc giá 3 product từ Roblox (`GetProductInfoAsync`, lưu cả phiên); nhận `RequestRevive`, kiểm tra ván đã thua, là ván thường, đúng `runId`; còn lượt đã mua thì hồi sinh ngay, không thì mở hộp mua của Roblox với product đúng lần; mua xong thì cấp lượt, chờ lưu xong rồi dùng cho ván đang chờ. Huỷ mua thì `ReviveResult(false)` để nút hết "Please wait…".
- **`DataService.waitUntilSaved`:** gọi `profile:Save()` rồi chờ tới khi `LastSavedData` chứa đúng `PurchaseId` (theo hướng dẫn "caching PurchaseId" của ProfileStore).
- **`GameRuns.revive`** (dùng `GameSession:revive` từ M1): chỉ ván thường, đã thua, đúng `runId`. Một ván chỉ tính **một lần kết thúc** (`endsRun`): hồi sinh rồi thua lại không cộng `gamesPlayed` và không ghi thêm `RunScore` / `RunMoves` / `RunMaxCombo`.
- **Remote mới:** `RequestRevive`, `ReviveOffer(runId, { tokens, price? })`, `ReviveResult(runId, ok)`; `GameState` có thêm lý do `"revive"` (không còn cảnh báo "resynced" trong Studio).
- **Client:** nút Revive hiện ở Game Over ("Revive · R$ 10", "Revive · Free" khi có lượt đã mua kèm "You have N"), bấm thì thành "Please wait…" tới khi có kết quả. Giá lấy từ Roblox, không ghi cứng.
- **Analytics:** funnel `ReviveOffer` (1 Offered, 2 Requested, 3 Paid, 4 Revived; lượt đã mua không có bước 3), session id `runId.số lần đã hồi sinh`.
- **Dữ liệu:** profile thêm `reviveTokens` và `purchaseIds` (version vẫn là 2, `Reconcile` tự điền mặc định). `Config.REVIVE_PRODUCTS` giữ ba ID, `MAX_REVIVES_PER_RUN` là `math.huge`.
- **Debug (chỉ Studio):** `fakepurchase [userId] [productId] [purchaseId]` đưa biên lai giả vào đúng hàm xử lý thật; `data` hiện `reviveTokens` và số giao dịch đã nhớ; `resetdata` xoá cả hai.
- **Cập nhật ở M11:** lượt đã mua nay gắn với mức giá của product (dữ liệu version 3, xem mục M11). Mô tả `version vẫn là 2` ở dòng "Dữ liệu" phía trên là của lúc làm M8.
- **137 test pass** (thêm 13: `Purchases` 7, hồi sinh và `endsRun` trong `GameRuns` 3, `PlayerData` 2, funnel trong `Telemetry` 1; cập nhật test `GameSession` vì không còn giới hạn).

| Kiểm tra trong Studio | Kết quả |
|---|---|
| Thua ván | Nút "Revive · R$ 10", gợi ý "Clears the center 4×4" (giá đọc được từ Roblox) |
| Bấm Revive thật | Nút chuyển "Please wait…" |
| Biên lai giả (product 1) khi đang chờ | `granted`; bảng xoá vùng 4×4 giữa, bộ khối mới, điểm giữ nguyên; lượt vừa cấp được dùng ngay (`reviveTokens=0`) |
| Cùng `PurchaseId` lần hai | `granted`, **không cấp thêm** (`purchases=1`, `reviveTokens=0`) |
| Thua lần hai | "Revive · R$ 15"; `games` vẫn là 2; `RunScore` chỉ ghi một lần |
| Biên lai giả khi không có hộp chờ (product 2) | `reviveTokens=1`; nút đổi thành "Revive · Free", "You have 1" |
| Dùng lượt đã mua | Hồi sinh, `reviveTokens=0`, funnel đủ bước Offered, Requested, Revived |
| Output | Không có lỗi từ game |

- **Chưa kiểm tra được:**
  - Hộp thoại mua thật của Roblox: bấm Revive thật gửi yêu cầu và mở hộp mua, nhưng ảnh chụp trong Studio không hiện hộp đó. Các lần bấm sau đó không tới được nút (có thể hộp mua đang chặn); mình kiểm tra các lần sau qua remote.
  - Giao dịch Robux thật trên server đã publish (cần M11), và bấm huỷ trong hộp mua.
  - Giá lần 3 trở đi (25 R$): đã kiểm tra chọn product trong test Lune, chưa thấy hiện trong Studio vì ván cần thua lần thứ ba.

## M10: Giao diện thật

Nguồn: file Figma ChikaBlocks-UI (trang Foundations và Screens). Trang Moodboard ghi rõ "reference only, do not use in game" (có nhân vật của bên thứ ba) nên **không lấy bất cứ thứ gì từ trang đó**. Mình chỉ đọc ba trang: Foundations (token và component), Screens (màn hình dọc 390×844 và ngang 1280×720), và 8 bộ theme.

### Mockup có gì

| Màn hình | Bản dọc | Bản ngang | Ghi chú |
|---|---|---|---|
| Gameplay | ✅ | ✅ | Dọc: điểm ở trên, bảng giữa, khay 3 ô nằm ngang ở dưới. Ngang: bảng bên trái, thẻ HUD (nút pause, điểm, best, combo) và khay dọc bên phải |
| Main Menu | ✅ | ✅ | Logo hai dòng, mascot, "Best", nút Play và Leaderboard, dòng khẩu hiệu, nút âm thanh và cài đặt |
| Dragging | ✅ | ✅ | Khối nổi cao hơn ngón tay khoảng 1,5 ô (khớp M4), ô sẽ đặt hiện viền nét đứt hồng |
| Combo Popup | ✅ | ✅ | Mascot kèm bong bóng "Combo x3!", chữ "+180" vàng, các tia sáng |
| Game Over | ✅ | ✅ | "No more moves!", điểm, Best, **Revive R$ 25** ("Clears the center 4×4 · 1 of 2 left"), Play again, Menu |
| Tutorial | ✅ | ✅ | Khung hướng dẫn có mascot, nút Skip, đường kéo nét đứt, bàn tay chỉ, ô khay được viền vàng |
| 8 theme × 6 màn (PC) | | ✅ | Mochi Blush, Polar Pip, Custard Bun, Mint Cloud, Bramble, Lilac Puff, Night Hoot, Tangerine, mỗi theme một linh vật gốc. Đây là cosmetic của GĐ4 |

Mockup **chưa có**: màn Leaderboard, màn Pause, màn Cài đặt, thanh EXP và danh hiệu ở Game Over, chỗ hiện level, nút "How to play", dòng gợi ý phím cho bàn phím và tay cầm, và hiệu ứng chờ bộ khối mới.

### Token lấy được từ Foundations

| Nhóm | Giá trị |
|---|---|
| Chữ | `text/primary` #4e3d4a, `text/muted` #7d6b78, chữ trên nút xanh #2f4a66 |
| Nền | `surface/panel` #fffbf3 (bảng, thẻ HUD, panel), `surface/tray-slot` #ffffff, `surface/cell-empty` #eaf4fb, nền trời chuyển màu xanh nhạt sang hồng nhạt kèm các đám mây |
| Nút chính (hồng) | #ff9dbb, viền dưới #e57fa0 |
| Nút phụ (xanh) | #a9dbff, viền dưới #62b2e8 |
| Nút thưởng (vàng) | #ffd36e, viền dưới #e0a93a (Revive, ô Combo) |
| 8 màu khối | butter #ffe08a, sky #9fd8ff, peach #ffc4a0, mint #b4ebc4, pink #ffb3c9, lavender #cfbdff, aqua #9ee6e0, coral #ff9e9e; mỗi màu có một màu viền đậm hơn |
| Bo góc | nút 18, panel 24, bảng 20 |
| Đổ bóng | "Clay": bóng mềm, kèm viền sáng bên trong ở mép trên; "Lifted": bóng đổ sâu cho khối đang kéo; "Glow/Gold": quầng vàng |
| Font | Fredoka Bold 56 (Display), 44 (điểm), 30 (tiêu đề); Fredoka SemiBold 22 (nút); Nunito ExtraBold 15 (nhãn); Nunito Bold 13 (chú thích) |

**Font trong Roblox:** có `FredokaOne` (một độ đậm, rất gần Fredoka Bold) và `Nunito` (có nhiều độ đậm). Font `Fredoka` nhiều độ đậm không có. Mình dùng `FredokaOne` cho tiêu đề, điểm và nút. Nút trong mockup là SemiBold nên sẽ đậm hơn một chút, khác biệt nhỏ.

### Hướng làm

1. **Theme dạng token** (`Theme.luau`) thay hết bảng màu xám hiện tại bằng bảng trên. Giữ cấu trúc token đã có nên các `View` không phải đổi cách gọi. Gom màu thành một bảng palette để GĐ4 thay theme bằng cách đổi palette (8 theme trong mockup có cùng bố cục, chỉ khác màu và linh vật).
2. **Bộ component dùng chung**, vẽ bằng Frame, `UICorner`, `UIStroke`, `UIGradient` để không cần tải nhiều ảnh:
   - Nút kiểu clay: thân nút, viền ngoài đậm, "mép dưới" dày vài px khác màu, lún xuống khi nhấn.
   - Thẻ HUD, pill (Best, Combo), panel, ô khay, nút icon tròn, bong bóng thoại, nền trời với mây và khối trôi trang trí (dùng lại `PieceView`).
   - Ô khối bóng: nền màu, viền màu đậm, vệt sáng nhỏ ở góc trên trái.
3. **Làm từng màn, cả dọc và ngang**, theo thứ tự: Gameplay (bảng, khay, HUD, kéo thả) → Menu → Game Over → Tutorial → Combo popup → Leaderboard và Pause (tự thiết kế theo cùng phong cách, bạn duyệt).
4. **Bố cục** giữ cơ chế hiện tại (vùng HUD, bảng, khay chia theo tỉ lệ, `CoreUISafeInsets`). Mockup đã tính sẵn 58 px thanh trên cùng của Roblox cho bản dọc.
5. **Đối chiếu mockup**: mỗi màn chụp ảnh trong Studio ở 1280×720 và 390×844 (cùng iPhone ngang), đặt cạnh frame Figma để bạn so.
6. **Hiệu ứng**: nút lún khi nhấn, khối bật nhẹ khi đặt, mascot hiện bong bóng khi combo, tia sáng, thanh EXP chạy. Âm thanh xem quyết định cuối.

### Ảnh dùng trong game

Ảnh được xuất từ Figma vào thư mục `assets/` (13 file PNG, nền trong suốt). Logo **không** phải ảnh: trong Figma nó là hai lớp chữ (`Chika` và `Blocks` trong `Logo (working title)`), nên game dựng bằng chữ `FredokaOne` cộng viền.

| Ảnh | File | Kích thước | Ghi chú |
|---|---|---|---|
| Icon Pause, Settings, Home, Replay, Trophy, Sound, Close | `pause.png`... | 96×96 (4x) | Một màu #4e3d4a (màu chữ chính) |
| Vương miện (Best) | `crown.png` | 72×72 (4x) | Vàng #ffd36e có viền nâu |
| Bàn tay chỉ (tutorial) | `Hand pointer (tutorial).png` | 208×208 (4x) | Trắng, viền nâu |
| Tia sáng | `Sparkle (decor).png` | 96×96 (4x) | Vàng, viền nâu |
| Mascot Happy, Cheer, Sad | `Mood=*.png` | 288×288 (3x) | Hình vuông bo tròn có chóp hồng |

Đám mây, bong bóng thoại, khung, nút, nền trời và khối bóng vẽ bằng UI, không cần ảnh. 8 linh vật theme chưa cần ở M10, chỉ cần khi làm cosmetic ở GĐ4.

**Lưu ý cho GĐ4:** icon đang là màu nâu đậm nên chỉ hợp theme sáng. Roblox tô màu ảnh bằng cách nhân màu, nên theme tối (Night Hoot) cần bản icon trắng. Khi đó mình tạo bản trắng từ chính các file này.

### Quyết định cần chốt

| Điểm | Vấn đề | Đề xuất |
|---|---|---|
| **AB.** Tên game trên logo | Mockup viết **ChikaBlocks** và ghi lớp logo là "working title"; tên đã chốt ở M9 là **ChiikaBlocks** (tên place trên Roblox là ChikaBlocks) | ✅ **Chốt: theo mockup (ChikaBlocks).** Đã đổi `Theme.Text.GameTitle` và các tài liệu |
| **AC.** ✅ Mascot mặc định | Màn hình dùng mascot **hình vuông bo tròn có chóp hồng** (ghi là placeholder). Trang theme thì có 8 linh vật khác (Mochi là hải cẩu trắng nơ hồng...) | Dùng mascot hình vuông làm mặc định trong M10. 8 linh vật là cosmetic GĐ4. Nếu bạn muốn Mochi là mặc định thì gửi ảnh Mochi 3 trạng thái |
| **AD.** ✅ Nút "How to play" | Mockup menu không có | Thêm nút "?" tròn cạnh nút âm thanh và cài đặt. Lần chơi đầu vẫn tự vào tutorial |
| **AE.** ✅ Level và danh hiệu | Mockup không có chỗ hiện | Thêm một pill nhỏ dưới "Best" ở menu ("Lv 5 · Regular"), và hàng EXP trong panel Game Over |
| **AF.** ✅ Nút pause | Mockup có nút pause nhưng không có màn pause | Panel nhỏ cùng phong cách với 3 nút Resume / Play again / Menu. Ván không dừng thời gian (game không có đồng hồ) nên pause chỉ để mở Menu an toàn |
| **AG.** ✅ Nút Cài đặt và Âm thanh (chỉ phần không liên quan âm thanh) | Mockup có hai nút nhưng không có nội dung | Âm thanh: bật hoặc tắt tiếng, lưu theo người chơi. Cài đặt: panel nhỏ có bật tắt nhạc, hiệu ứng âm thanh và nút "How to play". Cần chốt có làm âm thanh trong M10 không (xem AH) |
| **AH.** ⏭ Âm thanh (**để các giai đoạn sau**, theo bạn) | Roadmap có SFX và VFX cơ bản, mockup không nói gì về âm thanh | Làm 5 hiệu ứng âm thanh (đặt khối, xóa hàng, combo, game over, bấm nút) và một bản nhạc nền, dùng âm thanh miễn phí trong thư viện Roblox, bạn nghe duyệt. Nếu chưa muốn thì để sang sau, M10 chỉ làm giao diện nút bật tắt |
| **AI.** ✅ Nút Revive trên Game Over | Mockup có sẵn "Revive · R$ 25" nhưng M8 chưa làm | M10 dựng sẵn nút và dòng "Clears the center 4×4 · 1 of 2 left" nhưng **ẩn** cho tới khi M8 xong |

### Thứ tự và khối lượng

| Bước | Nội dung | Cần ảnh? |
|---|---|---|
| M10a ✅ | Theme token, font, bộ component, nền trời và mây | Không (đã có ảnh) |
| M10b ✅ | Gameplay: bảng, khối bóng, khay, HUD, kéo thả (dọc và ngang), panel Pause | Icon pause, crown |
| M10c ✅ | Menu, Game Over (có EXP, Revive ẩn) | Mascot |
| M10d ✅ | Tutorial, Combo popup với mascot, tia sáng | Mascot, bàn tay, sparkle |
| M10e ✅ | Leaderboard theo cùng phong cách (Cài đặt và âm thanh để sau) | Icon trophy, close |

Mỗi bước kết thúc bằng bộ test (logic không đổi nên các test hiện có phải còn nguyên), ảnh chụp đối chiếu Figma và một commit, giống các mốc trước.

### Kết quả M10a

- **Ảnh:** 13 file trong `assets/` đã tải lên Roblox (qua Studio) và kiểm tra tải được; ID nằm trong `Theme.Images`. Ảnh gốc giữ trong repo để tải lại khi cần.
- **`Theme.luau`** viết lại theo token Figma (Foundations): màu bề mặt, chữ, nút (chính hồng, phụ xanh, thưởng vàng, mỗi loại có màu mép dưới), 8 màu khối kèm màu viền, bo góc nút 18, panel 24, bảng 20, độ dày viền, font. Mọi `View` vẫn đọc token như cũ nên cả game đổi sang bảng màu sáng ngay.
- **Font:** tiêu đề, điểm và nút dùng `FredokaOne`; chữ thường dùng `Nunito` Bold, nhãn nhỏ dùng `Nunito` ExtraBold. Font `Fredoka` nhiều độ đậm không có trong Roblox.
- **`Clay.luau`** (mới):
  - `Clay.button`: nút viền nâu với mép dưới màu đậm hơn, lún xuống khi nhấn. Là một Frame chứa phần mép và `Face` (TextButton, dùng `Clay.face()` để lấy). Kích thước tối thiểu theo mức 44 px cho cảm ứng.
  - `Clay.setStyle`: đổi màu nút (tab đang chọn).
  - `Clay.sky`: nền trời gradient `#cfebff` → `#fff1f6` kèm 4 đám mây vẽ bằng UI.
- **Áp dụng:** nền toàn game, menu và Leaderboard dùng nền trời; nút ở menu, Game Over, Leaderboard (tab và Back) là nút clay; panel Game Over có viền.
- **Kiểm tra trong Studio** (PC 1365×768): menu, gameplay, Game Over và Leaderboard đều hiển thị đúng bảng màu mới; Output không có lỗi. 123 test pass.
- **Bài học:** `CanvasGroup.GroupTransparency` không có tác dụng trong ảnh chụp của Studio (đổi từ 0 đến 0.9 vẫn giống nhau), nên mây dùng một màu đặc nhạt thay vì làm mờ.
- **Chưa làm (thuộc các bước sau):** khối bóng có viền và vệt sáng, viền bảng, thẻ HUD, bố cục menu và Game Over theo mockup, mascot, icon, logo dạng chữ hai dòng, tutorial và combo popup.

### Kết quả M10b

- **Quyết định:** chốt AB–AG và AI theo đề xuất; **âm thanh (AH) để các giai đoạn sau**. Vì chưa có âm thanh, nút Âm thanh trên menu sẽ **không** dựng ở M10c (nút không làm gì là sai), và panel Cài đặt dời tới khi có âm thanh (lúc này chỉ có "How to play", đã có nút "?" riêng).
- **Khối bóng** (`Block.luau`): màu pastel, viền màu đậm của chính nó (2 px) và vệt sáng trắng nhỏ ở góc trên trái, dùng chung cho bảng, khay, khối đang kéo, bóng xem trước và hiệu ứng xóa. Ô trống giữ dạng phẳng. Khối mờ đi (cả viền và vệt sáng) khi cầm bằng phím ở chỗ không đặt được.
- **Bảng** có viền nâu 3 px. **Khay:** ô trắng, mờ đi khi khối bên trong đã đặt hoặc đang cầm.
- **HUD** (`HudBar.luau`): nút pause tròn có icon, "SCORE" và điểm (có dấu phẩy ngăn cách), pill Best có vương miện, pill Combo vàng (hiện từ combo 2). Màn ngang: nằm trên một thẻ kem có viền; màn dọc: nổi trên nền trời. Pill tự co theo chiều cao thẻ để không tràn trên điện thoại ngang; thẻ HUD ở màn ngang cao 20% thay vì 17%.
- **Panel Pause:** Resume, Play again, Menu; mở bằng nút pause hoặc phím **P**; Resume bằng nút, Enter, Space, Backspace hoặc B. Khi đang pause, phím chơi bị khóa. Ván không có đồng hồ nên pause không thay đổi gì khác (chủ yếu để mở Menu và Play again nhanh).
- **Component mới trong `Clay`:** `pill`, `iconButton`, `setPillHeight`. `Hud.new` nhận một bảng callback (`onRestart`, `onMenu`, `onPause`, `onResume`).
- **Kiểm tra trong Studio:** PC (1365×768), iPhone 17 Pro dọc (401×777) và ngang (749×381). Đã thử bấm Pause, Resume, phím P, Backspace, kéo khối (khay mờ, bóng xem trước), Game Over. Output không có lỗi. 123 test pass.
- **Bài học:** `UIAspectRatioConstraint` mặc định (`FitWithinMaxSize`) làm kích thước bằng 0 nếu một chiều của `Size` bằng 0; phải đặt kích thước tối đa thật cho cả hai chiều (đã gặp ở đám mây và nút pause).
- **Chưa làm:** đường kéo nét đứt và vòng viền hồng của ô sẽ đặt (mockup dùng nét đứt, Roblox không có viền đứt; hiện dùng bóng xem trước trong suốt), popup mascot khi combo (M10d), nút icon cho Menu (M10c).

### Kết quả M10c

- **Menu** (`MenuView.luau` viết lại):
  - Logo hai dòng dựng bằng chữ: "Chika" nâu, "Blocks" hồng có viền nâu, dòng dưới chồng nhẹ lên dòng trên. Hai dòng nằm trong `Theme.Text.LogoLines`, chỉ có một chỗ để đổi.
  - Mascot vui (ảnh), pill **Best** có vương miện, pill **level và danh hiệu** (chữ tím), nút Play lớn (72 px), nút Leaderboard, dòng khẩu hiệu "Drag blocks. Clear lines. Stay cozy.".
  - Nút tròn **"?"** ở góc trên phải mở tutorial (How to play).
  - 4 khối pastel trang trí nổi nhẹ lên xuống trên nền trời, tạm dừng khi menu đóng.
  - Màn ngang: logo và mascot bên trái, cột nút bên phải; màn dọc: xếp chồng. Kích thước logo, mascot và cột nút tính theo kích thước màn hình.
- **Game Over:** mascot buồn (mascot vui khi phá kỷ lục), tiêu đề "No more moves!" (đổi thành "New best!" khi có kỷ lục mới), "SCORE" và điểm lớn có dấu phẩy, pill Best, thanh EXP, "Level up!" và danh hiệu mới như M13. Cột nút: **Revive**, Play again, Menu.
  - **Màn ngang thấp** (< 480 px, điện thoại ngang): bảng chia hai cột, thông tin bên trái và nút bên phải, nút giữ cao 56 px (đạt mức cảm ứng 44 px). Bản gộp một cột trước đó phải thu nhỏ còn khoảng 50% nên không dùng được.
  - **Nút Revive dựng sẵn nhưng ẩn.** M8 chỉ cần gọi `Hud.setRevive({ text = "Revive · R$ 25", hint = "Clears the center 4×4 · 1 of 2 left" })` và truyền `onRevive` trong callbacks; gọi `Hud.setRevive(nil)` để ẩn.
- **Component mới:** `Format.withCommas` (số có dấu phẩy, dùng ở HUD, menu và Game Over); `Clay.button` nhận `textSize`; `Clay.iconButton` nhận chữ thay cho ảnh.
- **Nút Âm thanh:** như đã chốt, không dựng cho tới khi có âm thanh.
- **Kiểm tra trong Studio:** menu ở PC (1280×720), iPhone 17 Pro dọc và ngang; Game Over ở iPhone dọc và ngang (có xem trước slot Revive); bấm thật nút "?" mở tutorial. Output không có lỗi. 123 test pass.
- **Khác mockup:** pill level và nút "?" là bổ sung của mình (mockup không có, theo quyết định AD và AE); nút Âm thanh và Cài đặt trên menu chưa có.

### Kết quả M10d

- **Tutorial** (`TutorialView` và `TutorialController` viết lại):
  - Thẻ hướng dẫn có mascot ("Drag the block" / "to fill the row!") đặt vào chỗ thanh điểm; thanh điểm ẩn trong lúc có gợi ý và hiện lại sau nước đầu. Chữ đổi theo thiết bị đang dùng (chuột/cảm ứng, bàn phím, tay cầm).
  - Ba ô sẽ lấp hiện màu hồng nhạt có viền (mockup dùng nét đứt, Roblox không có); mũi tên chấm chấm cong nhẹ từ ô khay tới ô đích; bàn tay (ảnh) trượt dọc theo đó, đầu ngón tay đúng vào điểm đích.
  - Ô khay được chỉ có viền vàng dày, hai ô còn lại mờ đi (`TrayView.setHint`).
  - Nút **Skip** ở góc trên phải (68×44, đạt mức cảm ứng): bỏ tutorial, server tính là đã xong (remote mới `SkipTutorial`, giới hạn tần suất, ghi sự kiện `TutorialSkipped` một lần) và vào ván thường. Chỉ hiện trước nước đầu.
  - Sau lần xóa hàng đầu tiên: thẻ "Nice!" (mascot vui) phủ lên thanh điểm trong 3 giây.
- **Popup combo** (`ComboPopup.luau`): khi xóa hàng, chữ "+điểm" **vàng có viền nâu** nổi lên rồi mờ; combo từ 2 hoặc board clear thì mascot vui bật ra ở góc trên phải bảng cùng bong bóng "Combo x3!" / "Board clear!" (khoảng 1,3 giây); xóa từ 2 hàng trở lên, combo từ 2 hoặc board clear thì thêm 5 tia sáng xoay trên bảng.
- **Lỗi phát hiện và đã sửa:** `UIStroke` đặt dưới `TextButton` mặc định viền cả chữ (`Contextual`), làm nút Skip trông không có viền và chữ bị béo; đã đặt `ApplyStrokeMode = Border`.
- **Kiểm tra trong Studio:** PC (1280×720), iPhone 17 Pro dọc và ngang. Đã làm đủ luồng: tutorial hiện đúng, kéo chuột vào ô đích (xóa hàng, thẻ "Nice!", thanh điểm quay lại), bấm Skip thật (`tutorialDone=true`, sự kiện ghi đúng một lần), popup combo thật khi bot chơi. Output không có lỗi. 124 test pass (thêm 1 test cho `Telemetry`).
- **Chưa làm:** Leaderboard theo phong cách mới và tinh chỉnh chung (M10e).

### Kết quả M10e

- **Leaderboard** (`LeaderboardView.luau` viết lại; mockup chưa có màn này nên mình tự thiết kế theo cùng phong cách, bạn xem và góp ý nếu muốn đổi):
  - Một thẻ kem có viền nâu trên nền trời: biểu tượng cúp và tiêu đề "Leaderboard", nút tròn **X** ở góc trên phải (icon đã xuất), 4 tab clay (All time / This week, Highscore / Level), danh sách, pill "Your best" có vương miện ở cuối.
  - **Huy chương** cho hạng 1, 2, 3 (vàng, bạc, đồng, có viền nâu); các dòng khác xen kẽ nền nhạt. **Dòng của chính bạn nổi lên màu vàng** nhờ `userId` được thêm vào mỗi dòng (server gửi kèm, không cần so tên). Số có dấu phẩy.
  - Màn thấp (điện thoại ngang): bỏ tiêu đề, 4 tab nằm chung một hàng cạnh nút X, nên thấy được nhiều dòng hơn. Đóng bằng nút X, Escape, Backspace hoặc nút B tay cầm.
  - Nút Back ở cuối được thay bằng nút X để nhường chỗ cho danh sách.
- **Theme:** thêm `MedalSilver`, `MedalBronze` (hạng nhất dùng vàng của `Reward`).
- **Kiểm tra trong Studio:** iPhone 17 Pro ngang và dọc, với bảng giả gồm 8 và 12 người (có dòng của người chơi ở hạng 4); đã bấm nút X thật, về lại menu. Output không có lỗi. 124 test pass.
- **Lỗi phát hiện và đã sửa:** nút X lúc đầu nằm trong bố cục danh sách (xuất hiện ở giữa phía trên) vì `UIListLayout` xếp mọi con trực tiếp; đã tách nội dung vào một khung riêng.

### Tổng kết M10

| Bước | Kết quả |
|---|---|
| M10a | Theme, font, nút clay, nền trời, 13 ảnh đã tải lên Roblox |
| M10b | Màn chơi: khối bóng, bảng, khay, HUD, panel Pause |
| M10c | Menu và Game Over (Revive dựng sẵn, ẩn đến khi có M8) |
| M10d | Tutorial (thẻ, mũi tên chấm, bàn tay, Skip) và popup combo |
| M10e | Leaderboard |
| M10f | Chuyển động: khối thả trượt vào ô, ghost trượt giữa các ô, hàng sáng lên khi sắp xóa, bảng nhún khi xóa nhiều hàng, khối vừa xoay quay vào chỗ (commit `5988c8e`) |

- **Để lại sau:** âm thanh (hiệu ứng và nhạc, kèm nút Âm thanh và panel Cài đặt), 8 linh vật và theme cosmetic (GĐ4), bản icon trắng cho theme tối.
- **Khác mockup:** ô đích dùng viền liền thay nét đứt; pill level, nút "?" và Leaderboard dạng thẻ là phần mình bổ sung.

## M11: Publish thử và QA

Mình chưa publish được (cần Studio và tài khoản của bạn), nên M11 gồm hai phần: **rà soát code và thử tải trong Studio** (đã xong) và **bộ tài liệu để bạn publish và mời người thử** ([QA.md](QA.md)).

### Rà soát code (theo checklist `roblox-code-review`)

| Mức | Phát hiện | Xử lý |
|---|---|---|
| **Cao** | Lượt hồi sinh đã mua không phân biệt mức giá: mua 1 lượt 10 R$ có thể dùng cho lần hồi sinh thứ hai hoặc ba (đáng ra 15 và 25 R$) | `reviveTokens` thành ba ô theo mức giá `{10, 15, 25}`. Một lượt chỉ dùng cho lần hồi sinh có mức ≤ mức đã mua (dùng mức thấp nhất đủ dùng trước). Dữ liệu **version 3**: `MIGRATIONS[2]` đổi số cũ thành `{0, 0, n}` (lượt cũ được xem là mức cao nhất, nên không ai bị mất) |
| **Trung bình** | Máy chủ đóng lúc còn ghi bảng xếp hạng dở dang thì mất bản ghi | `LeaderboardService`: đếm `writesInFlight`, `game:BindToClose` flush mọi người rồi chờ tối đa 20 giây |
| **Trung bình** | Nút Revive có thể kẹt ở "Please wait…" nếu server không trả lời | Client tự gỡ sau 20 giây (`requestRevive`) |
| **Trung bình** | Chơi ván ngắn liên tục: mỗi ván ghi 4 đến 6 bảng, vượt ngân sách ghi của OrderedDataStore (Studio báo "request was added to queue" khi chạy 25 ván trong 40 giây) | Flush cuối ván giãn tối thiểu 20 giây mỗi người (`flush(player, data, minGap)`). Vòng làm mới 60 giây, `PlayerRemoving` và `BindToClose` vẫn flush đủ nên không mất dữ liệu |
| **Thấp** | `Maximum event re-entrancy depth exceeded for AbsoluteSizeChanged` trong `Hud.fit` thỉnh thoảng xuất hiện khi mở và đóng nhiều panel nhanh | `fit` gộp thành một lượt `task.defer`, không chạy lồng trong tín hiệu kích thước. Chạy 25 ván liên tục không còn lỗi |

Những điểm đã kiểm và **không cần sửa**: mọi remote đều kiểm kiểu và giới hạn tần suất; mã debug chỉ chạy trong Studio; các bảng theo người chơi đều dọn khi rời game; ProfileStore khoá phiên và kick người chơi nếu tải dữ liệu thất bại (không ghi đè bằng dữ liệu mặc định); tên trên bảng xếp hạng là display name của Roblox (đã lọc phía Roblox); cache `names` nhỏ và chỉ giữ tới hết đời server.

### Thử trong Studio

| Kiểm tra | Kết quả |
|---|---|
| Lượt 10 R$ ở lần hồi sinh thứ hai (cần 15 R$) | Nút vẫn hiện "Revive · R$ 15", lượt **không** bị dùng |
| Mua thêm lượt 15 R$ | Hiện "Revive · Free", "You have 1" (chỉ đếm lượt dùng được cho lần này). Hồi sinh dùng lượt 15 R$, giữ nguyên lượt 10 R$ (`reviveTokens=1/0/0`) |
| Hơn 80 ván liên tiếp (năm đợt) kèm hồi sinh | Không có lỗi hay cảnh báo từ game. Số phần tử GUI (khoảng 1.540), heap Lua (khoảng 2,3 đến 2,7 MB), kết nối kéo, hiệu ứng, popup đều **ổn định**, không rò rỉ |
| Mạng chậm (Network Simulator, độ trễ nhận 0,6 giây) | 4 ván liên tiếp rồi game over và hồi sinh: client và server **khớp** (`run=4 score=55 moves=11`, cùng khay), không có cảnh báo "resynced" |
| Bảng xếp hạng sau 25 ván nhanh | Cả bốn bảng đúng, không còn cảnh báo hàng đợi DataStore |
| Output | Chỉ còn cảnh báo `ContentId rbxassetid://203785492` do Studio (đã ghi từ GĐ1, không phải code game) |

- **141 test pass** (thêm 4 test cho token theo mức giá và migration của `Purchases` và `PlayerData`). `stylua`, `selene`, `rojo build` đều sạch.

### Chưa làm được, cần bạn

- **Giao dịch Robux thật** trên bản đã publish (mua 10 R$, huỷ giữa chừng, thoát ngay sau khi mua). Có sẵn trong QA.md, mục 2.
- **Phép thử "người mới hiểu trong 15 giây"** với người thật, và thử trên điện thoại thật. Hướng dẫn gửi tester ở QA.md, mục 3.
- **Mạng chậm thật** (3G, Wi-Fi yếu): Network Simulator trong Studio chỉ mô phỏng độ trễ nhận, không mô phỏng mất gói.
- **Giá hiển thị:** Roblox có thể hiện giá theo vùng trong hộp mua khác với giá cơ bản trên nút.
- **Hạng của chính người chơi** nằm ngoài top 50: `OrderedDataStore` không cho biết, giao diện chỉ hiện top 50 và điểm của bạn.
- Chín **badge ID** (M13) vẫn chờ bạn tạo.
- Bảng xếp hạng **nhiều người chơi** và bảng tuần mới được thử với một người.
