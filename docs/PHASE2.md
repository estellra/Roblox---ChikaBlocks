# Giai đoạn 2: MVP đủ để publish

Mục tiêu theo [PLAN.md](PLAN.md): game an toàn trước gian lận, lưu được điểm, có hồi sinh bằng Robux, có giao diện thật, người mới hiểu cách chơi trong 15 giây.

## Các mốc

| Mốc | Nội dung | Cần trước | Trạng thái |
|---|---|---|---|
| **M6** Server giữ quyền quyết định | `GameService` chạy `GameSession` trên server, seed bí mật, client dự đoán và đồng bộ lại khi lệch | Không | ✅ Xong |
| **M7** Lưu dữ liệu | ProfileStore (qua Wally): best, số ván, cờ "đã xem tutorial" | Bật *Enable Studio Access to API Services* | ✅ Xong |
| **M8** Hồi sinh bằng Robux | Developer Product, `ProcessReceipt` an toàn khi gọi lặp, giá tăng dần | Giá Robux, tạo product, chọn Group hay cá nhân | |
| **M9** Menu, tutorial, gamepad | Màn hình chính, tutorial lần đầu (ván dựng sẵn), bàn phím và tay cầm qua Input Action System | Ngôn ngữ (English) | ✅ Xong |
| **M10** Giao diện thật | Làm lại `Views/` theo mockup Figma, linh vật (âm thanh để sau) | Không | 🔶 M10a–d xong; còn M10e |
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
| M10e | Leaderboard và Cài đặt theo cùng phong cách, âm thanh (nếu chốt AH) | Icon trophy, close, sound |

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
