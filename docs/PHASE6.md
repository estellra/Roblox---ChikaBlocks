# Giai đoạn 6: PVP Ranked

> Plan đã duyệt. Mọi điểm BB đến CD đã chốt, xem [cuối file](#quyết-định-đã-chốt). Các số cần mô phỏng (bảng đòn, số giây khóa khay, điểm khi xóa hàng rác) chốt lại ở M24. Những gì còn chờ bạn trả lời nằm ở [Câu hỏi mở](#câu-hỏi-mở). Mockup PC đã có (14 màn, xem [Mockup giao diện](#mockup-giao-diện-pc)). M24 đã cài, xem [Kết quả M24](#kết-quả-m24); chưa có code cho M25 trở đi.

## Bối cảnh

- GĐ5 để lại sẵn: `Rooms` (phòng 2 người, mang `mode`), `RoomService`, giao thức lockstep có `seq` (`CoopRuns` + `CoopSync`), interface `Source` của `GameController` (M21), bạn chơi giả `coopbot`, bảng xếp hạng theo `OrderedDataStore` và công cụ xóa dữ liệu.
- PVP khác Coop ở chỗ **mỗi người một bảng riêng**. Vì vậy ván PVP gần với ván solo (`GameSession` + `GameRuns`, dự đoán theo `moveIndex`) hơn là với `CoopSession`. Hai lớp "đã xác nhận + đang chờ" của `CoopSync` chỉ cần khi hai người sửa chung một bảng; PVP tránh được nhờ chỉ áp rác ở ranh giới bộ khối (BH).
- `Rooms.Mode` hiện chỉ có `"coop"`, và `CoopService` bắt đầu ván Coop cho **mọi** phòng lập xong. Thêm `"pvp"` thì phải sửa cả hai chỗ.
- **Trạng thái kiểm thử còn nợ từ GĐ5:** màn hình của M19, M21, M22 chưa chạy đủ trong Studio; danh sách thử solo của M6 chưa chạy lại sau khi `TrayView`, `GameController`, `DragController`, `GamepadController`, `Hud` bị sửa. Việc này ảnh hưởng tới thứ tự làm: xem [Thứ tự và cổng kiểm UI](#thứ-tự-và-cổng-kiểm-ui).
- Skill `roblox-*` đã nạp trước khi lên plan: game-systems, networking, security, data-stores, teleport-matchmaking, analytics-liveops. Không có chỗ nào skill nói ngược với hướng trong `PLAN.md`. Một chỗ skill gợi ý thêm mà plan cũ chưa dùng (ConfigService cho cờ bật tắt) nằm ở câu hỏi mở số 3.

## Mục tiêu

- Hai người đấu một ván 3 phút, kết quả do server quyết, không làm giả được.
- Có điểm rank (ELO), hàng chờ ghép cặp, bảng Rank theo mùa và quà cuối mùa.
- Không bán lợi thế trong PVP.
- Dữ liệu mới xóa được theo yêu cầu bằng `scripts/erase-user.luau`.
- Code solo và Coop không đổi hành vi; 309 test hiện có pass mà không sửa.

## Luật chơi PVP

### Ván đấu

- **Mỗi người một bảng 8×8, khay 3 khối, tính điểm như solo** (ô đặt, xóa hàng, combo, dọn sạch bảng).
- **Đồng hồ 3 phút (BE).** Server gửi `startAt` và `endAt` theo `workspace:GetServerTimeNow()`; client tự vẽ đếm ngược 3-2-1 và đồng hồ. Hết giờ, **ai điểm cao hơn thắng**; bằng điểm là **hòa** (BL).
- **Cùng nguồn khối (BJ).** Bộ khối thứ *k* của hai người rút từ cùng một seed con, nên hai người gặp cùng "vận may". Chi tiết và giới hạn ở [Nguồn khối](#nguồn-khối-chung-bj).
- **Xoay:** mỗi người `PVP.FREE_ROTATIONS` (1) lượt miễn phí mỗi ván. **Lượt xoay đã mua và hồi sinh trả tiền không dùng được trong PVP (BK).**

### Rác (BC, BF, BG, BH, BI)

- **Kiếm đòn:** xóa nhiều hàng cùng lúc hoặc xóa hàng khi combo cao sinh ra "đòn", tính bằng số hàng rác. Bảng khởi điểm (chốt sau mô phỏng M24):

| Nước đi | Đòn (hàng rác) |
|---|---|
| Xóa 1 hàng/cột | 0 |
| Xóa 2 | 1 |
| Xóa 3 | 2 |
| Xóa 4 trở lên | 3 |
| Nước có xóa hàng khi combo ≥ 8 (chốt ở M24, trước là 3) | +1 |
| Dọn sạch bảng | +2 |

- **Triệt tiêu (BF):** đòn của mình trừ vào rác đang chờ của mình trước, bắt đầu từ hàng **sắp vào nhất**; phần dư mới sang hàng chờ rác của đối thủ. Hàng chờ tối đa `PVP.GARBAGE_QUEUE_MAX` (4), dư thì bỏ hàng mới nhất.
- **Dạng rác (BC):** một **hàng rác** gồm 7 ô xám và 1 lỗ, đẩy vào từ **đáy, trái hoặc phải**; hướng và vị trí lỗ do server rút ngẫu nhiên (1 trong 3 hướng, lỗ 1 trong 8 ô).
- **Báo trước hướng (CB):** hướng được rút **ngay lúc hàng rác vào hàng chờ** và gửi cho nạn nhân, nên người chơi thấy trước từng hàng rác đang chờ sẽ vào từ phía nào và kịp dọn mép đó. Vị trí lỗ vẫn rút lúc rác vào bảng, không báo trước.
  - Từ đáy: mọi hàng dịch lên một hàng, hàng rác thành hàng dưới cùng.
  - Từ trái: mọi cột dịch sang phải, hàng rác thành cột ngoài cùng bên trái. Từ phải thì ngược lại.
- **Áp rác ở ranh giới bộ khối (BH):** rác chỉ vào bảng lúc nạn nhân đặt xong khối thứ 3 và sắp nhận bộ mới, tối đa `PVP.GARBAGE_PER_SET` (1) hàng mỗi lần. Lúc đó client vốn đang chờ server trả bộ khối, nên không có nước dự đoán nào bị lật lại, và ping cao không bị thiệt. Bộ khối mới được kiểm công bằng trên bảng **sau khi** rác vào, nên cam kết "bộ mới luôn có khối đặt được" giữ nguyên.
- **Chi tiết hàng rác (BG):**
  - Hàng/cột bị đẩy ra khỏi mép đối diện **biến mất**, không tính điểm.
  - Nếu sau khi đẩy có hàng/cột đầy thì xóa ngay, **không điểm, không đổi combo**.
  - Ô rác là ô thường (màu xám, id `COLOR_COUNT + 1`): hàng chứa ô rác vẫn xóa được. **Hàng rác vụn (CD):** hàng/cột có quá nửa số ô là rác khi xóa thì không có điểm xóa hàng, không tăng combo, không sinh đòn; hàng có ít rác hơn tính như hàng thường.

### Hết nước trước giờ (BD)

- Khi không khối nào trong khay đặt vừa: server tự **xóa vùng 4×4 giữa bảng, đặt lại combo, chia bộ mới chắc chắn đặt được** (dùng lại `GameSession.revive`), và **khóa khay `PVP.STUCK_LOCK_SECONDS` (5) giây**. Màn hình ghi "Stuck! Board cleared" kèm thanh đếm.
- Rác đang chờ **không** áp trong lần chia này (chỉ áp ở lần chia thường), và không bị xóa.
- Số giây khóa chốt bằng mô phỏng: một bot cố tình để hết nước không được thắng bot chơi bình thường.

### Kết thúc, rời ván (BL, BM)

- **Hết giờ:** nước đi tính theo lúc **server nhận**. Nước tới sau `endAt + PVP.END_GRACE_SECONDS` (0,3 giây, như nhau cho mọi người) bị bỏ. Client khóa khay đúng `endAt` theo đồng hồ đồng bộ.
- **Rời ván hoặc rớt mạng = thua** (xử thua ngay, đối thủ thắng). Không có kết nối lại trong bản đầu.
- **Server tắt có báo trước** (cập nhật, đóng server): ván đang dở bị **hủy**, không ai đổi điểm.
- Hết ván: màn kết quả có điểm hai bên, số hàng rác đã gửi và đã đỡ, thay đổi điểm rank. Ván ranked có nút **Queue again**; ván giao hữu có **Play again** (cần cả hai, như Coop) và **Menu**.

### Ba loại ván

| Loại | Vào bằng | Tính rank | Ghi chú |
|---|---|---|---|
| `ranked` | Hàng chờ | Có | Không có đấu lại trực tiếp |
| `friendly` | Lời mời (`Rooms`, mode `"pvp"`) | Không | Đấu lại được |
| `bot` | Nút "Practice" khi hàng chờ vắng, hoặc lệnh debug | Không | Ghi rõ đối thủ là bot |

## Các mốc

| Mốc | Nội dung | Cần trước | Chơi được gì khi xong |
|---|---|---|---|
| **M24** Luật PVP | `Board.pushLine`, `PvpSession` (nguồn khối chung, đòn, triệt tiêu, rác, hết nước), mô phỏng để chốt số | Không | Chỉ có Lune test |
| **M25** ELO, rank, mùa | `Elo`, `PvpRating`, `Seasons`, trường dữ liệu mới, "ghi trước khoản thua" | Không | Chỉ có Lune test; `data` in ra trường `pvp` |
| **M26** Ván PVP giao hữu | `PvpMatches`, `PvpService`, `Rooms` mode `"pvp"`, remote, client (bảng đối thủ, đồng hồ, thanh rác, kết quả), `pvpbot` | M24, cổng kiểm UI | Đấu giao hữu qua lời mời hoặc với bot. `PVP.ENABLED = false` ngoài Studio |
| **M27** Hàng chờ ranked trong server | `Matchmaker`, `MatchmakingService`, tính ELO, chống cày điểm, bot khi vắng | M25, M26 | Ranked trong cùng server. Bật `PVP.ENABLED` |
| **M28** Bảng Rank, mùa, quà, dữ liệu | Bảng `Rank_<mùa>`, tab Rank, chuyển mùa, huy chương, xóa dữ liệu, analytics | M27 | Bảng Rank và quà cuối mùa |
| **M29** Ghép liên server | MemoryStore + reserved server + `TeleportAsync` | M27 và số liệu hàng chờ (BQ) | Ghép với người ở server khác. Có plan riêng khi tới nơi |

### Thứ tự và cổng kiểm UI

- **M24 và M25 độc lập, toàn logic thuần**, không đụng file giao diện nào. Bắt đầu ngay được, làm cái nào trước cũng được (mình đề xuất M24 trước vì mô phỏng sẽ cho biết luật rác có ổn không).
- **Trước M26 cần một lượt kiểm UI trong Studio (BY).** M26 sửa đúng các file mà thay đổi của Coop chưa được nhìn thấy chạy: `GameController` (`Source`), `TrayView`, `Hud`, `HudBar`, `BoardView`. Xây PVP lên trên phần chưa kiểm thì lỗi chồng lỗi và không biết lỗi của mốc nào. Lượt kiểm gồm:
  - Danh sách thử solo của M6 (kéo thả chuột và cảm ứng, game over, revive, xoay, tutorial).
  - Màn hình M19, M21, M22 với `coopbot` trong một cửa sổ Studio: màn Co-op, thẻ mời, khay hai người dọc và ngang, Game Over Coop, tab Co-op, thanh EXP.
- **Test hai người thật của GĐ5 vẫn để sau khi publish** như bạn đã chọn, không chặn M26. Nhưng nên chạy lượt đó **trước khi bật M27**: lời mời và phòng là phần dùng chung, lỗi ở đó sẽ thành lỗi của ranked.
- Sau đó M26 → M27 → M28. M29 chỉ làm khi số liệu cho thấy cần.

## Kiến trúc

| File | Mới? | Vai trò |
|---|---|---|
| `src/shared/Board.luau` | Sửa | Thêm `pushLine(board, side, hole, color)`. Hàm cũ không đổi |
| `src/shared/Generator.luau` | Sửa | `Overrides` thêm `MERCY_SMALL_MULTIPLIER`. Mặc định không đổi, cùng seed ra đúng bộ cũ |
| `src/shared/PvpSession.luau` | Mới | Bọc một `GameSession` 3 khối: nguồn khối theo seed con, bảng đòn, hàng chờ rác, áp rác, hết nước và khóa khay, ví xoay. Dùng chung hai phía |
| `src/server/PvpMatches.luau` | Mới | Như `GameRuns` nhưng theo trận: hai `PvpSession`, đồng hồ, nhận nước, chuyển đòn, kết thúc, xử thua. Logic thuần, đồng hồ và seed truyền vào |
| `src/server/Elo.luau` | Mới | Công thức ELO thuần |
| `src/server/PvpRating.luau` | Mới | Luật đổi dữ liệu rank: ghi trước khoản thua, chốt kết quả, chuyển mùa, hạng, huy chương |
| `src/server/Seasons.luau` | Mới | Mã mùa theo thời gian, ngưỡng hạng, quà |
| `src/server/Matchmaker.luau` | Mới | Hàng chờ thuần: vào, rút, ghép theo cửa sổ điểm nới dần |
| `src/server/Services/PvpService.luau` | Mới | Nối `PvpMatches` với remote, phòng, dữ liệu, bảng Rank, analytics |
| `src/server/Services/MatchmakingService.luau` | Mới | Nối `Matchmaker` với remote, điều kiện vào hàng chờ, đếm cặp trong MemoryStore |
| `src/server/Rooms.luau`, `RoomService.luau` | Sửa | `Mode` thêm `"pvp"`; `Rooms.form(a, b, mode)` lập phòng không qua lời mời (cho hàng chờ); `CoopInvite` nhận loại phòng |
| `src/server/Services/CoopService.luau` | Sửa | Chỉ nhận phòng `mode == "coop"` |
| `src/server/Services/DataService.luau` | Sửa | `beforeRelease(callback)`: gọi trước `EndSession` để chốt ván đang dở |
| `src/server/PlayerData.luau`, `Leaderboards.luau`, `LeaderboardService.luau`, `Erasure.luau`, `scripts/erase-user.luau` | Sửa | Trường `pvp`, bảng `Rank_<mùa>`, store mỗi mùa trong kế hoạch xóa |
| `src/client/Util/PvpSync.luau` | Mới | Logic thuần phía client: bản dự đoán theo `moveIndex`, áp kết quả server (rác, bộ khối, hết nước), phát hiện lệch |
| `src/client/Controllers/PvpController.luau`, `PvpRunController.luau` | Mới | Hàng chờ và màn Rank; nguồn ván PVP sau interface `Source` |
| `src/client/Views/PvpView.luau`, `OpponentBoardView.luau` | Mới | Màn hàng chờ, màn VS, kết quả; bảng nhỏ của đối thủ |
| `Hud`, `HudBar`, `BoardView`, `TrayView`, `LeaderboardView`, `CoopView`, `MenuView` | Sửa | Đồng hồ, thanh rác sắp tới, màu ô rác, hiệu ứng đẩy bảng, khóa khay, tab Rank, nút Duel, nút Ranked |
| `Net`, `Config`, `Telemetry`, `DebugService` | Sửa | Remote mới, `Config.PVP`, sự kiện mới, lệnh debug |

Một người chỉ ở trong **một** thứ tại một thời điểm: ván solo, phòng (Coop hoặc PVP), hoặc hàng chờ. Vào phòng thì rời hàng chờ và ván solo kết thúc (analytics ghi cách kết thúc `pvp`). Attribute `CoopBusy` giữ tên cũ, thêm giá trị `"queue"`.

### Tái dùng từ Coop và làm mới

| Tái dùng | Cách dùng |
|---|---|
| `Rooms`, `RoomService` | Lời mời giao hữu, phòng, rời phòng, `memberLeft` để xử thua |
| `GameSession`, `Generator`, `Scoring` | Nguyên luật; `PvpSession` dùng nguồn khối trả `nil` rồi `receiveSet`, nên **không sửa `GameSession`** |
| `GameRuns` (mẫu), `RateLimiter`, `Validate` | `PvpMatches` theo đúng khuôn kết quả `accepted` / `resync` / `ignored` |
| Interface `Source` của `GameController` (M21) | `PvpRunController` là nguồn thứ ba, phần vẽ và điều khiển dùng chung |
| Bài học M23: thứ tự chỉ bảo đảm trong một remote | Mọi tin có thứ tự của trận đi chung `PvpEvent` |
| `CoopHover` (`UnreliableRemoteEvent`) | Cùng cách cho bảng của đối thủ |
| `coopbot` | `pvpbot`: đối thủ giả chạy trên server, cũng là đối thủ luyện tập khi hàng chờ vắng |
| `CoopLockstep.spec` (tin trễ ngẫu nhiên) | `PvpLockstep.spec` |
| `LeaderboardService` (ghi có giãn cách, đọc mỗi phút), `Erasure` | Bảng Rank theo mùa |
| `CoopInviteView`, Game Over Coop | Thẻ mời ghi loại phòng; màn kết quả PVP |

**Không dùng:** `CoopSession`, `CoopRuns`, `CoopSync` (bảng chung, chỗ ngồi, hai lớp). **Làm mới:** mọi file "Mới" ở bảng trên.

## Mockup giao diện (PC)

Bạn gửi 14 mockup màn ngang cho PC; file nằm trong [`docs/mockups/phase6/`](mockups/phase6/). Giao diện PVP làm theo các mockup này (BX). Màn chưa có mockup thì dựng cùng phong cách bằng `Theme`/`Clay`.

| File | Màn | Mốc | Điều rút ra cho việc cài |
|---|---|---|---|
| `01-coop-screen-duel` | Màn Co-op có nút Duel | M26 | Mỗi người rảnh có hai nút **Duel** (xanh) và **Invite** (hồng); người bận chỉ có một nút mờ ghi lý do (In tutorial, In a room, Joining...). Tiêu đề và dòng mô tả vẫn là Co-op |
| `02-match-countdown` | Đếm ngược 3-2-1 | M26 | Số to giữa bảng kèm "Get ready!", cả màn mờ đi. Khay và bảng đối thủ đã hiện, đồng hồ đứng ở 3:00 |
| `03-duel-invite-card` | Thẻ mời Duel khi đang chơi solo | M26 | "Mia invites you to a Duel", "+2", thanh đếm, Decline và Accept; nằm trên vùng điểm số như thẻ mời Co-op của M19 |
| `07-match-playing` | Trong trận | M26 | Bố cục chuẩn: xem [M26, Client](#client) |
| `04-match-garbage-arrives` | Rác vừa vào | M26 | Hàng xám 7 ô + 1 lỗ; mũi tên ở mép bảng chỉ hướng rác vào; dòng dưới khay ghi "+1 garbage from Mia"; cột IN bớt một nấc |
| `12-match-stuck-locked` | Hết nước | M26 | Thẻ "Stuck! Board cleared" giữa bảng, vùng 4×4 giữa đã trống, khay mờ kèm vòng đếm số giây, dòng "Tray unlocks in 5"; rác chờ vẫn còn trong cột IN |
| `13-vs-practice-bot`, `14-vs-ranked` | Màn VS | M26, M27 | Nhãn trên cùng ("Ranked match" hoặc "Practice match · no rank change"); hai thẻ có vòng tròn chữ cái đầu, tên, hạng và điểm rank; bot ghi "Practice bot"; "Starting..." |
| `10-result-friendly-loss` | Kết quả giao hữu | M26 | Linh vật buồn, "Mia wins", "Time's up · friendly duel, no rank change", điểm hai bên, "Garbage sent 2 · blocked 4", "Mia wants a rematch", Play again và Menu |
| `11-result-ranked-win` | Kết quả ranked | M27 | Linh vật vui, "You win!", "Time's up · higher score wins", ô "Gold 1,320 → 1,338 +18", Queue again và Menu |
| `06-menu-ranked-button` | Menu | M27 | Nút **Ranked** (vàng) cùng hàng với Co-op; Leaderboard có hàng riêng bên dưới |
| `08-queue-searching` | Hàng chờ | M27 | Hạng và điểm, "14W 9L · Season 2026M12", ba chấm động, "Finding an opponent...", "Waited 0:12 · 3 other players can be matched here", Cancel |
| `09-queue-empty-options` | Hàng chờ vắng | M27 | Thêm dòng "Nobody to play right now. You can keep waiting, or:" và ba nút Keep waiting, Practice vs bot, Invite friends |
| `05-leaderboard-rank-tab` | Tab Rank | M28 | Dòng "Season 2026M12 · ends Dec 31"; bốn tab một hàng; top 3 có huy hiệu vàng, bạc, đồng; mỗi dòng có biểu tượng hạng, tên, tên hạng bên dưới, điểm; ô "You: Gold · 1,320 · 14W 9L" |

### Mockup trả lời hoặc đổi điều gì trong plan

- **Bảng nhỏ của đối thủ có màu khối** (plan cũ chỉ gửi ô có/không). Đổi BW: gửi màu từng ô. Màu gắn với họ khối, nên việc suy ra khối của đối thủ dễ hơn một chút (liên quan câu hỏi mở 2).
- **Cột IN của đối thủ** hiện trên thẻ đối thủ: plan đã gửi số rác chờ của đối thủ, khớp.
- **Tab Rank hiện tên hạng dưới tên người chơi**, không hiện danh hiệu mốc: trả lời câu hỏi mở 5 (quyết định CA).
- **Vòng tròn chữ cái đầu** thay cho ảnh đại diện Roblox: không phải tải thumbnail.
- **Khay hiện trong lúc đếm ngược:** hai bên có 3 giây nhìn bộ đầu tiên, như nhau.
- **Kết quả ghi "blocked N":** là số hàng rác đã triệt tiêu (`cancelled`).

### Mockup khác plan hoặc chưa rõ

Các điểm này nằm ở câu hỏi mở 8 đến 11; mình không tự chọn.

- `04` vẽ hàng rác **thay** hàng đáy (7 hàng trên giữ nguyên chỗ), còn BC đã chốt là **đẩy** cả bảng lên và hàng trên cùng mất. Bạn đã xác nhận: theo BC, mockup chỉ minh họa.
- Mũi tên hướng rác: mockup cho thấy nó lúc rác đã vào, còn plan cũ rút hướng lúc áp rác nên không báo trước được. Bạn đã chọn **có báo trước** (CB): hướng rút lúc rác vào hàng chờ. Mockup chưa vẽ mũi tên trong các nấc IN; mình dựng theo phong cách hiện có.
- Nút Pause có trong HUD của trận, nhưng trận có đồng hồ thì không dừng được.
- Menu thêm một hàng nút so với hiện tại (M19 đã phải gộp Co-op với Leaderboard cho vừa điện thoại ngang thấp).

### Chưa có mockup

- **Mọi màn trên điện thoại** (dọc và ngang): 14 mockup đều là PC.
- Rác vào từ trái và phải; bảng Pause hoặc bỏ cuộc; kết quả ranked thua, hòa, đối thủ rời; trận "Unrated" vì cặp đã đủ 2 trận trong ngày; nút Ranked khi bị khóa (chưa đủ level, private server); thông báo chuyển mùa và huy chương; chỗ hiện huy chương các mùa trước.

## M24: Luật PVP

### `Board.pushLine`

- `pushLine(board, side, hole, color)` với `side` là `"bottom"`, `"left"` hoặc `"right"`, `hole` từ 0 đến 7. Dịch cả bảng một ô về phía đối diện, bỏ hàng/cột bị đẩy ra, ghi hàng rác (7 ô `color`, 1 ô trống tại `hole`). Trả về các hàng/cột đầy sau khi đẩy để nơi gọi xóa.
- Tham số sai (hướng lạ, lỗ ngoài bảng, không nguyên) thì báo lỗi; hàm này chỉ server và bản sao client gọi, không nhận dữ liệu thẳng từ remote.

### Nguồn khối chung (BJ)

- **Vấn đề:** `Generator.nextSet` rút thử lại tới khi bộ khối qua được kiểm công bằng trên bảng của người đó, và tỉ lệ nhóm khối phụ thuộc điểm và độ đầy bảng. Hai người dùng chung một `Rng` thì luồng số lệch nhau ngay khi hai bảng khác nhau.
- **Cách làm:** bộ thứ *k* rút từ `Rng.new(mix(seed, k))`, nên dù trước đó ai rút thử lại bao nhiêu lần, cả hai đều bắt đầu bộ *k* với cùng dãy ứng viên. Ứng viên đầu tiên qua được kiểm công bằng trên bảng của mình thì nhận.
  - Độ khó theo **số thứ tự bộ**, không theo điểm: truyền "điểm ảo" `k × PVP.DIFFICULTY_SCORE_PER_SET` vào `nextSet`, nên tỉ lệ nhóm khối và mức công bằng giống nhau cho hai bên.
  - Bỏ mercy trong PVP (`MERCY_SMALL_MULTIPLIER = 1`), vì nó phụ thuộc độ đầy bảng của từng người.
  - Bộ chia sau khi hết nước rút từ luồng riêng `mix(seed, "revive", chỗ, j)`, không làm lệch số thứ tự bộ thường.
  - Hướng và lỗ của hàng rác rút từ luồng riêng theo nạn nhân: hướng lúc vào hàng chờ (CB), lỗ lúc vào bảng.
- **Hệ quả cần biết:** hai bảng khác nhau nhiều thì ứng viên đầu có thể không vừa bảng của một bên, bên đó nhận ứng viên kế. "Cùng nguồn khối" nghĩa là cùng dãy ứng viên, không phải lúc nào cũng cùng bộ. M24 đo tỉ lệ bộ trùng nhau giữa hai bot.
- **Rò thông tin:** người đi chậm hơn nhìn bảng đối thủ có thể suy ra khối sắp tới của mình. Xem câu hỏi mở số 2.

### `PvpSession`

- Giữ một `GameSession` với nguồn khối trả `nil` (bảng luôn "chờ bộ khối" sau khối thứ 3), rồi tự giao bộ bằng `receiveSet`. Server và client chạy cùng một đường: `deliver(garbage, set)` áp các hàng rác rồi giao bộ.
- `place(slot, x, y, now)`: từ chối khi đang khóa khay hoặc ngoài giờ; còn lại giao cho `GameSession.place`. Trả thêm `attack` (đòn của nước này), `cancelled` (đã trừ vào rác chờ), `sent` (phần sang đối thủ).
- `receiveAttack(lines, rng)` (chỉ server): rút hướng cho từng hàng rác rồi thêm vào cuối hàng chờ, cắt ở trần. Hàng chờ là danh sách hướng theo thứ tự sẽ vào bảng; client nhận nguyên danh sách.
- Triệt tiêu lấy khỏi **đầu** hàng chờ (hàng sắp vào nhất).
- `refill(rng)` (chỉ server): lấy tối đa 1 hàng rác khỏi đầu hàng chờ (hướng đã có), rút lỗ, áp, xóa hàng đầy không điểm, rút bộ thứ *k*, trả `{ garbage, set }` để gửi client.
- `unstick(now)`: khi `isOver`, gọi `GameSession.revive`, giao bộ từ luồng revive, đặt `lockedUntil`.
- `rotate(slot)`: `GameSession.rotateWith(slot, free, 0)` với ví miễn phí của ván; không có lượt mua.
- Snapshot = snapshot `GameSession` + `setIndex`, `pending` (danh sách hướng của rác chờ), `lockedUntil`, `freeRotations`, `sentTotal`, `takenTotal`, `stuckCount`.

### Mô phỏng (chốt số)

`tests/PvpSimulation.spec.luau`: hai bot tham lam đấu nhau, mỗi bot một nhịp đặt khối cố định (giả lập 3 phút bằng đồng hồ giả). In ra và dùng để chốt:

| Câu hỏi | Mục tiêu |
|---|---|
| Rác có gây hại không? | Bot nhận rác có điểm trung vị thấp hơn 10–25% so với cùng bot không nhận rác. Nếu rác lại làm **tăng** điểm (hàng rác 7/8 ô là hàng dễ xóa) thì đổi luật theo câu hỏi mở số 1 |
| Mỗi người gửi bao nhiêu hàng rác một ván? | Trung vị 3–6; chỉnh bảng đòn |
| Hết nước bao nhiêu lần một ván? | Trung vị 0–2 |
| Cố tình hết nước có lợi không? | Bot "tự sát" thua bot thường ở ≥ 90% ván; chỉnh số giây khóa |
| Hai bot nhận cùng bộ khối bao nhiêu phần trăm? | Chỉ để biết và ghi lại |
| Chia bộ trên bảng có rác chậm không? | Tệ nhất dưới vài ms, như solo |

### Test

- **Lune:**
  - `Board.pushLine`: ba hướng, bảng dịch đúng, hàng bị đẩy ra mất, vị trí lỗ, màu rác, hàng đầy sau khi đẩy, tham số sai.
  - `Generator`: ghi đè mercy; mặc định cùng seed vẫn ra đúng bộ cũ.
  - `PvpSession`: cùng seed và cùng nước đi cho cùng bộ khối; bảng khác nhau vẫn nhận cùng ứng viên đầu khi nó vừa; lần chia sau hết nước không làm lệch số thứ tự bộ; bảng đòn; triệt tiêu lấy hàng sắp vào nhất; trần hàng chờ bỏ hàng mới nhất; hướng rút lúc vào hàng chờ và không đổi tới lúc vào bảng; rác vào bảng đúng hướng đã báo; rác chỉ vào ở lần chia thường và tối đa 1 hàng; bộ mới luôn qua kiểm công bằng trên bảng đã có rác; hết nước thì dọn bảng và khóa khay (đồng hồ giả), nước trong lúc khóa bị từ chối; ví xoay chỉ có lượt miễn phí; snapshot đi và về.
  - `PvpSimulation`: 200 trận bot, kiểm bất biến sau mỗi nước (không còn hàng đầy, điểm không giảm, rác chờ không âm và không quá trần), cộng một client giả dựng lại từng sự kiện của server và phải khớp từng ô.
  - 309 test cũ pass không sửa.
- **Studio:** không có gì, đúng như mốc.
- **Hai người thật:** không có gì.

### Kết quả M24

Đã cài: `Board.pushLine`, `Generator.Overrides.MERCY_SMALL_MULTIPLIER`, `Rng.mix` (seed con cho bộ thứ *k*, luồng `"stuck"` và `"garbage"` theo chỗ), `Config.PVP`, `src/shared/PvpSession.luau`. Test: `PvpSession.spec` và `PvpSimulation.spec`, cộng test mới trong `Board`, `Generator`, `Rng`, `Config`. 347 test pass; 309 test cũ không sửa.

- **Khác plan một chút:** `PvpSession` tự giữ luồng rác của nạn nhân, nên `receiveAttack(lines)` và phần chia bộ không nhận `rng`. Phía server, `place` tự chia bộ sau khối thứ 3 (`refill`) và tự gỡ khi hết nước (`stuck`); kết quả trả về mang hai phần đó để gửi client. Phía client dùng `deliver`, `applyStuck`, `setPending`.
- **Bộ thứ *k*** dùng độ khó của điểm `(k - 1) × DIFFICULTY_SCORE_PER_SET`, nên bộ đầu tiên dễ như lúc bắt đầu ván solo.

Mô phỏng: 200 trận giữa hai bot tham lam, mỗi nước mất 1,5–2,5 giây. Thêm 100 trận bot tự sát gặp bot tham lam.

**Lần chạy đầu, với số khởi điểm** (combo ≥ 3 cộng đòn, hàng rác tính điểm như hàng thường):
- Điểm khi có rác **cao hơn 7,2%** so với không rác. Mục tiêu là thấp hơn 10–25%.
- Mỗi người gửi trung vị **21** hàng rác một ván. Mục tiêu là 3–6.

Lý do:
- **Điểm cộng combo là nguồn chính của rác.** Bot tham lam giữ combo rất dài: bỏ điểm cộng combo thì số rác gửi rơi từ 21 xuống 2.
- **Rác đang giúp nạn nhân.** Mỗi lần đẩy rác là xóa miễn phí một hàng ở mép đối diện, và hàng 7/8 ô rất dễ ăn điểm.

**Các biến thể đã thử** (điểm khi có rác so với không rác; số rác gửi trung vị):

| Biến thể | Điểm | Rác gửi |
|---|---|---|
| Số khởi điểm | +7,2% | 21 |
| Bỏ điểm cộng combo | +3,0% | 2 |
| Bảng `{0,0,1,2}`, không cộng combo | +0,4% | 0 |
| Cộng combo từ combo 4 / 5 / 8 | +11,7% / +9,2% / +7,5% | 19 / 16,5 / 11 |
| 2 lỗ / 3 lỗ | +0,6% / −8,4% | 20 / 19 |
| 2 lỗ, 2 hàng rác mỗi bộ | −3,6% | 20 |
| Hàng quá nửa là rác thì không điểm (gọi là "hàng rác vụn") | −11,3% | 18 |
| Hàng rác vụn, cộng combo từ combo 6 / **8** / 10 / 12 | −11,4% / **−9,7%** / −8,6% / −4,8% | 11 / **8** / 6 / 5 |
| Hàng rác vụn, cộng combo chỉ khi xóa ≥ 2 hàng | −4,4% | 3 |

Không biến thể nào đạt cả hai mục tiêu: gửi ít thì rác vào ít, nên hại ít.

**Đã chốt (CD):**
- Thêm luật **hàng rác vụn**: hàng/cột có quá `JUNK_LINE_GARBAGE_SHARE` (một nửa) số ô là rác (tính trên bảng trước nước đi) vẫn xóa, nhưng không có điểm xóa hàng, không tăng combo, không sinh đòn.
- `ATTACK_COMBO_FROM = 8`.
- Chọn mốc 8 thay vì 10, vì người thật giữ combo ngắn hơn bot nên sẽ gửi ít rác hơn số đo.

**Số cuối cùng:**

| Câu hỏi | Mục tiêu | Đo được | Đạt? |
|---|---|---|---|
| Rác có gây hại không? | Điểm trung vị thấp hơn 10–25% | 1563 có rác, 1731 không rác: thấp hơn 9,7% | Gần đạt |
| Số hàng rác gửi mỗi người một ván | Trung vị 3–6 | 8 | Hơi cao, chấp nhận (người thật giữ combo ngắn hơn bot) |
| Số lần hết nước mỗi người một ván | Trung vị 0–2 | Trung vị 1, nhiều nhất 5 | Có |
| Cố tình hết nước có lợi không? | Bot tự sát thua ≥ 90% | Thua 100% (trung vị 16 lần hết nước); giữ khóa 5 giây | Có |
| Hai bot nhận cùng bộ | Chỉ ghi lại | 88% của 5619 bộ | — |
| Thời gian chia bộ | Dưới vài ms | Trung bình 0,043 ms, tệ nhất 0,84 ms | Có |

Chỉnh lại sau lượt thử với người thật ở M26: đổi `ATTACK_COMBO_FROM` và `JUNK_LINE_GARBAGE_SHARE` trong `Config.PVP`.

## M25: ELO, rank, mùa

### Công thức (BN)

- `E = 1 / (1 + 10^((Rđối − Rmình) / 400))`, `R' = R + round(K × (S − E))`, với `S` là 1 (thắng), 0,5 (hòa), 0 (thua).
- Điểm khởi đầu **1000**. Sàn **100**.
- **K = 40** trong 10 ván ranked đầu tiên của tài khoản (xếp hạng nhanh), **K = 24** sau đó, **K = 16** từ 1800 điểm trở lên. Mỗi người dùng K của mình, nên tổng điểm không bảo toàn tuyệt đối; chấp nhận.
- Mức thay đổi của thắng, hòa, thua tính được ngay **lúc trận bắt đầu** (chỉ phụ thuộc điểm hai bên trước trận). Điều này cần cho "ghi trước".

### Ghi trước khoản thua (chống rút dây)

Vấn đề đã gặp ở M22: người rớt mạng có thể bị giải phóng dữ liệu trước khi sự kiện rời phòng tới. Với Coop chỉ mất một lần đếm ván; với ranked thì thành cách né thua. Cách xử lý:

1. **Trận ranked bắt đầu:** ghi vào dữ liệu của cả hai `pvp.pending = { id, win, draw, loss, at }` (ba mức thay đổi đã tính sẵn).
2. **Trận kết thúc bình thường:** áp đúng mức theo kết quả, xóa `pending`.
3. **Một người rời khi dữ liệu còn:** `DataService.beforeRelease` gọi `PvpService` trước `EndSession`: áp mức thua, xóa `pending`. Đối thủ nhận mức thắng ngay.
4. **Dữ liệu đã rời server trước khi kịp chốt** (ví dụ vào game trên thiết bị thứ hai để cướp phiên): `pending` nằm lại trong profile đã lưu. Lần vào sau, `PvpRating.settleStale` thấy `pending` cũ thì áp mức thua.
5. **Server tắt có báo trước (`BindToClose`):** xóa `pending` của mọi trận đang dở, không đổi điểm.

Mọi bước là logic thuần trên bảng dữ liệu (`PvpRating.open`, `close`, `forfeit`, `void`, `settleStale`), test được bằng Lune. Giới hạn: server **sập cứng** giữa trận mà `pending` đã kịp tự lưu thì cả hai bị tính thua ở lần vào sau. Hiếm, và không phân biệt được với rút dây từ phía dữ liệu; ghi vào rủi ro.

### Dữ liệu người chơi (BV)

| Trường (trong `pvp`) | Dùng cho | Mặc định |
|---|---|---|
| `rating`, `peak` | Điểm hiện tại và cao nhất mùa này | 1000, 1000 |
| `games`, `wins`, `losses`, `draws` | Tổng từ trước tới nay (ván ranked có tính điểm) | 0 |
| `season`, `seasonGames` | Mã mùa của các số trên, số ván mùa này | `""`, 0 |
| `pending` | Trận ranked đang dở (xem trên) | `false` |
| `lastSeason` | `{ id, rating, peak, games, tier }` của mùa vừa xong | `false` |
| `medals` | Huy chương theo mùa: `{ ["2026M12"] = { tier, top? } }` | `{}` |

- `Reconcile` tự điền bảng lồng nhau, nên version vẫn là 3 (có test).
- **Không lưu UserId của đối thủ, không lưu lịch sử trận** (cùng nguyên tắc với Coop). Xóa một người không để lại dấu vết của họ trong dữ liệu người khác.

### Mùa và hạng (BS, BT)

- **Mùa = tháng dương lịch theo UTC**, mã `2026M12`. Không cần cấu hình hay lịch hẹn giờ: `Seasons.id(time)` tính từ đồng hồ.
- **Chuyển mùa lười:** khi dữ liệu của người chơi mang mã mùa cũ (lúc vào game hoặc trước trận ranked đầu của mùa mới), `PvpRating.rollSeason` chép số liệu sang `lastSeason`, cấp huy chương theo hạng cao nhất đã đạt, rồi **kéo điểm về giữa:** `rating = 1000 + (rating − 1000) / 2`, `seasonGames = 0`, `peak = rating`.
- **Hạng** theo điểm: Bronze dưới 1000, Silver 1000, Gold 1200, Platinum 1400, Diamond 1600, Master 1800.

### Test

- **Lune:**
  - `Elo`: hai người bằng điểm (±K/2), chênh 400 điểm, ba mức K, làm tròn, sàn 100, thắng cộng với thua của đối thủ bằng 0 khi cùng K.
  - `PvpRating`: mở và chốt trận cho thắng, hòa, thua; xử thua; hủy; `pending` cũ ở lần vào sau; chốt hai lần không cộng đôi; trận không tính điểm không đổi gì; đếm ván và `peak`.
  - `Seasons`: mã mùa quanh ranh giới tháng và năm theo UTC; chuyển mùa một lần và chỉ một lần; kéo điểm về giữa; ngưỡng hạng; huy chương.
  - `PlayerData`: bảng mẫu có `pvp`, version vẫn 3.
- **Studio:** profile cũ nạp lên có `pvp` đúng mặc định (`data`); `DataService.beforeRelease` được gọi trước khi phiên kết thúc (dừng Play giữa một trận giả, vào lại, đọc `data`). Kiểm lại API hiện hành của ProfileStore cho lần lưu cuối khi phiên bị server khác lấy.
- **Hai người thật:** không có gì ở mốc này.

### Kết quả M25

Đã cài: `src/server/Elo.luau`, `Seasons.luau`, `PvpRating.luau`, `Config.PVP.RATING` và `Config.PVP.TIERS`, trường `pvp` trong `PlayerData` (version vẫn 3), `DataService.beforeRelease`, và lệnh debug `data` in thêm phần `pvp`. Test: `Elo.spec`, `Seasons.spec`, `PvpRating.spec`, cộng test mới trong `PlayerData.spec`. 373 test pass.

- **Sửa một test cũ:** test "starts new players at zero" của `PlayerData` so nguyên bảng mẫu, nên phải thêm `pvp` vào đó. Đây là test duy nhất trong số 309 test cũ phải sửa; M22 cũng sửa test này khi thêm trường Co-op.
- **Cấu hình truyền vào:** `Elo.new(settings)` và `PvpRating.new(settings, tiers)` nhận `Config.PVP.RATING` và `Config.PVP.TIERS` qua tham số, như `Rooms.new(deps)`. Code server và shared nằm ở hai chỗ khác nhau trong DataModel.
- **Chi tiết mình tự chọn (đổi được trong `Config.PVP.RATING`):**
  - Huy chương mùa cần ít nhất `MEDAL_MIN_GAMES = 1` ván ranked trong mùa.
  - `lastSeason` vẫn được ghi khi mùa đó không có ván nào.
  - Người nghỉ nhiều tháng chỉ bị kéo điểm về giữa một lần.
  - Mã mùa cũ hơn mùa trong dữ liệu (đồng hồ server khác chạy chậm) thì bỏ qua.
  - Làm tròn nửa ra xa số 0, nên khi cùng K thì điểm người thắng nhận đúng bằng điểm người thua mất.
- **Chưa nối:** chưa có chỗ nào gọi `settleStale`, `rollSeason` lúc vào game hay `beforeRelease`. Các lời gọi này thuộc `PvpService` ở M26/M27.
- **Studio:** chưa chạy, vì lúc làm không có Studio nào kết nối MCP. Còn nợ hai bước: kiểm `data` in ra `pvp` mặc định với một profile cũ, và đọc lại API hiện hành của ProfileStore cho lần lưu cuối khi phiên bị server khác lấy.

## M26: Ván PVP giao hữu

### Giao thức

```
Client A                                Server (PvpService → PvpMatches)                      Client B
  │ (phòng "pvp" lập xong)                trận mới, seed bí mật, startAt = bây giờ + 3 giây
  │ ◀── PvpEvent("start", state) ───────  matchId, loại trận, chỗ, startAt, endAt, snapshot ──────▶ │
  │
  │ đặt khối trên bản dự đoán
  │ PvpPlace(matchId, moveIndex, slot, x, y) ─▶ tần suất → kiểu → trong giờ? → khóa khay? → vừa?
  │ ◀── PvpEvent("result", matchId, moveIndex, score, sent, pending, refill?, stuck?)
  │         refill = { garbage = { {side, hole} }, set = { id, id, id } }   (sau khối thứ 3)
  │         stuck  = { set, lockedUntil }                                   (hết nước)
  │                                         đòn sang B: hàng chờ rác của B đổi
  │                                       ── PvpEvent("incoming", matchId, pending) ──────────────▶ │
  │                                       ── PvpOpponentBoard(buffer) ── (không tin cậy) ─────────▶ │
  │ PvpRotate(matchId, moveIndex, slot) ──▶ như solo
  │ PvpRequestState() ───────────────────▶ thấy lệch (điểm khác, moveIndex nhảy cóc, quá 2 giây chưa có kết quả)
  │ ◀── PvpEvent("state", state)
  │ PvpForfeit(matchId) hoặc rời server ──▶ xử thua
  │ ◀── PvpEvent("end", matchId, outcome, scores, reason, rating?) ───────────────────────────────▶ │
```

- **Client chỉ gửi ý định** (ô nào, khối nào). Điểm, đòn, rác, bộ khối, giờ, kết quả đều do server tính. Client so điểm của bản mình với `score` trong `result`; lệch thì xin lại trạng thái, như solo.
- **`pending` là danh sách hướng** (1 đáy, 2 trái, 3 phải), hàng sắp vào nhất đứng đầu, tối đa 4 phần tử. Nó đi trong `result` và `incoming` của chính nạn nhân. Bảng của đối thủ (`PvpOpponentBoard`) chỉ mang **số** rác chờ, không mang hướng.
- **`moveIndex` như solo** (số nước của chính người đó): nước cũ bị bỏ, nước nhảy cóc thì trả trạng thái đầy đủ.
- **Một remote cho mọi tin có thứ tự** (`PvpEvent`), theo bài học M23.
- **Bảng của đối thủ (BW):** `PvpOpponentBoard` là `UnreliableRemoteEvent` mang một `buffer` 39 byte: 32 byte màu của 64 ô (4 bit mỗi ô: trống, 8 màu khối, rác), điểm, rác chờ, số thứ tự. Gửi sau mỗi nước được nhận của đối thủ và nhắc lại mỗi giây để tin rơi tự lành; client chỉ giữ tin có số thứ tự mới nhất. **Không gửi khay và mã khối của đối thủ.**
- **Giới hạn tần suất** theo từng người: đặt 8 lần/giây, xoay 12 lần/giây, xin trạng thái 2 lần/giây, bỏ cuộc 1 lần/2 giây.
- **Đồng hồ:** `PvpMatches.sweep(now)` chạy mỗi 0,1 giây, kết thúc các trận quá `endAt + grace`. Đồng hồ nội bộ là `os.clock`, đổi sang giờ server khi gửi client (như `RoomService` làm với hạn lời mời).

### Server

- `PvpMatches` (thuần): `start(room, kind)`, `place`, `rotate`, `state`, `forfeit`, `sweep`, `rematch`, `close`, `remove`, `summary`, `peek`, `footprint`.
- `Rooms`: `MODES` thêm `pvp`; `form(a, b, mode)` lập phòng trực tiếp (dùng lại `formRoom`, vẫn rút mọi lời mời đang mở của hai người). `CoopInvite(targetUserId, mode)` với `mode` là số 1 (coop) hoặc 2 (pvp), kiểm ở server.
- `CoopService` bỏ qua phòng không phải `"coop"`; `PvpService` bỏ qua phòng không phải `"pvp"`. Có test.
- Người rời phòng (`memberLeft`) khi trận chưa xong thì xử thua; trận xong rồi thì chỉ là rời phòng.

### Client

- `PvpRunController` là một `Source`: `session()`, `canDrag` (sai khi khóa khay, trước `startAt`, sau `endAt`), `tryPlace`, `tryRotate`, `statusText`, `gameOver`, `leave`.
- **Bố cục màn ngang (theo `07-match-playing`):** bảng của mình bên trái. Cột phải từ trên xuống: thẻ HUD (nút Pause, SCORE, TIME), thẻ đối thủ (vòng tròn màu, tên, biểu tượng hạng, điểm trận, bảng nhỏ có màu, cột IN của đối thủ), khay 3 ô nằm ngang, dòng trạng thái ("Rotate: 1 free (this match)", "+1 garbage from Mia", "Tray unlocks in 5"). Cột **IN** của mình (4 nấc, đầy từ dưới lên, nấc dưới cùng là hàng sắp vào nhất) nằm sát mép trái dưới của bảng; **mỗi nấc có mũi tên nhỏ chỉ hướng** của hàng rác đó (CB). Cột IN trên thẻ đối thủ chỉ là ô xám, không có hướng.
- **Màn dọc và điện thoại ngang thấp:** chưa có mockup; dựng cùng thành phần, bố cục chốt khi có mockup hoặc sau lượt thử đầu.
- **Hiệu ứng:** hàng rác trượt vào từ đúng hướng và cả bảng trượt theo (khoảng 0,25 giây, trong lúc chờ bộ mới); **mũi tên ở mép bảng** hiện ngay khi có rác chờ, đứng ở phía mà hàng sắp vào nhất sẽ vào, và nháy lúc rác vào; ô rác màu xám; khay mờ kèm vòng đếm khi bị khóa; thẻ "Stuck! Board cleared".
- Đếm ngược 3-2-1 "Get ready!" trên bảng; màn VS 3 giây; màn kết quả. Chi tiết theo bảng mockup.
- Màn Co-op có thêm nút **Duel** cạnh **Invite** (lời mời giao hữu); thẻ mời ghi "invites you to a Duel".
- Theo mockup PC (BX); phần chưa có mockup dựng cùng phong cách bằng `Theme`/`Clay`.

### Debug (chỉ Studio)

- Server: `pvpbot [nước/giây]` ghép người chơi với đối thủ giả (đặt nước tham lam, có thể bảo nó `afk`, `leave`, `stuck`); `pvp` in trận của từng người; `pvp garbage <n>` nhét rác vào hàng chờ của mình; `pvp end` kết thúc trận ngay.
- Client: `pvp` in bản dự đoán và `moveIndex`.

### Test

- **Lune:**
  - `PvpMatches`: tham số rác (nil, chuỗi, NaN, ±inf, bảng, số quá lớn), nước trước `startAt`, nước sau `endAt` trong và ngoài khoảng gia hạn, nước trong lúc khóa khay, `moveIndex` cũ và nhảy cóc, sai `matchId`, giới hạn tần suất, đòn của A vào hàng chờ của B và được triệt tiêu, hết giờ với thắng và hòa, bỏ cuộc, rời server ở từng trạng thái, đấu lại cần cả hai, `footprint() == 0` sau khi mọi người rời.
  - `Rooms`: phòng `"pvp"`, `form` trực tiếp, mode lạ bị từ chối; test cũ không sửa.
  - `PvpSync`: nước của mình hiện ngay; kết quả có rác và bộ khối; hết nước; điểm lệch thì xin trạng thái.
  - **Lockstep PVP:** 200 trận, hai client giả và server thật, mọi tin trễ ngẫu nhiên 0–6 nhịp nhưng đúng thứ tự, có rác, hết nước, bỏ cuộc và hết giờ. Khi mọi tin đã tới: hai client và server giống hệt nhau, 0 lần phải xin lại trạng thái.
  - Mã hóa `buffer` của bảng đối thủ đi và về.
- **Studio, một client với `pvpbot`:** trọn một trận 3 phút; rác vào từ cả ba hướng; triệt tiêu thấy trên thanh; hết nước và khóa khay; hết giờ khi đang kéo khối; Leave giữa trận (thua); kết quả thắng, thua, hòa (`pvp end`); dữ liệu rác lên từng remote không sinh lỗi ở Output; solo và Coop vẫn chạy (chạy lại nhanh M6 và một ván `coopbot`).
- **Hai người thật (sau khi publish, chỉ liệt kê):** mời Duel, nhận, từ chối; chơi trọn trận, mỗi bên thấy bảng nhỏ của bên kia đổi theo; gửi và nhận rác; một bên đóng app giữa trận (bên kia thắng ngay); một bên bật giả lập mạng chậm (đồng hồ hai máy lệch nhau bao nhiêu, nước cuối sát giờ); điện thoại dọc và ngang, tay cầm; đấu lại.

### Tiến độ M26

**Phần logic (đã làm; UI chờ cổng kiểm BY vì lúc làm không có Studio nào kết nối MCP):**

- `src/server/PvpMatches.luau`: đủ các hàm `start`, `place`, `rotate`, `state`, `peek`, `board`, `opponentOf`, `forfeit`, `sweep`, `cancelAll`, `rematch`, `leave`, `remove`, `summary`, `footprint`.
  - Nước tới sau `endAt + END_GRACE_SECONDS` bị bỏ (`ignored "too late"`).
  - Nước trong lúc đếm ngược hoặc lúc khóa khay thì server trả trạng thái (`resync`).
  - Trận đã xong vẫn giữ lại cho màn kết quả và đấu lại, tới khi cả hai rời.
- `Rooms`:
  - Thêm mode `"pvp"`.
  - Thêm `Rooms.form(a, b, mode)` để lập phòng không qua lời mời; sự kiện `formed` khi đó có `inviteId = nil`. `RoomService` và `CoopService` đã chặn trường hợp `nil` này.
  - Lời mời mang theo `mode`.
  - Hai người mời nhau thì chỉ tự nhận lời khi cùng loại phòng.
- `src/shared/PvpBoardCodec.luau`: bảng đối thủ 39 byte. Số phiên bản là u16 (chạy vòng), client chỉ giữ tin mới nhất.
- `src/client/Util/PvpSync.luau`: bản dự đoán phía client và luật xin lại trạng thái. Tin `result` mang thêm `sent` và `cancelled` của server: client có thể đã dự đoán nước đi trên hàng chờ rác cũ, khi tin `incoming` còn đang trên đường. Bảng và điểm không bị ảnh hưởng, chỉ tổng "đã gửi/đã đỡ" cần sửa theo server.
- `Config.PVP` thêm `COUNTDOWN_SECONDS = 3` và `OPPONENT_BOARD_RESEND_SECONDS = 1`.
- Test:
  - Spec mới: `PvpMatches.spec`, `PvpSync.spec`, `PvpBoardCodec.spec`, `PvpLockstep.spec`, cộng test mode `"pvp"` trong `Rooms.spec`. 415 test pass.
  - Lockstep: 200 trận, 32 791 nước, 4 707 lần hết nước, 837 hàng rác, 20 trận bỏ cuộc. 0 lần lệch, 0 lần xin lại trạng thái.
- **Sửa một test cũ:** `Rooms.spec` từng khẳng định mode `"pvp"` bị từ chối; dòng đó nay thử một mode lạ (`"duel"`).

**Cổng kiểm BY (2026-11-17, Studio qua MCP, một client, PC):** đạt.

| Phần kiểm | Kết quả |
|---|---|
| Menu, Play, kéo thả chuột, xoay, game over, revive (`fakepurchase`), tutorial | Đạt |
| Màn Co-op, danh sách, thẻ mời, ván Co-op với `coopbot`, Game Over Co-op, thanh EXP, tab Co-op | Đạt |
| Cảm ứng, màn dọc | Bỏ qua: bản này làm cho PC trước |

Ba lỗi hiển thị của GĐ5 đã sửa:
- Thẻ mời che nút X của màn Co-op: khi màn Co-op mở, thẻ dời sang góc trên bên phải.
- Thanh cuộn luôn hiện, và bóng nút "Invite friends" bị cắt: chiều cao thẻ Co-op giờ đo phần khung thật thay vì cộng số cố định.

Ảnh: `production/qa/evidence/gate-BY/` (thư mục bị gitignore, chỉ có trên máy).

**Phần UI và server (đã làm):**

- **Server:**
  - `PvpService`: trận bắt đầu khi lập phòng `"pvp"`; rời phòng hoặc rời server khi trận đang chạy thì thua.
  - Play again cần cả hai người; `BindToClose` hủy các trận đang chạy.
  - Bảng đối thủ gửi sau mỗi thay đổi và nhắc lại mỗi giây.
  - Bot luyện tập (`pvpbot`) đi nước tham lam.
  - Lời mời Duel đi qua `CoopInvite(target, 2)`; `CoopInvited` mang thêm mode.
- **Client:**
  - `PvpRunController` là một `Source` của `GameController`, có cờ `isMatch`: không có Game Over, không bán lượt xoay, Pause mở Resume và Forfeit.
  - `PvpView`: màn VS, đếm ngược, cột IN có mũi tên hướng, mũi tên ở mép bảng, hiệu ứng đẩy bảng, thẻ "Stuck", khóa khay có vòng đếm, màn kết quả.
  - `OpponentBoardView`: thẻ đối thủ.
  - `Gui` có biến thể bố cục `"match"`; `HudBar` có ô TIME.
  - Màn Co-op có nút Duel; thẻ mời ghi "invites you to a Duel".
- **Config:** `COUNTDOWN_SECONDS` đổi từ 3 lên 6, để chứa màn VS 3 giây (`VS_SECONDS`) rồi tới 3-2-1.
- **Debug (chỉ Studio):**
  - Server: `pvpbot`, `pvp`, `pvp nil <n> garbage`, `pvp nil nil cornered` (đặt bảng còn một nước, rồi đi tiếp theo đường thật tới lúc kẹt), `pvp nil nil end`.
  - Client: `pvp [again|menu]`.
- **Thử trong Studio với `pvpbot`, một client:**
  - Đã thấy chạy: màn VS, đếm ngược, đồng hồ, bảng đối thủ đổi theo, rác chờ và rác vào từ trái.
  - Đã thấy chạy: hết nước rồi khóa khay 5 giây, Pause rồi Forfeit, màn kết quả, Play again quay lại màn VS, Menu về menu, nút Duel.
  - Không có lỗi trong Output.
  - Ảnh: `production/qa/evidence/m26-pvp/` (8 ảnh, đặt cạnh mockup).
- **Lỗi tìm thấy khi thử và đã sửa:**
  - Cột IN trên thẻ đối thủ bị co lại; bảng nhỏ chừa khoảng trống.
  - Đồng hồ vẫn chạy sau khi hết trận.
  - Phiếu đấu lại có thể bị xóa nếu tới trước màn kết quả.

**Còn lại:**
- Thử với hai người thật (danh sách ở mục Test): lời mời Duel, trận thật, mạng chậm.
- Analytics của trận (để M28, cùng các sự kiện PVP khác).
- Thẻ VS và thẻ đối thủ hiện level thay vì hạng: hạng và huy hiệu đến ở M27/M28.

## M27: Hàng chờ ranked trong server

### Ghép cặp (BQ)

- `Matchmaker` (thuần, đồng hồ truyền vào): `enqueue(player, rating)`, `cancel`, `remove`, `tick() → { cặp }`, `footprint`.
- **Cửa sổ điểm nới dần:** mỗi người chấp nhận chênh lệch `100 + 20 × số giây đã chờ`, tối đa **400**. Hai người ghép được khi chênh lệch nằm trong cửa sổ của **cả hai**. Ưu tiên cặp chưa gặp nhau gần đây, rồi tới người chờ lâu nhất.
- Ghép xong: `Rooms.form(a, b, "pvp")`, trận loại `ranked` bắt đầu sau màn VS 3 giây. Không có bước "Accept" trong bản đầu.
- **Remote:** `PvpQueue(join: boolean)` (1 lần/giây), `PvpQueueState(state)` server gửi: đang chờ từ lúc nào, bao nhiêu người đủ điều kiện trong server, đã ghép.
- **Giao diện:** nút **Ranked** trên menu (`06`), màn hàng chờ (`08`, `09`), màn VS (`14`), kết quả có ô đổi điểm rank (`11`).

### Điều kiện vào hàng chờ và chống cày điểm (BO, BP)

| Luật | Chặn cái gì |
|---|---|
| Ranked **chỉ** qua hàng chờ; lời mời luôn là giao hữu | Hai người hẹn nhau cày |
| Tắt ranked trong private server (`game.PrivateServerOwnerId ~= 0`) | Thuê server riêng để tự ghép với nick phụ |
| Xong tutorial và level ≥ `PVP.MIN_LEVEL` (3) | Nick phụ tạo hàng loạt |
| Một cặp chỉ có **2 trận tính điểm trong 24 giờ**; trận thứ 3 vẫn chơi được nhưng báo trước là "Unrated" | Cày lặp với một nick phụ |
| Cửa sổ tối đa 400 điểm, cộng tính chất của ELO (thắng người thấp hơn nhiều gần như không được gì) | Nick phụ điểm thấp nuôi nick chính |
| Rời trận = thua đủ; ghi trước khoản thua (M25) | Rút dây khi sắp thua |
| Cần ≥ `RANK_MIN_GAMES` ván trong mùa mới lên bảng (M28) | Một hai trận may mắn lên top |

- **Đếm cặp** nằm trong `MemoryStoreHashMap` `PvpPairs`, khóa `"<id nhỏ>_<id lớn>"`, hết hạn sau 24 giờ, nên có hiệu lực cả khi hai người đổi server. MemoryStore lỗi thì dùng bộ đếm trong server và ghi một sự kiện analytics.
- **Không tự động cấm ai.** Dấu hiệu lạ (cặp lặp lại, nhịp đặt khối đều bất thường, chuỗi thắng do đối thủ bỏ cuộc sớm) chỉ ghi analytics để xem lại bằng tay.
- **Không chặn được:** một người cầm hai thiết bị vẫn đưa được 2 trận tính điểm mỗi nick phụ mỗi ngày, mỗi trận đáng ít dần theo ELO. Bot giải bài chạy trên máy người chơi cũng không phát hiện được từ server. Chấp nhận ở bản đầu.

### Khi hàng chờ vắng (BR)

- Màn hàng chờ ghi số người đủ điều kiện đang ở server và thời gian đã chờ.
- Sau `PVP.QUEUE_OFFER_SECONDS` (20) giây chưa có ai: hiện ba nút, vẫn tiếp tục chờ ở nền: **Keep waiting**, **Practice vs bot** (không tính rank, màn VS ghi rõ "Practice bot"), **Invite friends** (`SocialService:PromptGameInvite`, như màn Co-op).
- Không bao giờ cho bot đóng giả người và không tính ELO với bot.

### Test

- **Lune:** `Matchmaker` (cửa sổ nới theo đồng hồ giả, chọn cặp gần nhất, cần cửa sổ của cả hai, tránh đối thủ vừa gặp, rút khỏi hàng, rời server, không tự ghép với mình, một bài ngẫu nhiên 300 thao tác kiểm bất biến rồi `footprint() == 0`); luật cặp 2 trận/24 giờ với kho giả và đồng hồ giả, kể cả khi kho lỗi; điều kiện vào hàng chờ; `PvpService` chốt điểm đúng cho từng loại trận (ranked, unrated, friendly, bot) với `PvpRating`.
- **Studio, một client:** vào hàng chờ một mình, sau 20 giây thấy ba nút; `pvpbot queue [điểm]` cho một người giả vào hàng chờ để thử ghép, màn VS và chốt điểm (chỉ trong Studio mới cho bot tính điểm); dừng Play giữa trận ranked rồi vào lại, `data` cho thấy đã bị trừ điểm; đếm cặp ghi và đọc được từ MemoryStore của Studio; ranked tắt khi giả lập private server.
- **Hai người thật (sau khi publish, chỉ liệt kê):** hai tài khoản cùng server vào hàng chờ và được ghép; điểm hai bên đổi đúng sau trận; trận thứ 3 trong ngày của cùng cặp báo "Unrated" và không đổi điểm; một bên rời giữa trận rồi vào lại thấy bị trừ; vào game bằng thiết bị thứ hai giữa trận (cướp phiên) rồi kiểm điểm; private server không có nút Ranked; tài khoản mới dưới level 3 thấy lý do bị khóa.

### Kết quả M27

**Đã làm:**
- **Logic thuần:**
  - `Matchmaker`: cửa sổ điểm nới dần; ưu tiên người chưa gặp trong 10 phút, rồi người chờ lâu nhất.
  - `PairLimits`: một cặp tối đa 2 trận tính điểm mỗi 24 giờ. Đếm trong MemoryStore `PvpPairs`; MemoryStore lỗi thì đếm trong server và ghi cảnh báo.
  - `RankedRules`: điều kiện vào hàng chờ, và chốt hoặc hủy điểm khi trận kết thúc.
  - Test: `Matchmaker.spec` (gồm bài ngẫu nhiên 300 thao tác), `PairLimits.spec` (gồm lúc kho lỗi), `RankedRules.spec`. 432 test pass.
- **Server (`PvpService`):**
  - Hàng chờ (`PvpQueue`, `PvpQueueState`). Người đang chờ có `CoopBusy = "queue"` và không mời được.
  - Phòng ranked lập bằng `Rooms.form` (không qua lời mời).
  - Trận tính điểm: ghi trước khoản thua lúc bắt đầu. Khi kết thúc: chốt điểm, gửi điểm trước và sau, gửi lại profile.
  - Rời trận bị xử thua trước khi dữ liệu được giải phóng (`DataService.beforeRelease`).
  - Lúc vào game: `settleStale` và chuyển mùa.
  - Tắt server có báo trước: hủy trận, không ai đổi điểm.
  - Practice vs bot không còn giới hạn trong Studio (`PvpPractice`).
  - Server ghi attribute `RankedOpen` lên `ReplicatedStorage`: client không đọc được `PrivateServerOwnerId`.
  - Profile gửi client có thêm `rank`.
  - Debug: `pvpbot nil <điểm> queue`.
- **Client:**
  - Nút Ranked trên menu (`06`).
  - Màn hàng chờ `QueueView`/`QueueController` (`08`, `09`); khi bị chặn thì ghi lý do.
  - Màn VS ranked có huy hiệu hạng và điểm (`14`).
  - Màn kết quả có ô đổi điểm và nút "Queue again" (`11`).
  - Huy hiệu hạng tạm vẽ bằng UI (`RankBadge`), chờ ảnh thật ở M28.
  - Debug: `queue [open|keep|practice|close]`.

**Thử trong Studio (một client):**
- Đã thấy chạy:
  - Menu có nút Ranked.
  - Bị chặn khi dưới level 3 và hiện đúng lý do.
  - Màn hàng chờ, và sau 20 giây hiện 3 lựa chọn.
  - Bot ghép được vào trận ranked; `pending` đúng công thức (+23/+3/−17 khi 1000 gặp 1050, K 40).
  - Thua thì điểm đổi 1000 → 983; dữ liệu ghi 1 trận thua; `pending` đã xóa.
  - Queue again quay lại hàng chờ; Practice vs bot mở trận loại bot.
  - MemoryStore của Studio đọc và ghi được.
  - `data` in đúng phần `pvp` (xong bước Studio còn nợ của M25).
- Ảnh: `production/qa/evidence/m27-ranked/` (6 ảnh).
- **Lỗi tìm thấy khi thử và đã sửa:**
  - Client đọc `PrivateServerOwnerId` (Roblox chỉ cho đọc ở server).
  - Ô đổi điểm ghi hạng mới cạnh điểm cũ khi rớt hạng.
- **Chưa thử được với một client:**
  - Rời trận ranked rồi vào lại (dừng Play trong Studio là tắt server, nên trận bị hủy chứ không xử thua).
  - Trận thứ 3 trong ngày của cùng một cặp ("Unrated"), vì mỗi bot có UserId mới.
  - Private server.

  Các phần này nằm trong danh sách "Hai người thật".

**Chưa bật cho người chơi:** `PVP.ENABLED` vẫn `false`. Ngoài Studio chưa có PVP nào chạy. Bật sau lượt thử hai người thật của GĐ5 và GĐ6 (lời mời, phòng, trận Duel, ranked).

## M28: Bảng Rank, mùa, quà, dữ liệu, analytics

### Bảng Rank (BU)

- `OrderedDataStore` **`Rank_<mùa>`** (`Rank_2026M12`, thêm `_Dev` trong Studio), khóa là UserId, giá trị `Leaderboards.encode(rating, titleIndex)` như các bảng khác.
- **Ghi** sau mỗi trận tính điểm (cách nhau ít nhất 20 giây, và ở vòng đọc mỗi phút nếu còn thay đổi), chỉ khi `seasonGames ≥ PVP.RANK_MIN_GAMES` (5). Điểm có thể giảm nên dùng `SetAsync` như bảng Highscore, không phải `UpdateAsync` lấy giá trị lớn hơn như bảng Coop.
- **Đọc** top 50 trong vòng đọc mỗi phút hiện có (thêm một lần `GetSortedAsync`).
- **Giao diện (theo `05-leaderboard-rank-tab`):** tab thứ tư **Rank** cùng hàng với Highscore, Level, Co-op. Chọn Rank thì dòng dưới tiêu đề ghi "Season 2026M12 · ends Dec 31" thay cho hai tab thời gian. Mỗi dòng: thứ hạng (top 3 là huy hiệu vàng, bạc, đồng), biểu tượng hạng, tên, **tên hạng bên dưới tên** (CA), điểm. Ô cuối "You: Gold · 1,320 · 14W 9L". Người ngoài top 50 chỉ thấy hạng và điểm của mình (`OrderedDataStore` không tra được thứ hạng của một khóa).

### Quà theo mùa (BT)

- **Huy chương mùa** theo hạng cao nhất đã đạt trong mùa, cấp lúc chuyển mùa, lưu trong `pvp.medals`, hiện ở màn Rank.
- **Top 10 cuối mùa:** store của mùa cũ không còn ai ghi, nên bất kỳ server nào cũng đọc được top 10 chung cuộc. Mỗi server đọc một lần (sau ranh giới mùa ít nhất 10 phút, để các lần ghi trễ kịp tới), nhớ lại, và cấp huy chương "Top 10" hoặc "Champion" cho người có tên khi họ vào game. Không cần tác vụ hẹn giờ.
- **Badge Roblox** cho lần đầu đạt Gold, Diamond, Master (vĩnh viễn), khi có badge ID; cùng tình trạng "chờ ID" như M13.
- Quà là cosmetic thì chờ GĐ4.

### Xóa dữ liệu theo yêu cầu

| Dữ liệu | Ở đâu | Cách xóa |
|---|---|---|
| `pvp` trong profile | DataStore `PlayerData`, khóa `User_<id>` | Đã có (xóa cả profile) |
| Dòng bảng Rank | `Rank_<mùa>`, khóa `<id>`, mỗi mùa một store | `Erasure.orderedStoreNames` liệt kê thêm mọi mùa từ `FIRST_SEASON_TIME`, như đang làm với các tuần |
| Hàng chờ (M27) | Bộ nhớ server | Mất khi người chơi bị đưa ra khỏi server ở bước 1 của script |
| Đếm cặp `PvpPairs` | MemoryStore, khóa theo cặp | **Tự hết hạn trong 24 giờ.** Script không quét; ghi rõ trong phần chú thích đầu script |
| Lịch sử trận, id đối thủ | Không lưu | Không có gì để xóa |

Mỗi mùa thêm một store vào danh sách xóa (12 store mỗi năm), ít hơn nhiều so với bảng tuần.

### Analytics

- **Funnel `PvpQueue`** (phiên là id vé hàng chờ): 1 Queued, 2 Matched, 3 Started, 4 Finished.
- **Sự kiện** (giá trị số, tối đa ba trường phân loại ít giá trị):

| Sự kiện | Giá trị | Trường |
|---|---|---|
| `PvpQueueWait` | Số giây chờ | `matched`, `cancelled`, `bot`, `left` |
| `PvpMatchScore` | Điểm của người chơi | loại trận; `win`, `loss`, `draw` |
| `PvpMargin` | Chênh lệch điểm hai bên | loại trận |
| `PvpEnd` | 1 | `time`, `forfeit`, `disconnect`, `void` |
| `PvpGarbageSent`, `PvpGarbageCancelled`, `PvpGarbageTaken` | Số hàng trong trận | loại trận |
| `PvpStuck` | Số lần hết nước trong trận | loại trận |
| `PvpPendingAtEnd` | Rác còn chờ lúc hết giờ | loại trận |
| `PvpRatingGap` | Chênh lệch điểm rank lúc ghép | |
| `PvpUnratedPair` | 1 | |
| `PvpSeasonTier` | 1, lúc chuyển mùa | hạng |

- `RunScore`, `RunMoves`, `RunMaxCombo` thêm loại ván `pvp`; ván solo bỏ để vào PVP ghi cách kết thúc `pvp`.
- Không đưa UserId hay tên vào trường nào.

### Kiếm tiền trong PVP (BK)

- **Không bán gì ảnh hưởng tới kết quả:** không hồi sinh trả tiền, lượt xoay đã mua không dùng được, không mua lượt đấu. Không mở hộp thoại mua nào trong trận.
- Về sau (GĐ4): cosmetic hiện trong trận (skin khối, theme bảng, hiệu ứng), không thuộc giai đoạn này.

### Test

- **Lune:** `Leaderboards` (tên store theo mùa, chỉ ghi khi đủ số ván, mã hóa điểm rank); `Erasure` (danh sách store có mọi mùa từ mùa đầu, không trùng, danh sách cũ không đổi thứ tự); `Seasons` (top 10 từ bảng giả, người không có tên không được gì, cấp một lần); `Telemetry` (funnel và từng sự kiện mới, trường đúng).
- **Studio:** chơi trận ranked với `pvpbot queue` rồi `boards` đọc lại từ `Rank_<mùa>_Dev`; tab Rank; lệnh debug `season +1` (lệch đồng hồ truyền vào) để thấy chuyển mùa, kéo điểm, huy chương; `lune run scripts/erase-user.luau <id> --dry-run` in thêm các store `Rank_`.
- **Sau khi publish (chỉ liệt kê):** chạy `erase-user.luau` thật trên tài khoản thử đã chơi ranked và kiểm dòng Rank biến mất; xem funnel `PvpQueue` và các sự kiện trên Analytics; badge sau khi có ID; hai tài khoản thấy nhau trên tab Rank.

### Kết quả M28

**Đã làm:**
- **Bảng Rank:**
  - `Leaderboards` có bảng `Rank_season`, lưu ở store `Rank_<mùa>` (`_Dev` trong Studio).
  - Chỉ ghi khi đã có `RANK_MIN_GAMES` (5) ván trong mùa. Ghi sau mỗi trận tính điểm (cách nhau ít nhất 20 giây) và ở vòng đọc mỗi phút; mỗi phút đọc top 50.
  - Profile và snapshot bảng gửi client phần `you.rank`: điểm, thắng/thua/hòa, mùa, "ends Nov 30", huy chương.
- **Mùa thử (trả lời câu hỏi mở 7):** `RATING.REWARDS_FROM_SEASON = "2027M01"`. Các mùa trước đó vẫn có bảng Rank nhưng không cấp huy chương hay Top 10. **Khi bật PVP, đặt giá trị này là tháng kế tiếp tháng bật.**
- **Quà cuối mùa:**
  - Huy chương hạng cấp lúc chuyển mùa (như M25), trừ mùa thử.
  - Top 10 và Champion: mỗi server đọc top 10 chung cuộc của mùa vừa xong một lần, sau ranh giới mùa 10 phút (`LeaderboardService.finalTop`). Huy chương cấp cho người có tên khi họ vào game, hoặc ngay lúc đọc xong nếu họ đang ở server (`PvpRating.awardTop`, mỗi mùa một lần).
- **Badge:** `Config.PVP.TIER_BADGES` (Gold, Diamond, Master) trao qua `RewardService.awardBadge` khi lần đầu đạt hạng. Badge ID còn là 0, chờ bạn tạo trên Creator Hub.
- **Xóa dữ liệu:**
  - `Erasure.orderedStoreNames` liệt kê thêm `Rank_<mùa>` cho mọi mùa từ `FIRST_SEASON_TIME` (2026-11-01), xếp cuối danh sách để các store cũ giữ thứ tự.
  - `erase-user.luau` ghi chú rằng `PvpPairs` tự hết hạn.
  - Chạy thử `--dry-run` đã in ra `Rank_2026M11`.
- **Analytics:**
  - Funnel `PvpQueue` (Queued, Matched, Started, Finished).
  - Sự kiện: `PvpQueueWait` (`matched`, `cancelled`, `bot`, `left`); `PvpMatchScore`, `PvpMargin`, `PvpEnd`, `PvpGarbageSent`, `PvpGarbageCancelled`, `PvpGarbageTaken`, `PvpStuck`, `PvpPendingAtEnd`; `PvpRatingGap`, `PvpUnratedPair`, `PvpSeasonTier`.
  - Ván solo bỏ dở để vào PVP ghi cách kết thúc `pvp`. Không có UserId hay tên trong trường nào.
- **Giao diện:** tab Rank (`05`) có dòng mùa, huy hiệu, tên hạng dưới tên người chơi (CA), ô "You: Gold · 1,320 · 14W 9L", dòng huy chương các mùa. Tab Rank chỉ hiện khi server bật `RankedOpen`.
- **Debug (Studio):**
  - `pvp nil <n> season` đẩy đồng hồ mùa lên n tháng rồi chuyển mùa cho người chơi.
  - `pvpbot queue` không cho hai bot vào hàng chờ cùng lúc. Lúc thử, hai bot đã ghép với nhau.
- **Test:** thêm test cho `Leaderboards`, `Erasure`, `Seasons`, `PvpRating` (mùa thử, Top 10) và `Telemetry`. 441 test pass.
- **Hai test cũ phải sửa vì luật mới:**
  - `Erasure.spec` đếm đúng số store, nay có thêm `Rank_2026M11`.
  - `PvpRating.spec` dùng mùa 2026M12, nay là mùa thử.

**Thử trong Studio:**
- 5 trận ranked với bot, rồi `boards` đọc lại `Rank_2026M11_Dev`.
- Tab Rank khớp mockup `05`.
- `pvp nil 1 season`: điểm kéo 989 → 994, ghi `lastSeason`, mùa thử không có huy chương.
- Analytics ghi đủ funnel và các sự kiện.
- Ảnh: `production/qa/evidence/m28-rank/`.

**Còn lại:**
- ~~Ảnh huy hiệu hạng~~ Đã làm:
  - Xuất 8 biến thể của `RankBadge` (81:6639) ở 256 px vào `assets/rank/`. Bridge bỏ qua tham số scale, nên xuất qua instance tạm phóng ×4, xuất xong thì xóa khỏi Figma.
  - Upload qua Studio MCP; ID nằm trong `Theme.Images.Rank*`. `RankBadge` giờ hiện ảnh.
  - Lúc upload, ảnh còn chờ Roblox kiểm duyệt nên trong Studio chỗ huy hiệu tạm trống; duyệt xong sẽ tự hiện.
- Badge ID cho Gold, Diamond, Master.
- Kiểm trên server thật sau khi publish (xem mục Test).

## M29: Ghép liên server (phác thảo)

Chỉ làm khi số liệu M27 và M28 cho thấy cần (ví dụ trung vị `PvpQueueWait` kết thúc bằng `bot` hoặc `cancelled` chiếm đa số trong khi tổng số người đang chơi đủ lớn). Có plan chi tiết riêng khi tới nơi. Hướng theo skill `roblox-teleport-matchmaking`:

1. Mỗi server đưa người đang chờ quá N giây vào `MemoryStoreSortedMap` `PvpQueue` (điểm rank, `JobId`, hết hạn 60–90 giây, làm mới định kỳ).
2. Một server tìm được cặp thì giành cả hai mục bằng `UpdateAsync` (không giành được thì bỏ), gọi `TeleportService:ReserveServerAsync(game.PlaceId)`, ghi thông tin trận vào MemoryStore theo `PrivateServerId` (hai UserId, loại trận), và ghi "vé" cho từng người.
3. Server của mỗi người thấy vé thì `TeleportAsync` người đó với `ReservedServerAccessCode`, có thử lại và nghe `TeleportInitFailed`.
4. Server trận (`game.PrivateServerId ~= ""` và `PrivateServerOwnerId == 0`) đọc thông tin trận từ MemoryStore, **không tin `TeleportData`**, chờ đủ hai người (quá 30 giây thì hủy trận), lấy điểm rank từ profile vừa nạp, chạy đúng `PvpMatches` của M26, chốt điểm, rồi đưa cả hai về server công khai.

- Dùng **cùng một place** làm server trận, nên repo không thêm place thứ hai.
- `Matchmaker`, `PvpMatches`, `PvpRating` không đổi; chỉ thêm lớp vận chuyển.
- **Test:** Lune với MemoryStore giả (giành mục khi hai server cùng ghép, mục hết hạn, vé). Teleport **không chạy trong Studio**, nên toàn bộ luồng thật chỉ kiểm được sau khi publish với hai tài khoản ở hai server.
- Lựa chọn nhẹ hơn cần xem trước: tùy chỉnh matchmaking của Roblox theo thuộc tính người chơi (đưa người gần điểm rank vào cùng server công khai), không cần teleport. Cần kiểm tài liệu xem thuộc tính đọc được từ trường lồng trong profile hay phải có khóa riêng.

## Bảo mật

- Mọi remote: giới hạn tần suất → kiểm kiểu từng tham số → kiểm luật → mới làm. Client chỉ gửi số (ô, khối, id trận, UserId), không gửi `Instance`, chữ tự do hay kết quả. Không có chữ do người chơi nhập nên không cần lọc văn bản.
- **Server giữ:** seed, luồng rác, đồng hồ, điểm, đòn, kết quả, điểm rank. Client không tính được bộ khối sắp tới của chính mình.
- **Giờ là giờ server.** Giữ gói tin lại (lag-switch) chỉ làm mất thời gian của chính mình; nước tới sau hạn không tính.
- **Rút dây, cướp phiên:** ghi trước khoản thua (M25).
- **Cày điểm và nick phụ:** bảng ở M27.
- **Câu rác:** không đặt khối thứ 3 để hoãn rác thì cũng không ghi được điểm; đo bằng `PvpPendingAtEnd`.
- **Bảng đối thủ** chỉ có màu ô và điểm, không có khay. Người chậm hơn vẫn suy ra được khối từ thay đổi trên bảng: câu hỏi mở số 2.
- **M29:** thông tin trận lấy từ MemoryStore theo `PrivateServerId`, không lấy từ `TeleportData`; người lạ vào server trận bị đưa ra.
- Không tự động cấm; chỉ ghi dấu hiệu.

## Rủi ro

| Rủi ro | Cách xử lý |
|---|---|
| Hàng rác 7/8 ô lại là hàng dễ ăn điểm, rác thành quà | Mô phỏng M24 đo trước khi làm giao diện; phương án đổi luật ở câu hỏi mở số 1 |
| Đẩy cả bảng làm người chơi rối, nhất là trên điện thoại | Chỉ áp ở ranh giới bộ, tối đa 1 hàng mỗi lần, có hiệu ứng trượt và thanh báo trước; xem lại sau lượt thử người thật |
| Hàng chờ vắng vì ít người cùng server | Bot luyện tập, mời bạn, số liệu `PvpQueueWait`; M29 nếu cần |
| Xây M26 trên giao diện Coop chưa kiểm | Cổng kiểm UI trước M26 (BY) |
| Sửa `Rooms`/`CoopService` làm hỏng Coop | Test `Rooms` và `CoopRuns` cũ pass không sửa; thêm test "phòng pvp không sinh ván Coop" |
| Server sập cứng giữa trận ranked: cả hai có thể bị tính thua | Hiếm; ghi nhận. Tắt có báo trước thì hủy trận |
| API ProfileStore cho lần lưu cuối khác với mình nhớ | "Ghi trước" không phụ thuộc API đó; kiểm tài liệu ở M25 |
| "Cùng nguồn khối" lộ khối cho người chậm hơn | Câu hỏi mở số 2 |
| Không thử được 2 client qua Studio MCP | `pvpbot`; phần cần hai người chỉ liệt kê, bạn thử sau khi publish |
| Không tắt nhanh được ranked nếu có lỗi nghiêm trọng | `Config.PVP.RANKED_ENABLED` cần publish và khởi động lại server; câu hỏi mở số 3 |
| Mỗi mùa thêm một store phải xóa | 12 store mỗi năm; cùng cách với bảng tuần |

## Bạn cần làm

1. Trả lời các câu hỏi mở (BG đến BZ đã duyệt). Không còn câu nào chặn M24; câu 2 chờ số liệu thật sau M26; không còn câu nào chặn M28.
2. Trước M26: cùng mình chạy lượt kiểm UI trong Studio (M6 solo, màn hình M19/M21/M22). Nếu Studio MCP kết nối được thì mình tự chạy phần một client.
3. Cho mình biết **số người tối đa mỗi server** đang đặt trong Creator Hub và số người chơi cùng lúc hiện tại (để ước lượng hàng chờ trong server có đủ người không).
4. Sau M26 và M27: thử với hai tài khoản thật trên hai thiết bị theo các danh sách "Hai người thật".
5. Khi có: badge ID cho Gold, Diamond, Master; mockup cho điện thoại (dọc và ngang) và các màn còn thiếu (xem [Chưa có mockup](#chưa-có-mockup)). Mockup PC đã nhận.

## Câu hỏi mở

1. ~~**Điểm khi xóa hàng có ô rác.**~~ Đã trả lời (quyết định CD): hàng quá nửa là ô rác thì không có điểm, combo hay đòn; cộng đòn combo từ combo 8. Số liệu ở [Kết quả M24](#kết-quả-m24).
2. **Rò khối sắp tới.** Vì hai người nhận cùng dãy khối, người đi chậm hơn có thể suy ra bộ sắp tới từ bảng của đối thủ. Lựa chọn: (a) chấp nhận ở bản đầu và đo; (b) bảng nhỏ chỉ hiện đối thủ "tại cùng số bộ với mình" (server giữ ảnh chụp theo từng bộ); (c) bỏ cùng nguồn khối, mỗi người một seed. Mình nghiêng về (a) rồi (b) nếu thấy bị lợi dụng.
3. ~~**ConfigService.**~~ Đã trả lời: giữ `Config.luau`, có thể chuyển sang ConfigService sau khi ranked chạy thật. Câu gốc: Skill analytics-liveops khuyên để cờ bật tắt và số liệu cần chỉnh nhanh trong experience config (đổi không cần publish). Plan hiện để mọi số trong `Config.luau`. Với ranked, một cờ tắt khẩn cấp và các số ELO chỉnh được live có giá trị thật. Bạn muốn dùng ConfigService cho `PVP.RANKED_ENABLED` và nhóm số ELO/hàng chờ ngay từ M27, hay giữ `Config.luau` như các giai đoạn trước?
4. ~~**Tuổi tài khoản tối thiểu**~~ Đã trả lời: không, chỉ cần level ≥ 3. Câu gốc: để vào ranked (`player.AccountAge`)? Chặn nick phụ tốt hơn level 3 nhưng cũng chặn người mới thật.
5. ~~**Danh hiệu rank cạnh tên.**~~ Đã trả lời bằng mockup `05`: tab Rank hiện tên hạng dưới tên người chơi, không hiện danh hiệu mốc (quyết định CA).
6. ~~**Hàng chờ chạy nền.**~~ Đã trả lời: không, người chơi ngồi ở màn hàng chờ như mockup `08`/`09`. Bản đầu người chơi ngồi ở màn hàng chờ. Có muốn cho chơi solo trong lúc chờ (ghép được thì hiện thẻ "Match found" như thẻ mời) không? Tốt cho lúc vắng, nhưng thêm một bước Accept và các ca hết hạn.
7. ~~**Mùa đầu tiên**~~ Đã trả lời: tháng bật PVP là mùa thử, không có quà; mùa có quà bắt đầu từ `RATING.REWARDS_FROM_SEASON`. Câu gốc: bắt đầu từ tháng nào, và có cần một "mùa thử" không tính quà để chỉnh số không?
8. ~~**Rác đẩy hay thay?**~~ Đã trả lời: **đẩy cả bảng**, đúng như BC. Mockup `04` (hàng rác thay hàng đáy, 7 hàng trên đứng yên) chỉ là minh họa; khi cài, cả bảng dịch một ô và hàng/cột ở mép đối diện mất.
9. ~~**Báo trước hướng rác?**~~ Đã trả lời: **có** (quyết định CB). Server rút hướng lúc rác vào hàng chờ và gửi cho nạn nhân; vị trí lỗ không báo trước.
10. ~~**Nút Pause trong trận.**~~ Đã trả lời (quyết định CC): bấm Pause mở bảng có **Resume** và **Forfeit**, đồng hồ vẫn chạy.
11. ~~**Menu trên điện thoại ngang thấp.**~~ Đã trả lời: để tới khi làm bản điện thoại; PC theo mockup `06`. Mockup `06` có ba hàng nút dưới Play (Ranked + Co-op, rồi Leaderboard). M19 đã gộp Co-op với Leaderboard vào một hàng để vừa màn thấp. Trên điện thoại: thu nhỏ nút, hay xếp Ranked, Co-op, Leaderboard thành một hàng ba nút? Cần trước M27.

## Quyết định đã chốt

BB đến BF chốt khi hỏi luật; BG đến BZ là đề xuất của mình, bạn duyệt cả loạt sau khi đọc plan.

| Điểm | Câu hỏi | Quyết định |
|---|---|---|
| **BB.** Luật PVP (câu hỏi mở số 6 của PLAN) | Đua điểm, tấn công rác, hay lai? | ✅ **Chốt:** lai. Đua điểm có đồng hồ, cùng nguồn khối, kèm rác nhẹ. |
| **BC.** Dạng rác | Rác trông thế nào trên bảng không trọng lực? | ✅ **Chốt:** hàng rác đẩy vào từ đáy (kiểu Tetris), từ trái hoặc từ phải; mỗi hàng rác rút ngẫu nhiên 1 trong 3 hướng. Xác nhận lại sau khi có mockup: đẩy cả bảng, không phải thay hàng ở mép. |
| **BD.** Hết nước trước giờ | Chốt điểm, dọn bảng, hay thua ngay? | ✅ **Chốt:** dọn 4×4 giữa bảng, chia bộ mới, mất combo, khóa khay vài giây. |
| **BE.** Thời lượng | Một ván dài bao lâu? | ✅ **Chốt:** 3 phút, số nằm trong `Config.PVP`. |
| **BF.** Triệt tiêu | Đòn của mình có trừ rác đang chờ không? | ✅ **Chốt:** có, trừ rác chờ trước, phần dư mới sang đối thủ. |
| **BG.** Chi tiết hàng rác | Ô bị đẩy ra, hàng đầy do rác, điểm khi xóa hàng rác | ✅ **Chốt:** ô bị đẩy ra biến mất; hàng đầy do rác xóa không điểm; hàng rác 7 ô + 1 lỗ; ô rác tính như ô thường (xem câu hỏi mở 1). |
| **BH.** Thời điểm áp rác | Ngay lập tức hay ở ranh giới bộ khối? | ✅ **Chốt:** chỉ khi nạn nhân nhận bộ mới, tối đa 1 hàng mỗi lần, hàng chờ tối đa 4. |
| **BI.** Bảng đòn | Xóa bao nhiêu thì gửi bao nhiêu? | ✅ **Chốt:** bảng khởi điểm ở mục Luật; chốt bằng mô phỏng M24. |
| **BJ.** Cùng nguồn khối | "Cùng seed" nghĩa là gì khi `Generator` phụ thuộc bảng? | ✅ **Chốt:** seed con cho từng bộ, độ khó theo số thứ tự bộ, bỏ mercy, luồng riêng cho lần chia sau hết nước. |
| **BK.** Xoay, hồi sinh, kiếm tiền | Có bán gì trong PVP không? | ✅ **Chốt:** không. Mỗi người 1 lượt xoay miễn phí mỗi ván; lượt đã mua và hồi sinh trả tiền không dùng được. |
| **BL.** Kết thúc và hòa | Ai thắng, hòa xử thế nào, nước sát giờ? | ✅ **Chốt:** điểm cao hơn thắng; bằng điểm là hòa (0,5); giờ server, gia hạn 0,3 giây cho mọi người. |
| **BM.** Rời ván, rớt mạng | Xử thua hay hủy? | ✅ **Chốt:** rời hoặc rớt mạng là thua; server tắt có báo trước thì hủy; không có kết nối lại ở bản đầu. |
| **BN.** ELO | Công thức, mức khởi đầu, K? | ✅ **Chốt:** ELO chuẩn, 1000 điểm, K 40 (10 ván đầu) / 24 / 16 (từ 1800), sàn 100, ghi trước khoản thua. |
| **BO.** Ranked và giao hữu | Lời mời có tính rank không? | ✅ **Chốt:** không. Ranked chỉ qua hàng chờ. |
| **BP.** Chống cày điểm | Nick phụ, cày lặp | ✅ **Chốt:** cặp 2 trận tính điểm mỗi 24 giờ, tắt trong private server, level ≥ 3, cửa sổ ≤ 400 điểm, không tự động cấm. |
| **BQ.** Matchmaking | Trong server hay liên server? | ✅ **Chốt:** trong server trước (M27); liên server (M29) chỉ khi số liệu hàng chờ cho thấy cần. |
| **BR.** Hàng chờ vắng | Làm gì khi không có ai? | ✅ **Chốt:** sau 20 giây mời đấu bot luyện tập (ghi rõ là bot, không tính rank), mời bạn, hoặc chờ tiếp. |
| **BS.** Mùa | Dài bao lâu, reset thế nào? | ✅ **Chốt:** theo tháng dương lịch UTC; kéo điểm về giữa 50% quanh 1000. |
| **BT.** Hạng và quà | Hạng, phần thưởng, badge | ✅ **Chốt:** 6 hạng Bronze đến Master; huy chương mùa theo hạng cao nhất; huy chương Top 10 và Champion; badge lần đầu đạt Gold, Diamond, Master. |
| **BU.** Bảng Rank | Lưu ở đâu, ai được lên? | ✅ **Chốt:** `Rank_<mùa>`, top 50, cần ≥ 5 ván trong mùa, tab thứ tư. |
| **BV.** Dữ liệu | Lưu gì? | ✅ **Chốt:** bảng `pvp` trong profile; không lưu id đối thủ, không lưu lịch sử trận. |
| **BW.** Bảng của đối thủ | Thấy gì của đối thủ? | ✅ **Chốt:** màu từng ô (theo mockup), ô rác, điểm, rác chờ; không thấy khay. Gửi không tin cậy, nhắc lại mỗi giây. |
| **BX.** Giao diện | Gray-box hay chờ mockup? | ✅ **Chốt:** theo 14 mockup PC trong `docs/mockups/phase6/`. Màn chưa có mockup (điện thoại và các màn phụ) dựng cùng phong cách bằng `Theme`/`Clay`, vẽ lại khi có mockup. |
| **BY.** Cổng kiểm UI | Có cần kiểm UI GĐ5 trước M26 không? | ✅ **Chốt:** có, một lượt Studio (M6 solo và màn hình M19/M21/M22). Test hai người của GĐ5 chạy trước khi bật M27. |
| **BZ.** Đấu lại | Ranked có đấu lại trực tiếp không? | ✅ **Chốt:** không, chỉ "Queue again". Giao hữu có "Play again" cần cả hai. |
| **CA.** Danh hiệu ở tab Rank | Hạng rank hay danh hiệu mốc cạnh tên? | ✅ **Chốt (theo mockup `05`):** tab Rank hiện tên hạng dưới tên người chơi; các tab khác giữ danh hiệu mốc. |
| **CB.** Báo trước hướng rác | Người chơi có thấy trước rác vào từ phía nào không? | ✅ **Chốt:** có. Hướng rút lúc hàng rác vào hàng chờ và hiện ở từng nấc IN cùng mũi tên ở mép bảng; lỗ rút lúc vào bảng, không báo trước. Triệt tiêu lấy hàng sắp vào nhất; quá trần thì bỏ hàng mới nhất (hai chi tiết này là đề xuất của mình). |
| **CC.** Nút Pause trong trận | Trận có đồng hồ thì Pause làm gì? | ✅ **Chốt:** mở bảng **Resume** và **Forfeit**, đồng hồ vẫn chạy; ván ranked ghi rõ "counts as a loss". |
| **CD.** Rác giúp nạn nhân (câu hỏi mở 1) | Sửa luật rác thế nào sau mô phỏng M24? | ✅ **Chốt:** hàng rác vụn (quá nửa là ô rác) xóa không điểm, không combo, không đòn; cộng đòn combo từ combo 8. Bot: điểm thấp hơn 9,7% khi có rác, gửi 8 hàng mỗi ván. Chỉnh lại sau thử thật ở M26. |
