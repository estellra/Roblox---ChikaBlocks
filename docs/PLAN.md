# Kế hoạch build game: ChikaBlock

> Dựa trên tài liệu thiết kế "Chikawa Blast". Tên game: **ChikaBlocks** (đổi từ ChiikaBlocks theo mockup Figma ở M10).

## 1. Các quyết định đã chốt

| Chủ đề | Quyết định |
|---|---|
| Bản quyền | **Không** dùng nhân vật Chiikawa. Tự thiết kế linh vật riêng theo phong cách cute, pastel, tròn trịa. Tên game là **ChikaBlocks** (theo mockup Figma, sau khi M9 dùng tạm ChiikaBlocks; tên trên logo mockup ghi là "working title"). Lưu ý: tên này vẫn gần "Chiikawa", nên còn rủi ro bản quyền/thương hiệu khi publish và kiếm tiền; xem lại trước khi publish. |
| Workflow code | **Rojo + git**. Code nằm trong repo này, sync sang Studio. |
| Lobby | **Chỉ có menu UI**. Vào game là thấy menu, bấm Play là chơi ngay. Không có sảnh 3D. |
| Sinh block | **Công bằng, độ khó tăng dần**. Bộ khối mới luôn có ít nhất 1 khối đặt được. Không ngầm gài để người chơi thua. |
| Bảng chơi | **8x8** |
| Số khối mỗi lượt | **3** (Coop: mỗi người 2 khối) |
| Hồi sinh | **Dọn bớt bảng + cho bộ khối chắc chắn đặt được**. Tối đa 2 lần mỗi ván, lần 2 giá cao hơn. |
| Deadline | Chưa có. Chia theo giai đoạn, giai đoạn nào xong cũng chơi được. |

## 2. Kiến trúc kỹ thuật

### Cấu trúc repo (Rojo)

```
ChikaBlock/
├─ default.project.json        -- map src/ vào DataModel
├─ rokit.toml                  -- pin version rojo, stylua, selene
├─ src/
│  ├─ shared/   → ReplicatedStorage.Shared
│  │  ├─ Board.luau            -- lưới 8x8, kiểm tra đặt khối, xóa hàng/cột
│  │  ├─ Pieces.luau           -- danh sách hình khối (mỗi hướng xoay là 1 khối riêng)
│  │  ├─ Generator.luau        -- sinh bộ 3 khối có seed, độ khó theo điểm
│  │  ├─ Scoring.luau          -- tính điểm, combo
│  │  └─ Config.luau           -- toàn bộ số liệu cần tune (điểm, trọng số, giá)
│  ├─ server/   → ServerScriptService.Server
│  │  ├─ init.server.luau      -- entry duy nhất phía server: load Services, gọi init() rồi start()
│  │  └─ Services/
│  │     ├─ GameService.luau     -- quản lý ván chơi, validate nước đi, sinh bộ khối
│  │     ├─ DataService.luau     -- ProfileStore: highscore, level, cosmetic
│  │     └─ PurchaseService.luau -- ProcessReceipt (hồi sinh, rotate, donate)
│  └─ client/   → StarterPlayer.StarterPlayerScripts.Client
│     ├─ init.client.luau      -- entry duy nhất phía client: load Controllers
│     ├─ Controllers/          -- GameController, DragController, (GĐ2: Menu, Tutorial...)
│     └─ Views/                -- BoardView, TrayView, Hud... chỉ vẽ, không giữ logic game
└─ tests/                      -- unit test cho phần logic trong shared/
```

### Nguyên tắc

- **Logic game là module Luau thuần** (`Board`, `Generator`, `Scoring`), không phụ thuộc UI. Client và server dùng chung một code, và viết unit test được.
- **Server giữ quyền quyết định, client dự đoán trước để phản hồi tức thì:**
  1. Server giữ seed **bí mật** và tự sinh từng bộ khối, rồi gửi bộ khối cho client. Code trong `ReplicatedStorage` thì exploiter đọc được, nên nếu client có seed sẽ biết trước các khối sắp ra.
  2. Khi đặt khối, client cập nhật ngay trên màn hình (độ trễ cảm nhận gần 0ms, đáp ứng yêu cầu <100ms), đồng thời gửi `PlacePiece(pieceIndex, x, y)` lên server.
  3. Server kiểm tra hợp lệ, tự tính điểm rồi xác nhận. Nếu lệch thì client đồng bộ theo server.
  4. Đặt xong khối thứ 3, client chờ bộ khối mới từ server (khoảng một round-trip, được hiệu ứng xóa hàng che đi).
  5. Nhờ vậy điểm trên leaderboard không làm giả được, người chơi không biết trước khối (công bằng cho PVP), và hồi sinh chỉ cấp sau khi server xác nhận giao dịch.
- **Dữ liệu người chơi:** ProfileStore (session lock, chống mất và nhân bản data). **Leaderboard:** OrderedDataStore.
- **Toàn bộ số liệu nằm trong `Config.luau`** để tune mà không phải sửa logic. Sau này có thể chuyển sang ConfigService để chỉnh live.

## 3. Đặc tả gameplay (MVP)

### Khối
- Bộ hình gồm: 1x1, thanh 2–5 ô (ngang và dọc), vuông 2x2 và 3x3, chữ L nhỏ (3 ô) và L lớn (5 ô) theo 4 hướng, chữ L 4 ô và bản lật, T, S/Z.
- Mỗi hướng xoay là một khối riêng trong bộ hình. Từ M15 người chơi xoay được khối trong khay (mỗi ván 1 lượt miễn phí, mua thêm bằng Robux); khối đối xứng không xoay được.

### Thuật toán sinh khối
- Chọn ngẫu nhiên theo trọng số, dùng seed (`Random.new(seed)`).
- Độ khó tăng theo điểm: trọng số dần nghiêng về khối to và khó đặt.
- Bảo đảm công bằng:
  - Điểm thấp: cả bộ 3 khối có ít nhất một cách đặt hết (thử backtracking, chi phí rất nhỏ).
  - Điểm cao: chỉ bảo đảm có ít nhất 1 khối đặt được.
- Khi bảng gần đầy: tăng nhẹ tỉ lệ khối nhỏ để người chơi còn cơ hội gỡ (mercy).

### Tính điểm (số liệu tạm, sẽ tune khi test)
- Đặt khối: +1 điểm mỗi ô.
- Xóa L hàng/cột cùng lúc: điểm cơ bản `{10, 30, 60, 100, 150, 210}[L]`.
- Combo: mỗi lần đặt khối mà có xóa hàng thì combo +1. Combo về 0 sau 3 lần đặt liên tiếp không xóa được hàng nào. Hệ số nhân là `1 + 0.5 × combo`.
- Dọn sạch toàn bộ bảng: +300.
- Khi có combo, linh vật hiện popup kèm câu thoại ("Nice!", "Combo x3!").

### Game over và hồi sinh
- Game over khi không khối nào còn lại đặt vừa. Màn hình hiện điểm, highscore, nút Hồi sinh (Robux), Chơi lại và Về menu.
- Hồi sinh: xóa vùng 4x4 ở giữa bảng, đưa bộ khối mới chắc chắn đặt được. Tối đa 2 lần mỗi ván, mỗi mức giá là một Developer Product riêng.

### Điều khiển
| Nền tảng | Thao tác |
|---|---|
| PC | Giữ chuột lên khối để nhặt, kéo, thả để đặt. Có ghost preview và highlight các hàng sắp xóa. |
| Mobile | Kéo thả bằng ngón tay. Khối hiện lệch lên trên ngón tay để không bị che. |
| Gamepad | LB/RB chọn khối, D-pad hoặc cần trái di chuyển theo từng ô, A đặt, B hủy, Y xoay (khi có lượt xoay). Bàn phím: R xoay ô đang chọn. Chuột và cảm ứng: nút xoay ở góc ô khay. |

### Hướng dẫn (yêu cầu: hiểu cách chơi trong 15 giây)
- Lần chơi đầu dùng một seed cố định: nước đầu tiên chắc chắn xóa được một hàng.
- Linh vật kèm bàn tay động chỉ cách kéo khối vào bảng. Chỉ hiện ở lần chơi đầu tiên.

## 4. Lộ trình theo giai đoạn

### Giai đoạn 0: Setup
- [x] Cài Rokit, Rojo, StyLua, selene, Lune. Tạo `default.project.json`.
- [x] Cài plugin Rojo trong Studio và kết nối với place ChikaBlocks (`86520704157466`).
- [x] Thêm `.gitignore`. Test runner: Lune với `tests/TestKit.luau` (chạy `lune run tests/run.luau`).

### Giai đoạn 1: Prototype gray-box
Kế hoạch chi tiết: [PHASE1.md](PHASE1.md)

- [x] `Board`, `Pieces`, `Generator`, `Scoring` kèm unit test.
- [x] UI thô: lưới 8x8 và 3 khối chờ, kéo thả trên PC và mobile (dùng Device Emulator).
- [x] Vòng chơi đầy đủ: bắt đầu → đặt khối → xóa hàng → game over → chơi lại.
- **Xong khi:** chơi được trọn một ván trong Studio, logic pass toàn bộ test. ✅ Hoàn thành (kết quả từng mốc trong [PHASE1.md](PHASE1.md)).

### Giai đoạn 2: MVP (đủ để publish)
- [x] Server validate nước đi và tính điểm (như mục 2). Chi tiết: [PHASE2.md](PHASE2.md).
- [x] Lưu highscore bằng ProfileStore.
- [x] Hồi sinh bằng Developer Product, xử lý `ProcessReceipt` an toàn khi bị gọi lặp (M8: 3 mức giá 10 / 15 / 25 R$, không giới hạn số lần).
- [x] UI theme pastel, menu chính, màn Game Over, popup linh vật (M10, theo mockup Figma). SFX và nhạc để các giai đoạn sau.
- [x] Tutorial lần đầu chơi. Hỗ trợ gamepad và bàn phím (M9).
- **Xong khi:** đạt ≥95% số lần test không lỗi, người mới hiểu cách chơi trong 15 giây, kéo thả không thấy trễ.
- → Publish bản test (friends/private) rồi public. ✅ Đã publish; đã thử trên PC. Còn thử điện thoại, tay cầm, mua thật và người mới (M11, [QA.md](QA.md)).

### Giai đoạn 3: Giữ chân người chơi và kiếm tiền
Kế hoạch chi tiết: [PHASE3.md](PHASE3.md)

- [x] Level/EXP sau mỗi ván và quà theo mốc highscore và mốc level (danh hiệu, badge; cosmetic từ GĐ4). (M13; badge chờ ID)
- [x] Leaderboard: Highscore, Level, Robux đã donate. (M14: Highscore và Level, toàn thời gian và theo tuần; M16: bảng Supporters riêng.)
- [x] Donate bằng nhiều Developer Product với các mức khác nhau. (M16: 9 mức từ 5 đến 2.500 R$, bảng Supporters.)
- [x] Xoay khối: 1 lần miễn phí mỗi ván, mua thêm bằng Robux. (M15: gói 5 lượt, 25 R$, lượt mua được giữ cho các ván sau.)
- [ ] Rewarded video ad: xem quảng cáo đổi 1 lần hồi sinh hoặc 1 lần xoay.
- [x] AnalyticsService: theo dõi funnel tutorial, lần xóa hàng đầu tiên, game over, mua hồi sinh. (M12: funnel và số liệu ván; funnel `ReviveOffer`, `RotationOffer`, `DonateOffer` làm cùng M8, M15, M16. Số liệu thật chỉ có trên dashboard sau khi publish.)
- [x] Dọn dẹp sau publish (M18, đã thử trong Studio trên PC; còn điện thoại dọc, tay cầm, script xóa với API thật): hiệu ứng chờ bộ khối mới, nút xoay đủ cỡ chạm trên điện thoại ngang, xoay khối khi đang kéo, công cụ xóa dữ liệu người chơi theo yêu cầu. Chi tiết: [PHASE3.md](PHASE3.md).
- [ ] Hoãn lại (theo bạn): badge (chờ tạo ID), SFX và nhạc, Rewarded video ad, toàn bộ GĐ4 Cosmetic.

### Giai đoạn 4: Cosmetic
- [ ] Theme cho bảng chơi, skin cho khối, gói VFX và SFX khi combo.
- [ ] Cửa hàng cosmetic.
- [ ] Crate (nếu làm): bắt buộc công bố tỉ lệ rơi, kiểm tra `PolicyService` vì vật phẩm ngẫu nhiên trả phí bị cấm ở một số quốc gia.
- [ ] Vật phẩm limited theo sự kiện.

### Giai đoạn 5: Coop 2 người
Kế hoạch chi tiết (đã duyệt): [PHASE5.md](PHASE5.md)

- [ ] Hai người dùng chung một bảng, mỗi người 2 khối, đặt tự do cùng lúc. Chỉ khi cả hai đặt hết thì mới sinh bộ khối tiếp theo.
- [ ] Server giữ trạng thái chung. Mời bạn trong cùng server. Một người rời thì người kia chơi tiếp, điểm Coop chốt tại lúc đó.
- [ ] Leaderboard riêng cho Coop, xếp theo cặp.

### Giai đoạn 6: PVP Ranked
- [ ] Chốt luật PVP (xem câu hỏi mở).
- [ ] Hệ thống ELO, matchmaking (trong server, hoặc liên server bằng MemoryStore và reserved server).
- [ ] Leaderboard rank và quà theo mùa.

## 5. Rủi ro và cách xử lý

| Rủi ro | Cách xử lý |
|---|---|
| Bản quyền | Dùng linh vật và tên game riêng. Không dùng ảnh hay nhân vật Chiikawa ở bất kỳ đâu (icon, thumbnail, mô tả game). |
| Thiếu thời gian (đồ án UIT) | Mỗi giai đoạn đều chơi được. MVP chỉ gồm Giai đoạn 0–2. |
| Không có tiền quảng cáo | Đầu tư icon và thumbnail. Ván chơi ngắn, dễ chơi lại. Coop giúp người chơi rủ bạn. |
| Cạnh tranh với game block puzzle khác | Khác biệt nhờ linh vật cute, Coop và PVP, cùng cảm giác kéo thả mượt trên mobile. |

## Câu hỏi còn mở

Các câu hỏi này không chặn Giai đoạn 0–1, nhưng cần trả lời trước khi tới giai đoạn tương ứng:

1. **Linh vật** (trước M10): linh vật trông thế nào, ai vẽ asset 2D? Tên game đã chốt là ChikaBlocks.
2. **Ngôn ngữ UI:** đã chốt tiếng Anh (M9). Có thể thêm tiếng Việt qua LocalizationTable sau.
3. **Giá Robux** (trước GĐ2–3): hồi sinh lần 1 và lần 2, xoay khối, các mức donate.
4. **Publish dưới tài khoản cá nhân hay Group?** (trước GĐ2): nếu 2 người chia doanh thu thì nên dùng Group.
5. **Quà theo mốc:** đã chốt. Mốc highscore và mốc level đều tặng danh hiệu kèm badge; thêm cosmetic từ GĐ4 (xem quyết định W trong [PHASE3.md](PHASE3.md)).
6. **Luật PVP** (trước GĐ6): cùng seed và đua điểm trong 2–3 phút, hay xóa hàng để "tấn công" đẩy khối rác sang bảng đối thủ? Vẫn chưa chốt khi lên plan GĐ5, nên GĐ5 chỉ dựng phần dùng chung chắc chắn (lời mời và phòng 2 người).
7. **Lore** (tùy chọn): viết một câu chuyện ngắn cho linh vật mới.
