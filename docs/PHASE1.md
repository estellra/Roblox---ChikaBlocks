# Giai đoạn 1: Prototype gray-box

Mục tiêu: chơi được trọn một ván trong Studio, trên PC và trên mobile (dùng Device Simulator). Hình ảnh chỉ là khối màu trơn. Toàn bộ logic phải có unit test.

Đã đối chiếu với các skill `roblox-luau`, `roblox-architecture`, `roblox-ui`, `roblox-input`, `roblox-testing` và `roblox-studio-mcp`. Những chỗ khác với khuyến nghị của skill đều đã được chốt ở [mục cuối](#quyết-định-khi-đối-chiếu-với-skill).

## Phạm vi

**Có trong GĐ1**
- Logic thuần trong `src/shared`: RNG có seed, bộ hình khối, bảng chơi, tính điểm, sinh khối, phiên chơi (`GameSession`), và logic hồi sinh (chưa có phần mua).
- UI thô dựng bằng code: điểm số, bảng 8x8, khay 3 khối, màn Game Over với nút Chơi lại.
- Kéo thả bằng chuột và cảm ứng, có ghost preview và highlight các hàng sắp xóa.
- Tắt avatar (`Players.CharacterAutoLoads = false`). Ẩn player list, giữ chat.

**Để sang GĐ2:** server validate và RemoteEvent, lưu dữ liệu, mua hồi sinh, menu chính, theme pastel, linh vật, SFX/VFX, tutorial, gamepad.

> GĐ1 chạy hoàn toàn trên client. Vì `GameSession` là module thuần và nhận nguồn bộ khối qua tham số, sang GĐ2 server chạy đúng module này để kiểm tra nước đi, còn client nhận bộ khối từ server, không phải viết lại.

## Cấu trúc file

Theo `roblox-architecture`: mỗi bên chỉ có một entry script, mọi thứ còn lại là ModuleScript.

```
src/shared/                    → ReplicatedStorage.Shared
  Config.luau        -- số liệu điểm, độ khó, trọng số khối
  Rng.luau           -- xorshift32 có seed
  Pieces.luau        -- 37 hình khối cố định hướng
  Board.luau         -- lưới 8x8: canPlace, place, tìm và xóa hàng/cột
  Scoring.luau       -- điểm đặt khối, điểm xóa hàng, combo
  Generator.luau     -- sinh bộ 3 khối theo trọng số và độ khó, có bảo đảm công bằng
  GameSession.luau   -- trạng thái một ván: khay, điểm, combo, game over, hồi sinh
src/server/                    → ServerScriptService.Server
  init.server.luau   -- bootstrap: require mọi module trong Services/, gọi init() rồi start()
                     -- (GĐ1 chưa có service nào; Services/ có từ GĐ2)
src/client/                    → StarterPlayer.StarterPlayerScripts.Client
  init.client.luau   -- chờ game.Loaded, ẩn player list, bootstrap Controllers/
  Controllers/
    GameController.luau  -- giữ GameSession, nhận nước đi, cập nhật các view
    DragController.luau  -- nhặt, kéo, snap, thả (chuột và cảm ứng) — M4
    DebugController.luau -- chỉ trong Studio: cầu điều khiển cho playtest qua MCP
  Views/
    Theme.luau       -- design token: màu, font, cỡ chữ, bo góc, khoảng cách
    Create.luau      -- helper tạo instance (gán Parent sau cùng)
    Gui.luau         -- tạo 3 ScreenGui (nền, game, overlay) và bố cục co giãn
    BoardView.luau   -- 64 ô, chỉ vẽ lại ô thay đổi (ghost, highlight, hiệu ứng xóa ở M4)
    TrayView.luau    -- 3 ô khay, vẽ khối trên lưới 5x5
    Hud.luau         -- điểm, best (trong phiên), overlay Game Over
tests/
  Rng.spec, Pieces.spec, Board.spec, Scoring.spec, Generator.spec, GameSession.spec, Simulation.spec
```

- Controller có dạng `{ init: (self) -> ()?, start: (self) -> ()? }`. `init` không được yield, `start` thì được.
- `default.project.json` đặt `Players.CharacterAutoLoads = false` và `StarterGui.ScreenOrientation = Sensor`.

## Đặc tả logic

### Quy ước
- Tọa độ `x` là cột (0–7, trái sang phải), `y` là hàng (0–7, trên xuống dưới).
- Ô lưu trong mảng phẳng 64 phần tử, chỉ số `y * 8 + x + 1`. Giá trị `0` là ô trống, `1..n` là màu.
- Module trong `shared/` **không được dùng Roblox API** (`Random`, `Vector2`, `game`...), để Lune test được và server dùng lại được. Require nhau bằng `require("./Board")` (`./` là thư mục cha của script, tức các module cùng cấp).
- Mọi file mở đầu bằng `--!strict`, kiểu dữ liệu export bằng `export type`. Thêm `--!native` cho `Board` và `Generator` nếu benchmark cho thấy cần.

### Rng
- Thuật toán xorshift32 dùng `bit32`. Hàm `Rng.new(seed)`, `:nextFloat()` trả về `[0, 1)`, `:nextInt(min, max)`.
- Cùng seed thì cho cùng chuỗi số. Dùng cho test, seed tutorial (GĐ2) và bộ sinh khối phía server.

### Pieces
37 hình, mỗi hướng là một khối riêng:

| Nhóm | Hình | Số khối |
|---|---|---|
| Nhỏ (1–3 ô) | chấm 1x1; thanh 2 và 3 (ngang/dọc); L 3 ô (4 hướng) | 9 |
| Vừa (4 ô) | thanh 4 (ngang/dọc); vuông 2x2; L 4 ô và bản lật (8 hướng); T (4 hướng); S/Z (4 hướng) | 19 |
| Lớn (5–6 ô) | thanh 5 (ngang/dọc); chữ nhật 2x3 và 3x2; L lớn 3x3 (4 hướng) | 8 |
| Rất lớn (9 ô) | vuông 3x3 | 1 |

Mỗi khối gồm `id`, `cells` (danh sách `{x, y}` đã chuẩn hóa về góc trên trái), `width`, `height`, `size` (nhóm) và `color`.

**Màu cố định theo họ hình** (8 màu, `Config.COLOR_COUNT`): chấm, thanh, góc 3 ô, khối vuông/chữ nhật, L/J 4 ô, T, S/Z, L lớn. Client map chỉ số màu 1–8 sang bảng màu của theme.

### Board
- `Board.new()`, `canPlace(board, piece, x, y)` (kiểm tra trong biên và không chồng ô), `place(...)`.
- `findCompleteLines(board)` trả về các hàng và cột đầy. Hàng và cột được xóa **cùng lúc**, nên ô nằm ở giao điểm chỉ tính một lần.
- `hasAnyPlacement(board, piece)` và `fillRatio(board)`.

### Scoring (số liệu tạm, nằm trong `Config`)
- Đặt khối: `+1` mỗi ô.
- Xóa `L` đường cùng lúc: `CLEAR_POINTS[L]`, với `CLEAR_POINTS = {10, 30, 60, 100, 150, 210}`. Một lần đặt xóa tối đa được 6 đường.
- Combo:
  - Lần đặt có xóa hàng: `combo += 1`, đặt `movesSinceClear = 0`, điểm xóa nhân với `1 + 0.5 × (combo − 1)`.
  - Lần đặt không xóa hàng: `movesSinceClear += 1`. Khi `movesSinceClear` đạt 3 thì `combo = 0`.
- Bảng trống hoàn toàn sau khi xóa: `+300`.
- Điểm được làm tròn xuống.

### Generator
Đầu vào là bảng hiện tại, điểm số và `Rng`. Đầu ra là 3 khối.

1. **Tỉ lệ theo nhóm:** mỗi lần bốc chọn nhóm theo tỉ lệ, rồi chọn đều một khối trong nhóm. Tỉ lệ nội suy giữa mức dễ và mức khó theo `t = clamp(score / 8000, 0, 1)`:

   | Nhóm | Dễ (0 điểm) | Khó (từ 8000 điểm) |
   |---|---|---|
   | Nhỏ | 30% | 15% |
   | Vừa | 45% | 40% |
   | Lớn | 20% | 33% |
   | Rất lớn (3x3) | 5% | 12% |

   Mỗi bộ có tối đa 1 khối 3x3.
2. **Mercy:** khi `fillRatio > 0.6`, tỉ lệ nhóm Nhỏ nhân 2 rồi chuẩn hóa lại.
3. **Bảo đảm công bằng** (bốc lại tối đa 30 lần cho tới khi bộ khối đạt yêu cầu):

   | Điểm | Yêu cầu với bộ khối |
   |---|---|
   | < 1500, hoặc khi hồi sinh | Đặt được **cả 3** theo một thứ tự nào đó, có tính cả việc xóa hàng giữa các lần đặt. Kiểm tra bằng backtracking, giới hạn 20.000 node. |
   | 1500 – 5000 | **Từng khối** đều có chỗ đặt trên bảng hiện tại. |
   | ≥ 5000 | **Ít nhất 1 khối** đặt được. |

   Khi hồi sinh, bộ khối được bốc theo tỉ lệ mức dễ.
4. **Dự phòng:** nếu sau 30 lần vẫn không đạt, bốc thêm tối đa 10 lần chỉ từ nhóm Nhỏ, cuối cùng chia 3 khối 1x1. Bộ 3 khối 1x1 luôn đặt được, vì sau mỗi nước đi mọi hàng đầy đều bị xóa nên mỗi hàng luôn còn ít nhất 1 ô trống.
5. **Solver:** chạy trên row mask 8 bit thay vì mảng ô của `Board`. Nhánh được cắt bỏ khi một nước không xóa hàng nào trong lúc mọi khối còn lại đều không có chỗ đặt (đặt thêm ô không bao giờ tạo thêm chỗ trống). Test so sánh với tìm kiếm vét cạn trên 200 bảng.
6. **Hiệu năng (mục tiêu < 2ms trung bình, < 20ms chậm nhất):** đo được 0.02ms trung bình và dưới 1ms chậm nhất, cả trong Lune lẫn trên server Studio. Không cần `--!native`.

### GameSession
Nguồn bộ khối được **truyền vào** (dependency injection, theo `roblox-testing`). Nhờ vậy test có thể đưa bộ khối cố định, GĐ1 dùng `Generator` cục bộ, còn GĐ2 server dùng `Generator` với seed bí mật và client nhận bộ khối qua remote.

```lua
type DealReason = "Normal" | "Revive"
type SetSource = (board: Board, score: number, reason: DealReason) -> { Piece }

local session = GameSession.new(setSource: SetSource, initialBoard: Board?)
session.board, session.tray      -- tray: { Piece | false } x3, false = ô đã dùng
session.score, session.combo, session.isOver, session.revivesUsed, session.moveCount
session:canPlace(slot, x, y) -> boolean
session:place(slot, x, y) -> PlaceResult?  -- nil nếu nước đi không hợp lệ, trạng thái giữ nguyên
-- PlaceResult = { slot, piece, x, y, clearedRows, clearedCols, cellsCleared, points, combo,
--                 boardCleared, refilled, isOver }
session:revive() -> boolean      -- xóa vùng 4x4 giữa bảng, reset combo, lấy bộ khối "Revive", tối đa 2 lần
```
- Đặt hết 3 khối thì tự gọi `setSource` để lấy bộ mới.
- Sau mỗi lần đặt hoặc lấy bộ mới, nếu không khối nào còn trong khay đặt được thì `isOver = true`.
- `slot`, `x`, `y` được xem là dữ liệu không tin cậy (sang GĐ2 server truyền thẳng từ client): sai kiểu, không nguyên, NaN, vô cực hay ngoài biên đều trả về `nil`, không throw.

## Đặc tả UI và điều khiển

### Giao diện (theo `roblox-ui`)
- **UI gray-box là placeholder.** Khi có mockup ở GĐ2, phần `Views/` sẽ được làm lại theo mockup; logic và cơ chế kéo thả giữ nguyên. Mọi màu, font, cỡ chữ, bo góc và khoảng cách đọc từ token trong `Theme.luau`, nên đổi giao diện (hoặc bán theme ở GĐ4) chủ yếu là đổi token.
- **Ba ScreenGui**, đều có `ResetOnSpawn = false`:
  - `Background`: `IgnoreGuiInset = true` rồi mới đặt `ScreenInsets = None` (đặt `IgnoreGuiInset` sẽ tự đổi `ScreenInsets`), chỉ có một Frame màu phủ kín màn hình.
  - `Game`: `ScreenInsets = CoreUISafeInsets` (theo docs: tránh cả tai thỏ lẫn top bar của Roblox), `SafeAreaCompatibility = None`. Toàn bộ phần tương tác nằm ở đây, cùng lớp `DragLayer` cho M4.
  - `Overlay`: phủ kín màn hình, chỉ bật khi Game Over.
- **Bố cục co giãn**, tính lại mỗi khi vùng an toàn đổi kích thước (xoay máy, đổi thiết bị):
  - **Màn dọc** (rộng/cao < 1.1): HUD → Bảng → Khay xếp dọc, 3 ô khay nằm ngang.
  - **Màn ngang**: bảng bên trái; bên phải là cột gồm HUD và 3 ô khay xếp dọc.
  - Mọi kích thước dùng Scale; bảng và ô khay vuông nhờ `UIAspectRatioConstraint` (`FitWithinMaxSize`). 64 ô đặt bằng Scale (mỗi ô `1/8` cạnh lưới).
  - Chỉ lúc kéo thả mới đọc `AbsolutePosition` và `AbsoluteSize` để tính snap.
- **Khay:** mỗi khối vẽ trên lưới ảo 5x5 căn giữa ô khay (có lề trong), nên mọi khối cùng cỡ ô và khối dài 5 ô vừa khít.
- **Phóng to/thu nhỏ bằng `UIScale`, không tween `Size`:** khi nhặt, khối phóng từ cỡ ô khay lên cỡ ô bảng. Hiệu ứng xóa ô cũng dùng `UIScale`.
- Nút "Play again" dùng `Activated` (chạy được với chuột, cảm ứng và gamepad).
- **Chữ:** số điểm và dòng "Best" dùng `TextScaled` có `UITextSizeConstraint` chặn trên dưới (vùng HUD cao thấp rất khác nhau giữa điện thoại dọc và TV). Chữ trong panel dùng cỡ cố định. Vùng chạm tối thiểu 44×44 px.
- **Ngôn ngữ:** chữ trên UI bằng tiếng Anh; tiếng Việt thêm sau qua LocalizationTable.
- Tạo xong toàn bộ cây UI rồi mới gán `Parent` cho `PlayerGui`, để chỉ chạy layout một lần.

### Kéo thả (tự viết bằng UserInputService)
- **Bắt đầu kéo:** từ `InputBegan` của chính ô khay (GuiObject). `UserInputService.InputBegan` báo `gameProcessedEvent = true` khi bấm lên GUI, nên không bắt đầu kéo từ sự kiện đó.
- **Theo dõi khi đang kéo:**
  - Cảm ứng: theo dõi đúng `InputObject` Touch đã bắt đầu, qua `UserInputService.InputChanged` và `InputEnded`.
  - Chuột: đọc `InputChanged` loại `MouseMovement`, kết thúc khi `InputEnded` loại `MouseButton1`.
- **Lúc nhặt:** khối được chuyển sang một lớp kéo (Frame phủ màn hình có `ZIndex` cao) để không bị layout của khay kéo lại.
- **Với cảm ứng** (`input.UserInputType == Touch`): khối vẽ cao hơn ngón tay khoảng 1,5 ô để không bị che.
- **Snap:** `gx = round((gócTrênTráiKhối − board.AbsolutePosition) / cạnhÔ)`, tính tương tự cho `gy`.
  - Đặt hợp lệ thì hiện ghost và highlight các hàng/cột sẽ xóa.
  - Thả ở vị trí hợp lệ thì gọi `GameController`. Không hợp lệ thì khối tween về khay.
- **Chuẩn bị cho gamepad ở GĐ2:** `DragController` tách phần "ý định" (`pick(slot)`, `moveTo(gx, gy)`, `drop()`, `cancel()`) khỏi phần đọc input. GĐ2 chỉ cần thêm bindings bằng Input Action System gọi đúng các hàm này.
- Viết handler sao cho vẫn đúng khi signal chạy kiểu **Deferred** (handler chạy cuối frame, không chạy ngay lúc fire).
- Giữ lại mọi connection và disconnect khi kết thúc kéo hoặc khi chơi lại, để không rò bộ nhớ.

### Hiệu ứng và Game Over
- **Hiệu ứng xóa (gray-box):** ô nháy sáng rồi `UIScale` thu về 0 trong khoảng 0.15 giây.
- **Game Over:** overlay hiện điểm, best trong phiên và nút "Chơi lại" (tạo `GameSession` mới).

## Kiểm tra

- **Logic:** `lune run tests/run.luau` (Lune và TestKit). Các module trong `shared/` đều thuần nên test được hết.
- **Trong Studio, qua Studio MCP (theo `roblox-studio-mcp`):**
  - Code sửa trên đĩa và để Rojo sync, **không** sửa script trong Studio, vì Rojo sẽ ghi đè.
  - Playtest bằng `start_stop_play`, đọc lỗi bằng `get_console_output`, kiểm tra trạng thái bằng `execute_luau` trong context Client, xem giao diện bằng `screen_capture`. Xong luôn dừng play.
- **Thiết bị:** kiểm tra bằng Device Simulator ở các cấu hình điện thoại dọc, điện thoại ngang, tablet và màn 1080p, dùng skill `rbx-device-simulator-lua` của Studio để đổi thiết bị tự động.
  - Chỉ đổi được thiết bị ở chế độ Edit, nên mỗi máy phải: dừng play → chọn máy → bấm Play → chụp.
  - Chọn thiết bị trước rồi mới đặt hướng màn hình (đặt hướng khi đang giả lập laptop sẽ lỗi).
- **Cầu debug (chỉ trong Studio):** `PlayerScripts.ChikaDebug:Invoke(lệnh, ...)` gọi từ `execute_luau` context Client. Lệnh: `state`, `layout`, `place slot x y`, `autoplay n`, `gameover`, `restart`. `DebugController` cũng in `[Layout] …` ra Output mỗi khi bố cục đổi.
- **Lưu ý môi trường:**
  - `execute_luau` ở chế độ Edit giữ cache module đã require, nên muốn chạy code mới thì kiểm tra trong playtest.
  - `rojo serve` không nạp lại thay đổi `$properties` trong `default.project.json`; phải khởi động lại server rồi Connect lại trong Studio.

## Các mốc thực hiện

Mỗi mốc kết thúc bằng: test pass, `stylua --check` và `selene` sạch, rồi commit.

| Mốc | Nội dung | Kiểm tra |
|---|---|---|
| **M1** Logic cơ bản | `Rng`, `Pieces`, `Board`, `Scoring` | Test: RNG xác định theo seed; 37 khối hợp lệ và không trùng; đặt khối và xóa hàng/cột (cả trường hợp giao nhau); bảng điểm và combo |
| **M2** Sinh khối và phiên chơi | `Generator`, `GameSession` (nhận `SetSource`), `revive` | Test: chạy 10.000 bộ khối trên bảng ngẫu nhiên, mỗi bộ đều đạt yêu cầu công bằng theo đúng mức điểm; `GameSession` với bộ khối cố định cho kết quả đúng; game over và lấy bộ mới đúng lúc; benchmark hiệu năng; bot tự chơi 200 ván không lỗi |
| **M3** Khung client và vẽ UI | `init` hai bên, `GameController`, `Gui`, `BoardView`, `TrayView`, `Hud`, tắt avatar, ẩn player list | Playtest qua MCP: không lỗi Output; `screen_capture` cho thấy bảng vuông và nằm giữa ở 1080p, trên điện thoại dọc và ngang, trên tablet |
| **M4** Kéo thả | `DragController`, ghost, highlight, hiệu ứng xóa | Bạn chơi thử bằng chuột và bằng Device Simulator (cảm ứng); khối luôn snap đúng ô và không bị ngón tay che |
| **M5** Vòng chơi hoàn chỉnh | Game over, Chơi lại, best trong phiên | Chơi đến lúc thua rồi chơi lại 3 lần liền, không lỗi và không tăng số connection. Tick checklist GĐ1 trong `PLAN.md` |

**Hoàn thành GĐ1 khi:** chơi trọn một ván trên PC và trên giả lập điện thoại, không có lỗi trong Output, và toàn bộ test logic pass.

## Quyết định khi đối chiếu với skill

| Chủ đề | Skill khuyên | Quyết định |
|---|---|---|
| Kéo thả | `UIDragDetector` (`roblox-ui`) | **Tự viết bằng UserInputService.** Cần toàn quyền với snap, nâng khối trên ngón tay và đổi lớp khi kéo. Skill khuyên `UIDragDetector` chủ yếu để thay `Draggable` đã deprecated. |
| Unit test | Jest Lua (`roblox-testing`) | **Giữ Lune + TestKit.** Skill cũng ghi nhận Lune cho module Luau thuần, và toàn bộ logic GĐ1 đều thuần. |
| Cấu trúc code | Một entry mỗi bên, `Services/` và `Controllers/` (`roblox-architecture`) | **Theo skill.** |
| Nguồn bộ khối (GĐ2) | Không đặt thứ cần bí mật trong `ReplicatedStorage` (`roblox-architecture`) | **Server giữ seed và gửi từng bộ khối.** `GameSession` nhận nguồn bộ khối qua tham số. |
| ScreenInsets | `CoreUISafeInsets` cho UI tương tác (`roblox-ui`) | Theo skill: tách riêng ScreenGui nền và ScreenGui game. |
| Layout và hiệu ứng | Scale, constraint, `UIScale` (`roblox-ui`) | Theo skill: bỏ module `Layout`, chuyển sang Scale và `UIAspectRatioConstraint`. |
| Gamepad | Mọi thao tác đều có binding gamepad (`roblox-input`) | Vẫn làm ở GĐ2 như PLAN.md. GĐ1 tách lớp ý định trong `DragController` để GĐ2 gắn Input Action System vào. |

### Quyết định khi review plan M2

| Điểm | Quyết định |
|---|---|
| A. Trọng số khối | Tính theo **nhóm**, ghi dưới dạng tỉ lệ phần trăm (bảng ở mục Generator). |
| B. Khối 3x3 | Tối đa **1 khối 3x3** mỗi bộ. |
| C. Màu khối | **Cố định theo họ hình**, không ngẫu nhiên. |
| D. Hồi sinh | **Reset combo** khi hồi sinh. |

### Kết quả M2

- 55 test pass, bao gồm 10.000 bảng ngẫu nhiên cho Generator và 200 ván bot tự chơi.
- Bot (ưu tiên xóa hàng, sau đó chọn chỗ đặt khít nhất) đạt trung bình 3.129 điểm sau 134 nước; 65% số ván vượt 1.500 điểm và 24% vượt 5.000 điểm. Số liệu này dùng làm mốc khi tune độ khó.

### Quyết định khi review plan M3

| Điểm | Quyết định |
|---|---|
| E. Bố cục và xoay màn hình | **Hai bố cục (dọc/ngang) tự chuyển**, giữ xoay tự do (`Sensor`). |
| F. Công cụ debug | **Có** `DebugController`, chỉ tạo trong Studio. |
| G. Ngôn ngữ UI | **Tiếng Anh**, tiếng Việt thêm sau qua LocalizationTable. |
| Theme | **Dạng token** trong `Theme.luau`, để làm lại theo mockup (GĐ2) và bán theme (GĐ4) dễ dàng. |

### Kết quả M3

Playtest qua MCP, không có lỗi trong Output (cảnh báo `rbxassetid://203785492` đến từ Studio, không phải code của game).

| Thiết bị | Viewport | Bố cục | Bảng | Ô khay / ô bảng |
|---|---|---|---|---|
| Average Laptop | 1365×768 | Ngang | 681 px | 39% |
| iPhone 17 Pro, ngang | 749×381 | Ngang | 310 px | 39% |
| iPhone 17 Pro, dọc | 401×777 | Dọc | 384 px | 49% |
| iPad Pro M5 13", ngang | 1375×1031 | Ngang | 792 px | 46% |
| Samsung Galaxy A06, ngang | 705×338 | Ngang | 268 px | 39% |
| Xbox One | 1920×1080 | Ngang | 953 px | 39% |

- Bảng luôn vuông, nằm trong vùng an toàn (né top bar và tai thỏ), overlay Game Over vừa màn hình ở mọi máy.
- Đã sửa trong lúc kiểm tra: chữ "Best" quá nhỏ trên TV và tablet (chuyển sang `TextScaled` có chặn 14–28 px); khối dài 5 ô chạm mép ô khay (thêm lề trong ô khay).
- **Để lại cho lúc làm UI theo mockup:** ở màn ngang, ô trong khay chỉ bằng ~39% ô trên bảng (trên Galaxy A06 chỉ 12.7 px). Vẫn nhìn rõ hình và ô khay đủ lớn để chạm (63 px), nhưng mockup nên bố trí khay to hơn ở màn ngang.
