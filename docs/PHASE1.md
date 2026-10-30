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
    DragController.luau  -- nhặt, kéo, snap, thả (chuột và cảm ứng)
  Views/
    Gui.luau         -- tạo 2 ScreenGui (nền và game), không giữ logic
    BoardView.luau   -- 64 ô, ghost preview, highlight, hiệu ứng xóa
    TrayView.luau    -- 3 ô khay, vẽ khối thu nhỏ
    Hud.luau         -- điểm, best (trong phiên), overlay Game Over
tests/
  Rng.spec, Pieces.spec, Board.spec, Scoring.spec, Generator.spec, GameSession.spec
```

- `Main.server.luau` và `Main.client.luau` hiện có sẽ được thay bằng hai file `init` ở trên.
- Controller có dạng `{ init: (self) -> ()?, start: (self) -> ()? }`. `init` không được yield, `start` thì được.
- `default.project.json` thêm `Players.$properties.CharacterAutoLoads = false`.

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

Mỗi khối gồm `id`, `cells` (danh sách `{x, y}` đã chuẩn hóa về góc trên trái), `width`, `height`, `size` (nhóm).

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

1. **Trọng số khối** nội suy giữa mức dễ và mức khó theo `t = clamp(score / 8000, 0, 1)`:

   | Nhóm | Dễ (t = 0) | Khó (t = 1) |
   |---|---|---|
   | Nhỏ | 3 | 1.5 |
   | Vừa | 3 | 3 |
   | Lớn | 2 | 3 |
   | Rất lớn | 0.5 | 1.5 |

2. **Mercy:** khi `fillRatio > 0.6`, trọng số nhóm Nhỏ nhân 2.
3. **Bảo đảm công bằng** (chọn ngẫu nhiên lại tối đa 30 lần cho tới khi bộ khối đạt yêu cầu):

   | Điểm | Yêu cầu với bộ khối |
   |---|---|
   | < 1500 | Đặt được **cả 3** theo một thứ tự nào đó, có tính cả việc xóa hàng giữa các lần đặt. Kiểm tra bằng backtracking, giới hạn 20.000 node. |
   | 1500 – 5000 | **Từng khối** đều có chỗ đặt trên bảng hiện tại. |
   | ≥ 5000 | **Ít nhất 1 khối** đặt được. |

4. **Dự phòng:** nếu sau 30 lần vẫn không đạt, lấy bộ khối nhỏ nhất đặt vừa. Khối 1x1 luôn đặt được, vì bảng không thể kín hết 64 ô (bảng kín thì mọi hàng đều đầy và đã bị xóa).
5. Hiệu năng: sinh một bộ trung bình < 2ms, chậm nhất < 20ms. Có test benchmark để kiểm tra.

### GameSession
Nguồn bộ khối được **truyền vào** (dependency injection, theo `roblox-testing`). Nhờ vậy test có thể đưa bộ khối cố định, GĐ1 dùng `Generator` cục bộ, còn GĐ2 server dùng `Generator` với seed bí mật và client nhận bộ khối qua remote.

```lua
type SetSource = (board: Board, score: number) -> { Piece }

local session = GameSession.new(nextSet: SetSource)
session.board, session.tray      -- tray: { Piece? } x3, nil = đã dùng
session.score, session.combo, session.isOver, session.revivesUsed
session:canPlace(slot, x, y) -> boolean
session:place(slot, x, y) -> PlaceResult?  -- nil nếu nước đi không hợp lệ
-- PlaceResult = { cells, clearedRows, clearedCols, points, combo, boardCleared, refilled, isOver }
session:revive() -> boolean      -- xóa vùng 4x4 giữa bảng, lấy bộ khối mới, tối đa 2 lần
```
- Đặt hết 3 khối thì tự gọi `nextSet` để lấy bộ mới.
- Sau mỗi lần đặt hoặc lấy bộ mới, nếu không khối nào còn trong khay đặt được thì `isOver = true`.

## Đặc tả UI và điều khiển

### Giao diện (theo `roblox-ui`)
- **Hai ScreenGui**, đều có `ResetOnSpawn = false` và `ZIndexBehavior = Sibling`:
  - `Background`: `IgnoreGuiInset = true`, `ScreenInsets = None`, chỉ có một Frame màu phủ kín màn hình.
  - `Game`: `ScreenInsets = CoreUISafeInsets` để tránh tai thỏ và thanh top bar của Roblox. Toàn bộ phần tương tác nằm ở đây.
- **Layout dùng Scale và constraint, không tính pixel bằng tay:**
  - Cột dọc gồm HUD điểm, bảng chơi, khay 3 khối.
  - Bảng có `Size = UDim2.fromScale(0.9, 0.55)` cùng `UIAspectRatioConstraint` (`AspectRatio = 1`, `AspectType = FitWithinMaxSize`), nên luôn vuông và tự co theo màn hình hoặc khi xoay máy.
  - 64 ô được đặt bằng Scale (mỗi ô `1/8` cạnh bảng).
  - Chỉ lúc kéo thả mới đọc `AbsolutePosition` và `AbsoluteSize` để tính snap.
- **Phóng to/thu nhỏ bằng `UIScale`, không tween `Size`:** khối trong khay có scale 0.55, nhặt lên thì tween về 1.0. Hiệu ứng xóa ô cũng dùng `UIScale`.
- Nút "Chơi lại" dùng `Activated` (chạy được với chuột, cảm ứng và gamepad), không dùng `MouseButton1Click`.
- Chữ dùng `TextSize` cố định kèm `UITextSizeConstraint` khi cần, tránh `TextScaled`. Vùng chạm tối thiểu khoảng 44×44 px.
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
- **Thiết bị:** kiểm tra bằng Device Simulator ở các cấu hình điện thoại dọc, điện thoại ngang, tablet và màn 1080p. Có thể dùng skill `rbx-device-simulator-lua` của Studio để đổi thiết bị tự động.

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
