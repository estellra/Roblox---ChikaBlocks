# Giai đoạn 5: Coop 2 người

> Plan đã duyệt. Mọi điểm AP đến BA đã chốt, xem [cuối file](#quyết-định-đã-chốt). Đã làm: M19 (xem [Kết quả M19](#kết-quả-m19)), M20 (xem [Kết quả M20](#kết-quả-m20)) và M21 (xem [Kết quả M21](#kết-quả-m21)) và M22 (xem [Kết quả M22](#kết-quả-m22)), và M23 (xem [Kết quả M23](#kết-quả-m23)), cả ba chưa chạy phần màn hình trong Studio. Giai đoạn 5 đã code xong.

## Bối cảnh

- Ván solo hiện có bốn lớp: `GameSession` (luật, dùng chung hai phía), `GameRuns` (ván của từng người trên server), `GameService` (remote, dữ liệu, analytics) và `GameController` (client dự đoán rồi so với server).
- Cả bốn lớp đều giả định **một người, một khay 3 khối**, và `moveIndex` là số nước của chính người đó. Coop khác ở ba chỗ:
  1. Một ván thuộc về hai người, nên phải có "phòng" đứng trên ván.
  2. Khay 4 khối, chia mỗi người 2.
  3. Hai client cùng dự đoán trên một bảng, nên hai nước có thể đè nhau. `moveIndex` kiểu solo không dùng được (cả hai sẽ cùng gửi chỉ số 5).
- **PVP chưa chốt luật (AP)**, nên GĐ5 chỉ dựng sẵn phần chắc chắn dùng chung với GĐ6: lời mời và phòng 2 người (`Rooms`, không biết gì về luật chơi). Không đoán trước luật PVP.
- Code solo không đổi hành vi. Chỗ duy nhất của solo bị đụng tới là `GameSession`/`Generator` (thêm tham số số khối mỗi bộ, mặc định 3) và `GameController` (tách phần giao thức, xem M21).

## Luật chơi Coop

- **Bảng chung 8×8, điểm chung, combo chung.** Cách tính điểm giữ nguyên như solo.
- **Mỗi bộ 4 khối:** ô 1–2 của người mời, ô 3–4 của người được mời. Mỗi người chỉ đặt được khối của mình, nhưng thấy cả khối của bạn chơi.
- **Đặt tự do, cùng lúc (AR).** Hai người thả đè nhau thì server nhận nước tới trước; khối của người kia quay về khay.
- **Bộ mới chỉ được chia khi cả 4 khối đã đặt.** Ai đặt xong trước thì khay hiện "Waiting for <tên>…".
- **Thua** khi còn khối trong khay mà không khối nào (của cả hai) đặt vừa. Nếu khối của bạn không vừa nhưng khối của bạn chơi còn vừa thì chưa thua: bạn chơi đặt, xóa hàng, rồi tới bạn.
- **Một người rời giữa ván (AQ):** người ở lại nhận luôn khối của người rời và chơi tiếp tới hết ván (các bộ sau vẫn 4 khối). **Điểm Coop được chốt tại lúc người kia rời**: bảng Coop và kỷ lục Coop của cả hai chỉ tính tới đó. HUD ghi rõ "Partner left · score no longer counts for Co-op". EXP vẫn được cộng cho người ở lại.
- **Người chơi treo máy (AU):** nếu bạn chơi còn khối đặt được mà 45 giây không làm gì, trong khi bạn không còn nước nào, bạn có nút "Take over". Bấm thì người kia bị đưa ra khỏi ván (về menu), xử lý y như họ tự rời.
- **Hết ván:** màn Game Over hiện điểm đội, phần đóng góp của từng người, EXP. "Play again" cần cả hai cùng bấm; "Menu" là rời phòng.
- Không có tutorial, xoay khối và hồi sinh trong bản Coop đầu tiên (M19–M22). Xoay và hồi sinh là M23.

## Các mốc

| Mốc | Nội dung | Cần trước | Chơi được gì khi xong |
|---|---|---|---|
| **M19** Phòng và lời mời | `Rooms` (logic thuần), `RoomService`, màn Co-op (danh sách người trong server), thông báo mời | Không | Hai client mời, nhận, từ chối, rời phòng. Nút Co-op còn ẩn (`Config.COOP.ENABLED = false`) |
| **M20** Luật Coop | `GameSession`/`Generator` nhận số khối mỗi bộ; `CoopSession` (chỗ ngồi, quyền đặt, tiếp quản, chốt điểm); mô phỏng độ khó | Không | Chỉ có Lune test; chưa có gì trên màn hình |
| **M21** Ván Coop | `CoopRuns`, `CoopService`, giao thức mới, client (`CoopSync`, khay 2 người, nước của bạn chơi), rời ván, treo máy, chơi lại | M19, M20 | Chơi trọn ván Coop với 2 client. Bật `COOP.ENABLED` |
| **M22** Dữ liệu và leaderboard | Kỷ lục Coop, EXP, analytics, bảng Coop theo cặp, xóa dữ liệu theo yêu cầu | M21 | Bảng Co-op trong màn Leaderboard |
| **M23** Xoay và hồi sinh trong Coop | Lượt xoay theo từng người, hồi sinh cho cả đội | M22, quyết định AV, AW | Kiếm tiền trong Coop |

**Thứ tự đề xuất:** M19 và M20 độc lập, làm cái nào trước cũng được (mình đề xuất M20 trước vì toàn logic thuần, lộ sớm vấn đề về độ khó). Rồi M21 → M22. M23 có plan riêng khi tới nơi.

## Kiến trúc

| File | Mới? | Vai trò |
|---|---|---|
| `src/server/Rooms.luau` | Mới | Logic thuần: lời mời, phòng 2 người, rời phòng. Không biết luật chơi; mỗi phòng mang một `mode` (`"coop"`, sau này `"pvp"`). **Phần dùng chung với GĐ6.** |
| `src/server/Services/RoomService.luau` | Mới | Nối `Rooms` với remote và `PlayerRemoving`; báo cho service khác khi phòng lập xong, có người rời, phòng giải tán |
| `src/shared/GameSession.luau`, `Generator.luau` | Sửa | Thêm tham số `setSize` (mặc định `Config.PIECES_PER_SET` = 3). Solo không đổi |
| `src/shared/CoopSession.luau` | Mới | Bọc một `GameSession` 4 khối: ô nào của ai, ai còn trong ván, tiếp quản, điểm đã chốt, đóng góp từng người. Dùng chung hai phía |
| `src/server/CoopRuns.luau` | Mới | Như `GameRuns` nhưng theo phòng: bắt đầu ván, nhận nước, từ chối nước xung đột, rời ván, đồng hồ treo máy. Logic thuần, đồng hồ và seed truyền vào |
| `src/server/Services/CoopService.luau` | Mới | Nối `CoopRuns` với remote, dữ liệu, EXP, leaderboard, analytics. `GameService` vẫn chỉ lo solo |
| `src/client/Util/CoopSync.luau` | Mới | Logic thuần phía client: trạng thái đã xác nhận + các nước đang chờ (xem giao thức) |
| `src/client/Controllers/CoopController.luau`, `Views/CoopView.luau` | Mới | Màn Co-op, thông báo mời, trạng thái phòng |
| `src/client/Controllers/GameController.luau` | Sửa | Tách phần giao thức thành hai "nguồn ván" (solo, coop) sau một interface nhỏ; phần vẽ và điều khiển dùng chung |
| `src/client/Views/TrayView.luau` + `PartnerTrayView.luau` | Sửa + mới | Khay nhận số ô; khay nhỏ hiện 2 khối của bạn chơi |
| `Leaderboards`, `LeaderboardService`, `Erasure`, `scripts/erase-user.luau` | Sửa | Bảng `Coop_all` khóa theo cặp (M22) |
| `Net`, `Config`, `PlayerData`, `Telemetry`, `DebugService` | Sửa | Remote mới, `Config.COOP`, trường dữ liệu mới, sự kiện mới, lệnh debug |

Một người chỉ ở trong **một** thứ tại một thời điểm: ván solo hoặc phòng Coop. Vào phòng thì ván solo đang dở kết thúc (analytics ghi cách kết thúc `coop`); gửi `StartGame` (solo) khi đang trong phòng thì tính là rời phòng.

## M19: Phòng và lời mời

### Cách dùng

- Menu có nút **Co-op** mở màn Co-op: danh sách người khác trong server (display name của Roblox, level), mỗi dòng một nút **Invite**. Người đang bận (đã ở trong phòng) hoặc chưa xong tutorial thì nút mờ kèm lý do.
- Server chỉ có một mình bạn: màn hình ghi "No one else is here yet" và nút **Invite friends** mở hộp mời bạn bè của Roblox (`SocialService:PromptGameInvite`; mình sẽ kiểm tra lại API hiện hành khi làm).
- Người được mời thấy thông báo "<tên> invites you to Co-op" với **Accept** / **Decline** và thanh đếm 30 giây. Thông báo nhỏ, không che bảng nếu họ đang chơi solo (AY).
- Nhận lời: phòng lập xong, ván Coop bắt đầu ngay cho cả hai.

### Luật của `Rooms`

- Mỗi người tối đa 1 lời mời đang gửi và 3 lời mời đang chờ trả lời (quá thì người mời nhận "busy").
- Lời mời hết hạn sau `COOP.INVITE_SECONDS` = 30. Server gửi **thời điểm hết hạn** một lần (`workspace:GetServerTimeNow()`), client tự vẽ thanh đếm.
- Bị từ chối hoặc hết hạn: cặp đó nghỉ 60 giây trước khi mời lại được (chống mời dồn).
- Hai người mời lẫn nhau cùng lúc: lời mời thứ hai được coi là nhận lời.
- Không mời được: chính mình, người không còn trong server, người đang trong phòng, người chưa xong tutorial; người mời cũng phải xong tutorial và không ở trong phòng.
- Rời phòng (tự rời, mất kết nối) thì phòng báo cho người còn lại; phòng hết người thì xóa. Mọi bảng theo người chơi được dọn ở `PlayerRemoving`.
- Trạng thái "bận" công bố qua attribute `CoopBusy` trên `Player` (tự nhân bản tới mọi client), nên danh sách không cần remote riêng.

### Remote

| Remote | Chiều | Nội dung |
|---|---|---|
| `CoopInvite(targetUserId)` | C → S | Số nguyên; server tự tìm người chơi bằng `GetPlayerByUserId`. Giới hạn 1 lần mỗi 2 giây |
| `CoopInviteReply(inviteId, accept)` | C → S | Chỉ người được mời của đúng lời mời đó trả lời được |
| `CoopCancelInvite()` | C → S | Rút lời mời đang gửi |
| `CoopLeave()` | C → S | Rời phòng (cũng là nút Menu ở Game Over) |
| `CoopInvited(inviteId, fromUserId, expiresAt)` | S → C | Hiện thông báo mời |
| `CoopInviteResult(targetUserId, result)` | S → C | `sent`, `declined`, `expired`, `busy`, `cooldown`, `left` |
| `CoopRoom(room)` | S → C | Phòng lập xong hoặc đổi: bạn chơi là ai, ai còn trong phòng, ai đã bấm Play again; `nil` khi phòng giải tán |

Client không bao giờ gửi `Instance`, tên hay chữ tự do; chỉ gửi số. Không có chữ do người chơi tự nhập nên không cần lọc văn bản.

### Test

- Lune (`Rooms`, đồng hồ giả): mời, nhận, từ chối, hết hạn, nghỉ 60 giây, mời chính mình, mời người bận, mời lẫn nhau, quá 3 lời mời chờ, rời khi đang có lời mời, rời phòng, không còn sót khóa nào sau khi cả hai rời.
- Studio, 2 client (Test → Clients and Servers): các luồng trên bằng nút thật; tin rác lên từng remote; người vào server sau xuất hiện trong danh sách.

### Kết quả M19

- **`Rooms`** (`src/server/Rooms.luau`, logic thuần, đồng hồ và "ai chơi được" truyền vào): đúng các luật trong plan. Một người có tối đa 1 lời mời đang gửi và 3 đang chờ; lời mời sống 30 giây; từ chối hoặc hết hạn thì **cả hai chiều** của cặp nghỉ 60 giây; mời lẫn nhau coi như nhận lời (người mời trước làm chỗ 1); vào phòng thì rút các lời mời đã gửi và trả lời "busy" các lời mời đang chờ; phòng còn khi một người rời, mất khi người cuối rời. Mọi thứ cần báo cho người chơi đi ra qua `deps.emit` dưới dạng sự kiện có địa chỉ (`invited`, `result`, `room`) và sự kiện cho service khác (`formed`, `memberLeft`, `closed`). `remove` (người chơi rời server) dọn sạch mọi bảng, có test `footprint() == 0`.
- **`RoomService`** nối `Rooms` với remote và `Players`: giới hạn tần suất (mời 1 lần mỗi 2 giây), kiểm kiểu từng tham số (UserId là số nguyên trong ±2^53, vì người chơi thử nhiều client trong Studio có thể mang UserId âm), tìm người bằng `GetPlayerByUserId`, quét lời mời hết hạn mỗi giây. Công bố trên mỗi `Player` hai attribute: `CoopBusy` (`"room"`, `"tutorial"`, `"loading"` hoặc nil khi rảnh) và `Level`, nên màn Co-op không cần remote riêng để liệt kê. Có `onRoomFormed`, `onMemberLeft`, `onRoomClosed` cho CoopService ở M21. Gửi `StartGame` thì rời phòng (một người chỉ ở trong một thứ).
- **Remote** (trong `Net`): `CoopInvite`, `CoopInviteReply`, `CoopCancelInvite`, `CoopLeave` (client gửi số), `CoopInvited`, `CoopInviteResult`, `CoopRoom` (server gửi).
- **Client:** nút **Co-op** trên menu, `CoopView` (màn Co-op: danh sách người trong server kèm level, nút Invite/Cancel, thẻ phòng với nút Leave, "No one else is here yet" + Invite friends), `CoopInviteView` (thẻ mời có Accept/Decline và thanh đếm), `CoopController` giữ trạng thái. Gray-box theo `Theme`/`Clay`.
- **Khác plan:**
  - `CoopInviteResult(otherUserId, result)`: tham số đầu là người còn lại của lời mời (không phải luôn là người được mời), và thêm kết quả `cancelled` cho bên được mời (lời mời biến mất khỏi màn hình khi người mời rút lại, rời hoặc vào phòng).
  - **Thông báo mời nằm trên vùng điểm số, chỉ hiện thẻ cũ nhất kèm "+N" cho các thẻ chờ**, thay vì xếp chồng ở giữa trên. Bản đầu đặt giữa trên và đè lên góc bảng ở màn ngang, trái với AY; đã bỏ. Hệ quả: lời mời hiện ra sẽ che điểm tạm thời, không che bảng hay khay.
  - Nút Co-op nằm **cùng hàng** với Leaderboard (mỗi nút nửa hàng, chữ tự thu nhỏ cho vừa) thay vì thêm một hàng, để vừa màn điện thoại ngang thấp.
  - `Config.COOP.ENABLED = false`: client ẩn nút và server bỏ qua remote Coop, **trừ trong Studio** (luôn bật để thử).
  - `GameService.onTutorialDone` (mới) để `CoopBusy` đổi ngay khi người chơi xong tutorial; lệnh debug `coop` ở server và `coop …` ở client (đưa vào đúng thứ server sẽ gửi, bấm Invite cho người giả).
  - **Chưa làm (để M21):** vào phòng chưa kết thúc ván solo đang dở, vì chưa có ván Coop để chuyển sang. Nhận lời khi đang chơi solo chỉ lập phòng; ván solo vẫn chạy.
- **Test:** **224 pass** (thêm 17 trong `Rooms.spec`: mời, nhận, từ chối, hết hạn, nghỉ 60 giây hai chiều, trả lời sau hạn, các lời từ chối vô nghĩa, mời lẫn nhau, giới hạn 1 và 3, chỉ đúng người được mời trả lời và tham số rác, vào phòng thì dọn mọi lời mời, rời phòng, người chơi rời server ở từng trạng thái, mô tả debug, và một bài ngẫu nhiên 300 thao tác của 6 người kiểm bất biến rồi cho cả sáu rời, không sót khóa nào). `stylua` sạch, `selene src` sạch.

| Kiểm tra trong Studio (một client) | Kết quả |
|---|---|
| Server khởi động | `RoomService` chạy; Player có `CoopBusy=nil` (rảnh) và `Level=5`; `coop` báo không có lời mời, phòng hay nghỉ |
| Bấm nút Co-op trên menu bằng chuột thật, rồi nút X | Mở màn Co-op, X đóng và về menu |
| Server chỉ có một mình | "No one else is here yet." và nút Invite friends |
| 6 người giả đủ trạng thái | Chỉ người rảnh có nút Invite sáng; "In a room", "In tutorial", "Joining…" mờ kèm lý do |
| Bấm Invite một UserId không có trong server (qua server thật) | Server trả `left`, màn ghi "That player is no longer here.", nút về lại Invite |
| Lời mời đang chờ | Nút thành Cancel, các nút khác mờ |
| Kết quả declined, busy, cooldown, expired, left | Mỗi loại một câu riêng, tự xóa sau 6 giây |
| Ba lời mời liên tiếp giữa ván solo (màn ngang 1276×584) | Chỉ thẻ cũ nhất hiện, kèm "+2", thanh đếm đúng thời gian còn lại, nằm trên vùng điểm số; không đè bảng hay khay |
| Thẻ mời khi đang ở màn Co-op | Hiện phía trên màn |
| Thẻ phòng "In a room with …" + Leave; "Your partner left the room."; ghi chú "Finish the tutorial…" khi `CoopBusy` của mình là tutorial | Đúng |
| Dữ liệu rác (nil, chuỗi, NaN, ±inf, 1e300, bảng, Vector3, 2^60, 1,5, tham số thừa) lên `CoopInvite`, `CoopInviteReply`, `CoopCancelInvite`, `CoopLeave` | Không có lỗi ở Output; server không có lời mời hay phòng nào |
| Output | Không có lỗi từ game (chỉ cảnh báo `ContentId rbxassetid://203785492` của Studio, đã ghi từ GĐ1) |

- **Chưa kiểm tra được:**
  - Mọi luồng cần **hai người thật** (nhận, từ chối, hết hạn, rời phòng, người vào server sau): Studio MCP không mở được hai client. Đã phủ bằng test `Rooms` và bằng việc đẩy vào client đúng thứ server sẽ gửi; chưa chạy thật giữa hai client.
  - `SocialService:PromptGameInvite`: docs ghi API này không chạy trong Studio. Nút Invite friends hiện được (`CanSendGameInviteAsync` trả true trong Studio) nhưng chưa bấm thử; chỉ kiểm được sau khi publish.
  - Phím Escape và Backspace đóng màn, tay cầm, màn dọc và iPhone: phím do MCP gửi không tới `InputBegan` (màn Support cũ cũng không đóng bằng cách thử này), và không đổi được cỡ cửa sổ qua MCP. Mã đóng màn giống `SupportView`. Thẻ mời bám vào vùng điểm số nên theo bố cục dọc, nhưng chưa nhìn thấy.
  - Kiểm kiểu `--!strict` (không có luau-lsp/analyze trong repo); Rojo đã sync và chạy không lỗi ở Output.
- **Giới hạn đã biết:** remote chỉ gửi một lần: lời mời đến đúng lúc client chưa nghe được thì mất và hết hạn sau 30 giây (chưa có cách xin lại trạng thái, M21 thêm nếu cần). Người chơi ngoài Studio chỉ thấy danh sách người trong cùng server, không có bạn bè ở server khác.
- **Test thủ công:** để sau khi xong cả giai đoạn và publish, chạy một lượt với hai tài khoản thật. Phần của M19: mời, nhận, từ chối, rút lời mời, để lời mời hết hạn, mời lại trong 60 giây, rời phòng, đóng một client giữa chừng, người vào server sau có hiện trong danh sách không, nút Invite friends, và các phím Escape/Backspace, tay cầm, màn dọc. Cả hai tài khoản phải xong tutorial.

## M20: Luật Coop

### `GameSession` và `Generator`

- `GameSession.new(setSource, initialBoard?, setSize?)` và `Generator.newSource(rng, setSize?)`. `SET_SIZE` thành trường của session; snapshot giữ nguyên dạng (mảng `tray` dài 4 thay vì 3). Toàn bộ 173 test hiện có phải pass mà không sửa.
- `MAX_HUGE_PER_SET` vẫn là 1 cho bộ 4 khối.
- **Kiểm tra công bằng `WholeSet` với 4 khối tốn hơn** (thêm một tầng tìm kiếm). Đã có trần `SOLVER_NODE_BUDGET`; M20 đo thời gian chia một bộ (trung bình và tệ nhất) và chỉ hạ trần cho Coop nếu vượt vài mili giây.

### `CoopSession`

- Giữ một `GameSession` 4 khối và thêm:
  - `seatOf(slot)`: ô 1–2 là chỗ 1, ô 3–4 là chỗ 2.
  - `place(seat, slot, x, y)`: từ chối khi ô không thuộc chỗ đó (trừ khi chỗ kia đã rời), còn lại giao cho `GameSession.place`.
  - `release(seat)`: người ở chỗ đó rời; chỗ còn lại đặt được mọi ô; `countedScore` chốt bằng điểm lúc đó.
  - `countedScore`: điểm tính cho kỷ lục và bảng Coop (bằng `score` khi còn đủ hai người).
  - `contribution[seat]`: điểm do nước của từng người mang lại, cho màn Game Over.
- Snapshot = snapshot của `GameSession` + `present` (ai còn trong ván), `countedScore`, `contribution`.

### Độ khó

- 4 khối mỗi bộ trên cùng bảng 8×8 khó hơn solo ở điểm cao (phải đặt hết 4 khối mới có bộ mới). `tests/Simulation.spec.luau` thêm bot tham lam chơi bộ 4 khối, in điểm trung vị cạnh solo.
- Mục tiêu tune: ván Coop của bot dài trong khoảng ±30% so với solo. Nếu lệch, `Config.COOP.GENERATOR` ghi đè các ngưỡng (`WHOLE_SET_BELOW_SCORE`, `EACH_PIECE_BELOW_SCORE`, `DIFFICULTY_MAX_SCORE`). Con số chốt sau khi có kết quả mô phỏng.

### Test

- Lune: `GameSession` với `setSize` 4 (chia, thua, snapshot đi và về); `Generator` 4 khối (đủ số khối, các mức công bằng vẫn đúng, thời gian chia); `CoopSession` (quyền đặt theo chỗ, đặt hộ sau `release`, `countedScore` đứng yên sau `release`, đóng góp cộng lại bằng điểm đội, luật thua khi chỉ một bên còn nước).

### Kết quả M20

- **`GameSession` và `Generator` nhận số khối mỗi bộ.** `GameSession.new(setSource, initialBoard?, setSize?)` giữ `setSize` thành trường của session; `fromSnapshot` lấy cỡ bộ từ độ dài `tray` của snapshot (snapshot Coop có `tray` dài 4, dạng snapshot không đổi). `Generator.nextSet(…, setSize?, overrides?)` và `newSource(rng, setSize?, overrides?)`; bộ dự phòng toàn Chấm cũng theo cỡ bộ, `MAX_HUGE_PER_SET` vẫn là 1. Mặc định vẫn 3 và thứ tự rút ngẫu nhiên không đổi (cùng seed ra đúng bộ cũ, có test). **173 test cũ pass không sửa**: không spec cũ nào bị đụng, `tests/run.luau` chỉ thêm 3 dòng đăng ký spec mới.
- **`CoopSession`** (`src/shared/CoopSession.luau`, dùng chung hai phía): `new`, `fromSnapshot`, `snapshot`, `receiveSet`, `seatOf(slot)`, `slotsOf(seat)`, `canPlace`, `place(seat, slot, x, y)`, `release(seat)`, `countedScore`, `contribution`, và `newSource(rng)` (4 khối, dùng `Config.COOP.GENERATOR`). Quy tắc đúng như plan: chỗ 1 giữ ô 1–2, chỗ 2 giữ ô 3–4; sau `release` người ở lại đặt được mọi ô, người rời không đặt được gì; `countedScore` đi theo `score` khi còn đủ hai người rồi đứng yên (lần `release` thứ hai không đổi nó); `contribution[1] + contribution[2]` luôn bằng điểm đội; luật thua giữ nguyên của `GameSession` (hết cả bốn khối vừa mới thua).
- **Khác plan (nhỏ, cho M21 dùng):**
  - Snapshot **lồng**: `{ game = <snapshot GameSession>, present, countedScore, contribution }` thay vì dàn phẳng, để không chép lại 11 trường của `GameSession.Snapshot`.
  - Thêm `GameSession.hasPlacement(slot)` (phép thử mà game over dùng) và `CoopSession.hasMove(seat)`: "người này có khối của mình đặt vừa không". M21 cần cho điều kiện nút Take over (bạn chơi còn nước, mình hết nước).
  - `Config.COOP = { SET_SIZE = 4, GENERATOR = { SOLVER_NODE_BUDGET = 500 } }`. `Generator.Overrides` cho ghi đè bốn số (`DIFFICULTY_MAX_SCORE`, `WHOLE_SET_BELOW_SCORE`, `EACH_PIECE_BELOW_SCORE`, `SOLVER_NODE_BUDGET`); Coop chỉ cần đổi trần node, ba số kia giữ nguyên.
- **Độ khó** (bot tham lam, không hồi sinh vì Coop chưa có hồi sinh; 200 ván mỗi bên, một bot điều khiển cả hai chỗ):

| | Trung vị số nước | Trung vị điểm | Chạm 1500 | Chạm 5000 |
|---|---|---|---|---|
| Solo (3 khối) | 86 | 1793 | 56% | 12% |
| Coop (4 khối) | 94 | 1765 | 56% | 16% |

  Ván Coop dài **109%** ván solo, trong mục tiêu ±30%, nên **không phải đụng tới ba ngưỡng độ khó**. Giới hạn của phép đo: không hồi sinh thì bot chết quanh 1.700 điểm, nên vùng điểm cao (từ 5000) chỉ có 12–16% ván chạm tới. Số liệu ở đó mỏng; đánh giá lại khi có người chơi thật.
- **Thời gian chia bộ** (đo trong ván bot thật và trên bảng ngẫu nhiên đông đặc): bộ 4 khối trung bình chỉ 0,02–0,08 ms (solo 0,01–0,03), nhưng đuôi dài hơn hẳn. Với trần mặc định 20000, khoảng **1 đến 2 lần trên 1.000 lần chia vượt 5 ms và lần chậm nhất 9–49 ms** (solo chậm nhất 1–2 ms). Plan nói hạ trần nếu vượt vài ms, nên đã quét trần node trên 800 ván bot:

| Trần node (4 khối) | Chia bộ chậm nhất | Số lần > 2 ms | Trung vị ván bot (điểm / nước) |
|---|---|---|---|
| 20000 (mặc định) | 9,1 ms | 18 / 22.860 | 1595 / 87 |
| 1000 | 3,6 ms | 3 / 23.003 | 1603 / 87 |
| **500 (chọn)** | **2,8 ms** | **1 / 23.230** | **1682 / 91** |
| 250 | 1,5 ms | 0 / 23.440 | 1740 / 91 |
| 100 | 2,3 ms | 1 / 24.306 | 1959 / 102 |

  Chọn **500**: đuôi giảm ít nhất khoảng 3 lần mà ván bot chỉ dài hơn khoảng 5% (từ 250 trở xuống bộ dễ dần, ở 100 ván dài hơn 17%). Hạ trần **không** làm yếu cam kết công bằng: trần cạn thì bộ bị coi là chưa chứng minh được và rút lại, không bao giờ nhận bộ không đặt được. Tỉ lệ bộ toàn khối nhỏ giữ nguyên (0,82%) và bộ toàn Chấm là 0,004%, nên trần thấp không làm bộ khối dự phòng xuất hiện nhiều hơn. Máy này nhiễu: cùng cấu hình, chậm nhất lệch tới ×3 giữa các lần chạy, nên bảng chỉ để so sánh tương đối. Test `Co-op nextSet` chỉ báo lỗi khi tệ nhất vượt 50 ms.
- **Test:** **207 pass** (thêm 34: `SetSize` 16, `CoopSession` 15, `CoopSimulation` 3). `SetSize` gồm `GameSession` với bộ 4 (chia, chỉ làm mới khi đủ 4, thua, snapshot đi và về, nguồn chờ) và `Generator` 4 khối (đủ số khối, mức công bằng đúng trên 4.000 bảng ngẫu nhiên, khớp tìm kiếm vét cạn, ghi đè, thời gian). `CoopSimulation` có bot tham lam chơi 200 ván solo và Coop (kiểm bất biến sau mỗi nước), 200 ván có một người rời giữa ván (người rời không đặt được gì, `countedScore` đứng yên), và 100 ván client giả theo server từng nước kể cả khi có người rời: **12.226 nước, 2.983 bộ giao, 48 người rời, không lệch**. Phần lockstep Coop đầy đủ (tin đến trễ, xung đột) vẫn là của M21. Test bot nằm trong `CoopSimulation.spec` chứ không thêm vào `Simulation.spec` để spec cũ giữ nguyên; bot là bản sao có thay `linesCompleted` bằng `Board.previewLines`.
- **Công cụ:** `stylua src tests` sạch, `selene src` sạch, ba spec mới cũng sạch khi lint. `selene tests` còn 12 lỗi có sẵn từ trước (`assert` một tham số trong các spec cũ), không đụng tới.
- **Chưa kiểm tra được:** kiểm kiểu `--!strict`. Repo không có luau-lsp hay luau-analyze và Lune không kiểm kiểu, nên các file mới mới chỉ chạy được, chưa được trình kiểm kiểu duyệt; sẽ biết khi Rojo sync vào Studio ở M21. Chưa có gì trên màn hình, đúng như mốc.
- **Giới hạn đã biết:**
  - Số liệu độ khó chỉ từ bot, chưa từ người chơi thật; bot chơi một mình điều khiển cả hai chỗ nên không có xung đột thả đè nhau.
  - `CoopSession` chưa có xoay và hồi sinh (M23). `GameSession.rotate` vẫn dùng bộ đếm lượt miễn phí chung của phiên, cần đổi sang "ví" theo người khi tới M23.
  - `hasMove` dựa trên `hasPlacement` nên đã tính cả khối đã mở khóa xoay; M23 không cần sửa chỗ này.

## M21: Ván Coop

### Giao thức

```
Client A / B                                    Server (CoopService → CoopRuns)
  │ (phòng lập xong)                              ván mới, seed bí mật, chia 4 khối
  │ ◀──── CoopState(state, "start") ────────────  snapshot, runId, bạn ngồi chỗ nào
  │
  │ đặt khối ngay trên bản dự đoán
  │ CoopPlace(runId, moveId, slot, x, y) ──────▶  giới hạn tần suất → đúng chỗ ngồi? → còn vừa?
  │                                               hợp lệ: seq + 1, gửi cho CẢ HAI
  │ ◀──── CoopEvent("move", runId, seq, seat, moveId, slot, x, y, score, set?, isOver)
  │                                               không hợp lệ (bạn chơi đã chiếm ô): chỉ gửi người đặt
  │ ◀──── CoopReject(runId, moveId) ────────────  khối quay về khay
  │
  │ CoopRequestState() ────────────────────────▶  thấy lệch (seq nhảy cóc, điểm khác, quá 2 giây chưa xác nhận)
  │ ◀──── CoopState(state, "resync" | "takeover")
```

- **Server xếp thứ tự.** Mỗi nước được nhận mang một số `seq` tăng dần của cả ván. `moveId` là bộ đếm riêng của từng client, chỉ để client nhận ra nước của mình.
- **Client giữ hai lớp (`CoopSync`):**
  - *Đã xác nhận*: `CoopSession` dựng từ `CoopState`, chỉ áp các `CoopEvent` theo đúng `seq`.
  - *Đang chờ*: các nước của mình đã gửi mà chưa được xác nhận (thường 0 hoặc 1 nước).
  - Thứ hiện trên màn hình = đã xác nhận + áp lại các nước đang chờ. Khi nước của bạn chơi tới, client áp vào lớp đã xác nhận rồi dựng lại; nước đang chờ nào không còn vừa thì bỏ ngay (khối bay về khay), không đợi `CoopReject`.
- Điểm và combo do server tính. Client so điểm của lớp đã xác nhận với `score` trong `CoopEvent`; lệch thì xin lại trạng thái.
- Bộ khối mới đi kèm `CoopEvent` của nước thứ 4 (`set` = 4 id). Seed không rời server, như solo.
- Mọi remote đều là `RemoteEvent` (tin cậy, đúng thứ tự). Mỗi nước chỉ gửi thay đổi (vài con số), không gửi cả bảng.
- **Bóng khối của bạn chơi (BA, bỏ được nếu rối mắt):** `CoopHover(slot, x, y)` qua `UnreliableRemoteEvent`, client gửi tối đa 10 lần/giây và chỉ khi ô đổi; server kiểm số nguyên trong bảng, giới hạn tần suất, chuyển cho bạn chơi. Thấy bạn chơi đang nhắm ô nào thì ít thả đè nhau hơn.

### Server

- `CoopRuns` (thuần, test bằng Lune với người chơi giả và đồng hồ giả): `start(room)`, `place(player, runId, moveId, slot, x, y)`, `leave(player)`, `takeOver(player, runId)`, `state(player)`, `summary(room)`. Kết quả là union có `kind` như `GameRuns` (`accepted`, `rejected`, `resync`, `ignored`).
- Giới hạn tần suất theo từng người như solo (đặt khối 8 lần/giây, xin trạng thái 2 lần/giây).
- **Rời ván:** `PlayerRemoving`, `CoopLeave`, hoặc bị tiếp quản → `CoopSession.release` → gửi `CoopState(…, "takeover")` cho người ở lại.
- **Treo máy:** server ghi thời điểm hành động cuối của mỗi người. `CoopTakeOver` chỉ được nhận khi đồng hồ **của server** cho thấy bạn chơi đã im ≥ `COOP.AFK_SECONDS` và người bấm không còn nước nào. Server gửi thời điểm nút sẽ mở; client chỉ vẽ.
- **Chơi lại:** `CoopRematch()` từ cả hai thì `CoopRuns.start` lại trong cùng phòng. Một người đã bấm thì người kia thấy "<tên> wants to play again".

### Client

- **Tách `GameController`:** phần vẽ, màn Game Over, listener giữ nguyên chỗ. Phần giao thức thành hai nguồn ván sau một interface nhỏ (`session()` để vẽ, `canDrag(slot)`, `tryPlace`, `tryRotate`, `mode`): nguồn solo là code hiện tại (dự đoán theo `moveIndex`, hồi sinh, xoay), nguồn coop dùng `CoopSync`. `DragController` và `GamepadController` vẫn gọi `GameController` như cũ.
- **Khay:** `TrayView` nhận số ô (2 ô to của mình). `PartnerTrayView` hiện 2 khối của bạn chơi, nhỏ, kèm tên; đặt ở chỗ ô thứ ba của khay solo nên bố cục dọc và ngang không phải dàn lại. Sau khi tiếp quản, khay nhỏ kéo được.
- **Nước của bạn chơi:** chạy hiệu ứng đặt và xóa hàng như nước của mình, thêm viền màu ngắn để biết ai vừa đặt.
- **HUD:** tên bạn chơi, điểm đội; "Waiting for <tên>…" khi mình hết khối; dòng "Partner left…" sau khi tiếp quản; nút Pause mở bảng có "Leave run" (ván không dừng).
- Gamepad và bàn phím: LB/RB chỉ đi qua các ô kéo được.
- Giao diện gray-box theo `Theme` và `Clay` hiện có (AZ).

### Debug (chỉ Studio)

- Server: `coopbot [nước/giây]` ghép người chơi với một bạn chơi giả chạy trên server (đặt nước hợp lệ ngẫu nhiên, có thể bảo nó treo máy hoặc rời). Nhờ vậy một cửa sổ Studio vẫn thử được gần hết Coop, và mình tự chạy được qua Studio MCP. `coop` in trạng thái phòng và ván.
- Client: `coop` in hai lớp của `CoopSync`.

### Test

- Lune:
  - `CoopRuns`: tham số rác, sai chỗ ngồi, ván cũ, gửi dồn, hai nước đè nhau (một nhận, một từ chối), rời ván, tiếp quản trước và sau hạn treo máy, chơi lại.
  - **Lockstep Coop:** 200 ván, hai client giả và server, tin nhắn đến trễ ngẫu nhiên và có xung đột. Sau khi mọi tin đã tới: hai client và server giống hệt nhau, không còn nước đang chờ.
- Studio, 2 client: chơi trọn ván; cố tình thả đè nhau; một bên rời giữa ván; treo máy rồi tiếp quản; chơi lại; Network Simulator 3G ở một bên; iPhone dọc và ngang; tay cầm. Không có cảnh báo resync khi chơi bình thường.

### Kết quả M21

> **Lưu ý: phần giao diện chưa được chạy trong Studio.** Studio MCP không kết nối được trong lúc làm mốc này (`Server's protocol version is not supported: 2026-07-28`, khởi động lại Claude vẫn không hết). Logic server và đồng bộ có test phủ; còn mọi thứ vẽ lên màn hình mới chỉ được viết và đọc lại, chưa ai thấy chạy. Các ca cần xem ở mục "Test thủ công" bên dưới.

- **`CoopRuns`** (`src/server/CoopRuns.luau`, logic thuần, đồng hồ và seed truyền vào): `start(room)`, `place`, `state`, `leave`, `takeOver`, `rematch`, `close`, `remove`, `summary`, `peek`. Mỗi nước được nhận mang một `seq` tăng dần của cả ván; `moveId` là bộ đếm riêng của client. Một nước không còn vừa (bạn chơi đã chiếm ô, khối đã đặt, không phải khối của mình, ván đã hết) bị **từ chối** (`CoopReject`, chỉ gửi người đặt); tham số không hợp lệ (kiểu, số nguyên, ván cũ, quá tần suất) bị **bỏ qua** không trả lời. Giới hạn đặt 8 lần mỗi giây, xin trạng thái 2 lần mỗi giây.
- **Tiếp quản (AU):** người bấm phải không còn nước đi, bạn chơi còn nước, và **không ai đặt khối nào trong 45 giây** (tính từ nước nhận gần nhất của cả hai, chứ không chỉ của bạn chơi, để người vừa đặt xong hết khối không bị tính là treo máy ngay). Server gửi thời điểm nút mở (`takeOverAt`, giờ server) kèm `CoopEvent` và `CoopState` cho đúng người đang chờ, không có remote riêng; client chỉ vẽ. Server kiểm lại khi nhận `CoopTakeOver`.
- **`CoopService`**: phòng lập xong thì ván solo của cả hai kết thúc (`GameService.abandonRun`, analytics ghi cách kết thúc `coop`) và ván Coop bắt đầu; người rời phòng (tự rời, mất kết nối, bị tiếp quản) rời ván, người ở lại nhận `CoopState(…, "takeover")`; phòng đóng thì ván bị quên; chơi lại cần cả hai (`CoopRematchVotes` cho biết ai đã bấm). Remote mới: `CoopPlace`, `CoopRequestState`, `CoopTakeOver`, `CoopRematch` (client gửi) và `CoopState`, `CoopEvent`, `CoopReject`, `CoopRematchVotes` (server gửi). `CoopState` còn mang `userIds` của hai người để client biết tên bạn chơi, vì tin này có thể tới trước `CoopRoom`.
- **`CoopSync`** (`src/client/Util/CoopSync.luau`, logic thuần): lớp đã xác nhận (áp từng `CoopEvent` đúng `seq`) và lớp đang chờ (nước của mình chưa được xác nhận); cái hiện ra là lớp đã xác nhận cộng các nước đang chờ chơi lại. Nước đang chờ mà không còn vừa thì bỏ ngay khi nước của bạn chơi tới, không đợi `CoopReject`. `seq` nhảy cóc, nước không vừa bản của mình, điểm lệch, bộ khối đến sai lúc hoặc `isOver` lệch thì xin lại trạng thái.
- **Tách `GameController`:** thay vì dời code solo (rủi ro làm hỏng solo), code solo giữ nguyên và `GameController` nhận một `Source`: `session()` để vẽ, `runId`, `canDrag(slot)`, `tryPlace`, `tryRotate`, `statusText`, `gameOver`, `leave`, `playAgain`, `takeOver`. Khi có `Source` thì các hàm công khai (`getSession`, `tryPlace`, `tryRotate`, `getRunId`, `pause`, `restart`, `requestMenu`, `getRotationText`) hỏi nó. Thêm `canDrag`, `getSlotCount`, `isCoop`, `attachSource`, `detachSource`, `sourceChanged`, `sourceReplaced`. `CoopRunController` (client) là nguồn Coop. `DragController.pick` và `GamepadController` (LB/RB) chỉ đi qua các ô `canDrag`.
- **Giao diện:** `TrayView` dựng sẵn 4 ô một lần; solo dùng 3, Coop xếp 2 ô của mình ở khay và 2 ô của bạn chơi (nhỏ, kèm tên) trong một bảng đặt ở chỗ ô thứ ba (`configure`), nên `DragController` vẫn nối đúng các ô cũ. `HudBar` đổi thành "TEAM SCORE" và pill ghi "With <tên>" thay cho kỷ lục; `Hud` có Game Over Coop (điểm đội, phần đóng góp từng người, ghi chú nếu bạn chơi đã rời, nút Play again chờ cả hai: "Waiting for <tên>…" hoặc "<tên> wants to play again"), bảng Pause có "Leave run" thay cho Play again và Menu, và nút **Take over** nổi trên bảng; khối bạn chơi vừa đặt có viền màu tím ngắn (`BoardView.accent`). Dòng dưới khay ghi "Waiting for <tên>…" hoặc "Partner left · score no longer counts for Co-op". Nhận lời mời khi đang ở menu hay màn Leaderboard/Support/Co-op thì các màn đó đóng hẳn (`MenuController.leaveForGame`).
- **Điểm Coop sau khi bạn rời (AQ):** đã đúng ở `CoopSession` từ M20; màn Game Over ghi "<tên> left: N counts for Co-op".
- **Debug (chỉ Studio):** server `coopbot [userId] [nước/giây]` ghép người chơi với bạn chơi giả chạy trên server (đặt nước hợp lệ ngẫu nhiên, tự bấm chơi lại khi hết ván); `coopbot nil nil afk|back|leave` cho nó treo máy, chơi tiếp hoặc rời; `coop` in thêm ván Coop của từng người. Client `coop run|play [n]|again|leave|takeover` xem trạng thái và điều khiển ván Coop.
- **Khác plan:** bật `Config.COOP.ENABLED = true` (nút Co-op hiện ngoài Studio; dữ liệu, EXP và bảng Coop chưa có tới M22); `CoopSession.mayPlace` thành hàm công khai; `Telemetry.RunEnd` thêm `"coop"`; `GameService.abandonRun`; remote `CoopRematchVotes` (plan chỉ nói "người kia thấy <tên> wants to play again").
- **Bóng khối của bạn chơi (BA):** khi người chơi kéo một khối tới một ô đặt được (chuột, cảm ứng, bàn phím hay tay cầm), `DragController.onAim` báo ô đó; `CoopRunController` gửi `CoopHover(slot, x, y)` (`UnreliableRemoteEvent`) **chỉ khi ô đổi, tối đa 10 lần mỗi giây** (ô mới nhất chờ tới lượt), gửi lại mỗi nửa giây khi giữ yên, và gửi không tham số khi thả hoặc rời bảng. Server (`CoopRuns.hover`) giới hạn 12 lần mỗi giây, kiểm đó là khối của đúng người gửi và còn trong khay, ô là số nguyên trong bảng cho khối đó, và còn bạn chơi để báo; sai thì bỏ lặng lẽ. Rồi chuyển cho bạn chơi bằng `CoopPartnerHover`. Client vẽ viền các ô của khối (màu tím của bạn chơi, trong suốt, dưới ghost của chính mình, `BoardView.showPartnerAim`), trượt theo ô; bóng **tự tắt sau 1,2 giây không được làm mới** (tin không tin cậy có thể rơi mất tin "thả") và tắt ngay khi nước của bạn chơi tới. Bạn chơi giả `coopbot` cũng giữ khối lên ô một chút (0,4 giây) trước khi đặt, nên thử được cả đường này.
- **Chưa làm:** xoay khối và hồi sinh trong Coop (M23).
- **Test:** **253 pass** (thêm 29: `CoopRuns` 17, `CoopSync` 11, `CoopLockstep` 1). `CoopRuns`: tham số rác, sai chỗ ngồi, hai nước đè nhau (một nhận, một từ chối, không tốn `seq`), giới hạn tần suất, rời ván (người ở lại đặt được khối của người rời, điểm chốt đứng yên), tiếp quản trước và sau hạn 45 giây (kể cả khi bạn chơi đặt thêm khối làm đồng hồ chạy lại), chơi lại cần cả hai, không chơi lại khi bạn đã rời, dọn sạch bảng, và bóng khối (báo cho bạn chơi, bỏ khi sai chỗ ngồi, khối đã đặt, ngoài bảng, tham số rác hoặc không còn bạn chơi, giới hạn 12 lần mỗi giây). `CoopSync`: nước của mình hiện ngay, bị bạn chơi chiếm ô thì rơi ra khỏi hàng chờ và lệnh `CoopReject` đến sau không làm gì, `seq` nhảy cóc, điểm lệch, nước trùng, bộ khối. **Lockstep Coop:** 200 ván, hai client giả (`CoopSync`) và server thật (`CoopRuns`), mọi tin trễ ngẫu nhiên 0–6 nhịp nhưng vẫn đúng thứ tự: **2.692 nước được nhận, 590 nước bị từ chối do xung đột, 582 nước bị bỏ sớm ở client, 50 người rời giữa ván, 0 lần phải xin lại trạng thái**; khi mọi tin đã tới, hai client và server giống hệt nhau, không còn nước chờ, bảng không còn hàng đầy. `stylua` sạch, `selene src` sạch.

- **Chưa kiểm tra được:**
  - **Mọi thứ trên màn hình** (xem lưu ý đầu mục): khay hai người ở bố cục dọc và ngang, chữ "With <tên>", thẻ HUD, panel Game Over Coop, nút Take over, viền màu của khối bạn chơi, hiệu ứng khối đặt và xóa hàng của nước bạn chơi, cụm ô nhỏ có kéo được sau khi tiếp quản, và **bóng khối của bạn chơi** (vị trí, độ trong, có quá rối mắt không; plan cho bỏ nếu rối).
  - **Ván solo sau khi sửa `TrayView`, `GameController`, `DragController`, `GamepadController`, `Hud`:** plan yêu cầu chạy lại danh sách thử Studio của M6 cho solo; chưa chạy (chỉ có lockstep solo và toàn bộ test cũ, đều pass không sửa).
  - Hai người thật, Network Simulator 3G, iPhone dọc và ngang, tay cầm, kiểm kiểu `--!strict` (không có luau-lsp/analyze).
- **Test thủ công** (để sau khi xong cả giai đoạn và publish, hai tài khoản thật): chơi trọn một ván Coop; cố tình thả đè nhau (khối bay về khay, không có cảnh báo resync trong Output); một bên rời giữa ván (người ở lại thấy "Partner left…", kéo được khối nhỏ, Game Over ghi điểm được tính); treo máy 45 giây rồi bấm Take over (người kia về menu); Play again cần cả hai, và nhìn thấy "<tên> wants to play again"; kéo một khối trên bảng và xem bóng hiện ở màn của người kia (theo ô, tắt khi thả hoặc khi người kia đặt, không kẹt lại khi mạng lag; nếu thấy rối mắt thì bỏ như plan cho phép: bỏ `DragController.onAim(onAim)` ở `CoopRunController.start`); bấm Menu khi Game Over và Leave run trong Pause; nhận lời mời khi đang chơi solo (ván solo kết thúc), khi đang ở màn Leaderboard/Support; chạy lại các ca solo của M6 (kéo thả chuột và cảm ứng, game over, revive, xoay, tutorial) vì bố cục khay đã đổi. Có thể thử một phần trong một cửa sổ Studio bằng `coopbot` khi Studio MCP chạy lại được.

## M22: Dữ liệu và leaderboard

### Dữ liệu người chơi

| Trường | Dùng cho | Mặc định |
|---|---|---|
| `coopBest` | Điểm Coop (đã chốt) cao nhất, với bất kỳ ai | 0 |
| `coopGamesPlayed` | Số ván Coop đã thua (hoặc bị chốt điểm) | 0 |

`Reconcile` tự điền nên version vẫn là 3. **Profile không lưu UserId của bạn chơi** (xem phần xóa dữ liệu).

- Kỷ lục solo (`bestScore`), mốc highscore và `gamesPlayed` **không** nhận điểm Coop: luật khác (4 khối, hai người).
- `coopBest` được cập nhật theo từng nước khi còn đủ hai người, như EXP của solo, nên không phụ thuộc thứ tự xử lý lúc người chơi rời.
- **EXP (AT):** mỗi người nhận `floor(điểm đội × COOP.EXP_SHARE / 10)` với `EXP_SHARE = 0,5`, cộng dần theo từng nước. Mốc level vẫn tính bình thường.

### Bảng Coop theo cặp (AS)

- `OrderedDataStore` `Coop` (`Coop_Dev` trong Studio), khóa bảng `Coop_all`. **Khóa mỗi dòng là cặp** `"<id nhỏ>_<id lớn>"` (tối đa 27 ký tự, giới hạn là 50), giá trị là điểm đã chốt cao nhất của cặp đó (số thuần, không gắn danh hiệu).
- **Ghi:** server ghi một lần cho cả cặp bằng `UpdateAsync` lấy giá trị lớn hơn, nên kỷ lục cũ của cặp không bị ghi đè dù server không nhớ nó. Ghi khi thua, khi một người rời, và mỗi phút nếu điểm đã chốt đổi; cách nhau ít nhất 20 giây như solo. Ngân sách ghi ordered (`30 + 5 × số người` mỗi phút) dư nhiều.
- **Đọc:** thêm một lần `GetSortedAsync` top 50 vào vòng đọc mỗi phút; tra tên cả hai người trong cùng lô `GetUserInfosByUserIdsAsync`.
- **Giao diện:** tab thứ ba **Co-op** cạnh Highscore / Level. Mỗi dòng: hạng, "A & B", điểm. Cuối màn: "Your co-op best: N" (từ `coopBest`). Bản đầu chỉ có All time (AX).
- `Leaderboards.pairKey(a, b)` và `pairIds(key)` (logic thuần, có test).

### Xóa dữ liệu theo yêu cầu

- Khóa theo cặp không tìm được bằng một UserId đơn lẻ, và `OrderedDataStore` không gắn được user id. Cách xử lý: `scripts/erase-user.luau` **quét cả store `Coop`** qua Open Cloud (mỗi trang 100 dòng) và xóa mọi khóa khớp `^<id>_` hoặc `_<id>$`.
- Vì profile không lưu UserId của bạn chơi, xóa một người không để sót dấu vết của họ trong dữ liệu của người khác.
- Hệ quả: dòng "A & B" biến mất cả với B khi A yêu cầu xóa. `coopBest` của B vẫn giữ (chỉ là một con số).
- **Giới hạn:** chi phí quét tăng theo số dòng của bảng (1.000 cặp = 10 request mỗi lần xóa). Khi bảng lên tới hàng chục nghìn cặp thì cần một chỉ mục riêng; ghi vào rủi ro.

### Analytics

- `RunScore`, `RunMoves`, `RunMaxCombo` thêm loại ván `coop`; cách kết thúc thêm `partner_left` và `takeover`. Ván solo bị bỏ để vào Coop ghi cách kết thúc `coop`.
- Funnel `CoopInvite` (1 Sent, 2 Accepted, 3 RunStarted, 4 RunFinished), phiên là id lời mời.
- Sự kiện `CoopConflict` (nước bị từ chối vì đè nhau) để biết xung đột có thường xảy ra không.

### Test

- Lune: `PlayerData` (trường mới), `Leaderboards` (khóa cặp không phụ thuộc thứ tự hai id, tách lại đúng), `Erasure` (id 12 không khớp `123_45` hay `45_312`), `Telemetry`.
- Studio: chơi ván Coop với `coopbot` rồi `boards` đọc lại từ `OrderedDataStore` thật; ván điểm thấp hơn không ghi đè; rời giữa ván thì bảng giữ điểm lúc rời.

### Kết quả M22

> **Lưu ý: chưa chạy trong Studio.** Studio MCP vẫn không kết nối được (`Server's protocol version is not supported`), nên chưa có lần ghi nào lên `OrderedDataStore` thật, chưa nhìn thấy tab Co-op và chưa gọi Open Cloud thật. Logic thuần có test; phần còn lại nằm ở mục "Chưa kiểm tra được" và "Test thủ công".

- **Dữ liệu người chơi:** `PlayerData` thêm `coopBest` (điểm Coop đã chốt cao nhất, với bất kỳ ai) và `coopGamesPlayed`, mặc định 0. `Reconcile` tự điền nên version vẫn là 3 (có test). **Profile không lưu UserId của bạn chơi.** Test cũ `starts new players at zero` ghim nguyên bảng mẫu nên mình thêm hai trường vào bảng đó; không test cũ nào khác phải sửa.
- **Điểm Coop tách khỏi solo:** `CoopProgress` (logic thuần) và `PlayerData.recordCoopScore/recordCoopGame`. Kỷ lục solo, mốc highscore, `gamesPlayed` và điểm tuần của bảng Highscore không nhận điểm Coop (có test).
- **EXP (AT):** `Progression.expForCoopScore(score) = floor(score × COOP.EXP_SHARE / EXP_SCORE_DIVISOR)` với `EXP_SHARE = 0,5`. Mỗi người còn trong ván nhận phần EXP tăng thêm sau **từng nước** theo điểm đội (kể cả người ở lại sau khi bạn chơi rời, như plan); không cộng hai lần cho cùng điểm. EXP đó cũng vào bảng Level tuần. Mốc level được nhận như solo (`RewardService.sync`).
- **`coopBest`:** nâng sau từng nước bằng **điểm đã chốt** (`countedScore`, đứng yên khi bạn chơi rời hoặc bị tiếp quản), nên không phụ thuộc thứ tự xử lý lúc người chơi rời. **`coopGamesPlayed`:** tăng một lần cho mỗi người mỗi ván, ở lúc xảy ra trước: hết nước đi, hoặc điểm bị chốt vì bạn chơi rời hay bị tiếp quản (và ván có ít nhất một nước).
- **Game Over Coop có EXP:** server gửi `CoopRewards(runId, rewards)` cho mỗi người còn trong ván lúc hết nước đi (cùng dạng `RunRewards` của solo); `Hud.showCoopGameOver` hiện thanh EXP, lên level và danh hiệu mới như màn solo, kể cả khi tin đến sau khi panel mở.
- **Bảng Coop theo cặp (AS):** `OrderedDataStore` `Coop` (`Coop_Dev` trong Studio), khóa bảng `Coop_all`; `Leaderboards.pairKey(a, b)` ("<id nhỏ>_<id lớn>", tối đa 27 ký tự, không phụ thuộc thứ tự, chịu được id âm của Studio) và `pairIds(key)`. Giá trị là điểm thuần, không gắn danh hiệu. `LeaderboardService`:
  - **Ghi:** nhớ điểm đã chốt cao nhất của từng cặp trong server (cập nhật sau mỗi nước, chỉ là tính toán); ghi bằng **`UpdateAsync` lấy giá trị lớn hơn** (trả `nil` khi kho đã có điểm cao hơn) nên kỷ lục cũ của cặp không bị ghi đè dù server không nhớ nó. Ghi khi hết nước đi, khi một người rời hoặc bị tiếp quản (cách nhau ít nhất 20 giây), mỗi lần đọc bảng (mỗi phút) nếu điểm đã chốt đổi, và khi server đóng; chỉ một lần cho cả cặp, không phải mỗi người một lần. Cặp đã ghi xong và không còn ai trong server thì bị quên.
  - **Đọc:** thêm một lần `GetSortedAsync` top 50 vào vòng đọc mỗi phút; tên của cả hai người nằm trong cùng lô `GetUserInfosByUserIdsAsync` với các bảng khác. Mỗi dòng: hạng, "A & B", điểm; snapshot thêm `you.coopBest`.
  - **Giao diện:** tab thứ ba **Co-op** cạnh Highscore / Level (hai tab thời gian một hàng, ba tab bảng một hàng; trên màn thấp cả năm chung một hàng). Bảng Coop chỉ có All time (AX): chọn nó thì tab "This week" mờ đi, và dòng cuối ghi "Your co-op best: N". Dòng của mình tô vàng nếu mình là một trong hai người.
- **Xóa dữ liệu theo yêu cầu:** `Erasure.pairKeyMatches(key, userId)` và `pairKeysFor(keys, userId)` so từng id nguyên ("12_45" và "45_12" khớp 12; "123_45" và "45_312" không). `scripts/erase-user.luau` liệt kê **cả store `Coop`** qua Open Cloud (mỗi trang 100 dòng), rồi xóa mọi dòng của người đó (dòng của cặp biến mất cho cả bạn chơi; `coopBest` của bạn chơi vẫn giữ). Kế hoạch xóa theo id (`Erasure.plan`, `orderedStoreNames`) **giữ nguyên**, store Coop nằm riêng (`Erasure.COOP_STORE`). `--dry-run` ghi thêm dòng quét này mà không gửi request. Chi phí quét tăng theo số dòng của bảng (1.000 cặp = 10 request mỗi lần xóa); khi lên hàng chục nghìn cặp thì cần chỉ mục riêng.
- **Analytics:** `RunScore`, `RunMoves`, `RunMaxCombo` có loại ván `coop` (điểm đội); cách kết thúc thêm `partner_left` (hết nước đi sau khi bạn chơi đã rời) và `takeover` (bị bạn chơi tiếp quản); `gameover` và `left` dùng như solo, ván solo bỏ để vào Coop ghi `coop` (từ M21). Hết nước đi Coop **không** làm tiến bước onboarding "GameOver". Funnel `CoopInvite` (1 Sent, 2 Accepted, 3 RunStarted, 4 RunFinished) ghi cho người mời, phiên là id lời mời (chơi lại ghi lại bước 3 và 4 trong cùng phiên). Sự kiện `CoopConflict` mỗi lần một nước bị từ chối.
- **Khác plan (nhỏ):** sự kiện `formed` của `Rooms` mang `inviteId` (cho funnel) và `RoomService.onRoomFormed` truyền nó cho người nghe; kết quả `CoopRuns` thêm `present` và `countedScore` cho mỗi nước, `summary` cho người rời hoặc bị tiếp quản; lệnh debug `data` in `coopBest` và `coopGames`, `resetdata` xóa chúng, `boards` in thêm bảng Coop và các cặp đang chờ ghi.
- **Test:** **273 pass** (thêm 20: `PlayerData` 2, `Leaderboards` 3, `Erasure` 3, `Telemetry` 4, `Rooms` 1, `CoopRuns` 2, `CoopProgress` 5). Gồm: khóa cặp không phụ thuộc thứ tự và tách lại đúng (kể cả id âm, khóa sai), id 12 không khớp `123_45` hay `45_312`, danh sách cửa hàng xóa theo id không đổi, EXP nửa phần và không cộng đôi, `coopBest` theo điểm đã chốt, đếm một ván một lần, Game Over Coop không thành bước onboarding. `stylua` sạch, `selene src` sạch; `lune run scripts/erase-user.luau <id> --dry-run` chạy.

- **Chưa kiểm tra được:**
  - **Mọi thứ cần Studio:** ghi và đọc `OrderedDataStore` thật (`UpdateAsync` giữ giá trị lớn hơn, trần ngân sách ghi), tab Co-op và dòng "Your co-op best" trên màn, thanh EXP ở Game Over Coop, `boards` sau một ván với `coopbot` (cặp "-7001_<id>" trong `Coop_Dev`).
  - **Open Cloud thật:** phần quét store Coop của `erase-user.luau` đọc phản hồi theo đúng tài liệu (`orderedDataStoreEntries` với `id`, và `nextPageToken`) nhưng mình không xác nhận được tên trường trong tài liệu và chưa có khóa để thử. Script in số dòng đã quét và cảnh báo khi một trang không có danh sách, để một lần quét "0 dòng" không bị tin mù quáng. Chạy `--dry-run`, rồi chạy trên tài khoản thử với một cặp có thật và kiểm dòng đã biến mất.
  - Analytics: sự kiện và funnel mới chưa được xem trên bảng điều khiển; kiểm kiểu `--!strict` (không có luau-lsp).
- **Giới hạn đã biết:** người chơi rớt mạng thì dữ liệu của họ có thể đã bị giải phóng trước khi sự kiện rời phòng tới, nên ván đó không được tính vào `coopGamesPlayed` của họ (EXP và `coopBest` đã cộng theo từng nước, không mất). Dòng của cặp hiện tên hiển thị của cả hai người (công khai như các bảng khác; người rời vẫn nằm trên dòng).
- **Test thủ công** (sau khi xong cả giai đoạn và publish): chơi một ván Coop với bạn thật rồi mở Leaderboard → Co-op và thấy "A & B" với điểm đã chơi; chơi ván điểm thấp hơn rồi xem dòng không bị hạ; một người rời giữa ván rồi xem dòng giữ điểm lúc rời và Game Over ghi điểm được tính; Game Over Coop hiện EXP, level up, danh hiệu; EXP của hai người cộng lại gần bằng một ván solo cùng điểm; mở Leaderboard khi chưa có dòng Coop nào; chạy `scripts/erase-user.luau` trên tài khoản thử đã chơi Coop và kiểm dòng cặp biến mất; xem funnel `CoopInvite` và sự kiện `CoopConflict` trên Analytics.

## M23: Xoay và hồi sinh trong Coop

Hướng đã chốt: AV (xoay) và AW (hồi sinh), xem bảng quyết định. Plan chi tiết:

### Xoay (AV)

- **Luật.** Mỗi người có `Config.FREE_ROTATIONS_PER_RUN` (1) lượt miễn phí mỗi ván, hết thì dùng lượt đã mua của chính mình (`data.rotations`). Chỉ xoay khối của mình; người ở lại xoay được cả khối của người đã rời, trả bằng ví của họ. Lượt đầu tiên của một khối tốn một lượt, sau đó khối xoay tự do tới khi đặt (như solo). Khối xoay đã mở khóa nên tính vào "còn nước đi hay không" (`hasPlacement` đã làm vậy).
- **`GameSession.rotateWith(slot, free, paid)`.** Xoay nhận "ví" từ ngoài (số lượt miễn phí và số lượt mua của người xoay) và không đụng bộ đếm của phiên. `rotate` cũ gọi nó rồi tự trừ `freeRotations`, nên solo và mọi test hiện có không đổi.
- **`CoopSession`.** Ví miễn phí theo chỗ ngồi (`freeRotations[seat]`, nằm trong snapshot); bộ đếm chung của `GameSession` đặt 0 trong Coop. `rotate(seat, slot, paidAvailable)` kiểm `mayPlace` rồi gọi `rotateWith`; `freeRotationsOf(seat)`; `revive()`.
- **Thứ tự sự kiện.** Xoay đổi khối nên bạn chơi cũng phải biết, nếu không nước đặt sau đó của người kia sẽ không khớp với bản của họ. Vì vậy `seq` của ván đổi nghĩa từ "số nước" thành "số sự kiện đã nhận" (nước đặt và lượt xoay), do `CoopRuns` đếm. Chưa có lượt xoay thì `seq` bằng số nước, nên test cũ không đổi. Server gửi `CoopEvent("turn", runId, seq, seat, moveId, slot, charged)` cho cả hai. **Nước đặt và lượt xoay đi chung một remote**, vì tài liệu Roblox chỉ bảo đảm thứ tự trong cùng một `RemoteEvent` (không bảo đảm giữa hai remote khác nhau, mình đã tra): một lượt xoay vượt mặt nước đặt trước nó sẽ làm bản của bạn chơi lệch. Vì thế `CoopMove` đổi tên thành `CoopEvent` với tham số đầu là loại sự kiện (`"move"` hoặc `"turn"`). Dù vậy, một sự kiện bị lỡ hay đảo vẫn bị phát hiện bằng `seq` và client xin lại trạng thái.
- **Giao thức.** Client gửi `CoopRotate(runId, moveId, slot)` (cùng bộ đếm `moveId` với `CoopPlace`). Server nhận thì gửi `CoopEvent("turn", …)` cho cả hai, từ chối thì `CoopReject(runId, moveId)` (dùng lại) kèm `Profile` mới (client có thể nhầm số lượt mua). Server tự quyết lượt miễn phí hay lượt mua; `charged` ("free", "paid" hoặc không có khi khối đã mở khóa) đi cùng sự kiện để client của bạn chơi dựng lại đúng, và nếu khác với bản của họ thì xin trạng thái.
- **Không làm hoãn "Take over".** Lượt xoay không đặt lại đồng hồ treo máy (chỉ nước đặt mới tính), nếu không một người cứ xoay mãi sẽ giữ chỗ vĩnh viễn.
- **Client.** `CoopSync` giữ cả lượt xoay chưa được xác nhận của mình trong `pending` (cùng thứ tự với nước đặt) và phát lại chúng khi nhận sự kiện của bạn chơi, nên khối xoay không bị nháy về hướng cũ. `GameController.tryRotate` dùng chung một đường cho solo và Coop (khối trong tay, mua gói khi hết lượt, `markTurned`); `Source` thêm `rotate` và `freeRotations`. Dòng dưới khay hiện "Rotate: 1 free · 2 owned" cùng dòng chờ bạn chơi.
- **Mua gói xoay trong Coop.** `RequestRotations` mở được khi người chơi đang ở một ván Coop chưa hết (hoặc ván solo thường chưa hết).

### Hồi sinh (AW)

- **Luật.** Ai trong hai người cũng bấm được, hồi sinh cho cả đội: xóa 4×4 giữa bàn, đặt lại combo, chia bộ 4 khối mới (`CoopSession.revive`). Lượt xoay miễn phí đã dùng không hồi lại. Giá theo `revivesUsed` của ván (như solo: bậc 1, 2, 3 rồi giữ bậc 3).
- **Lời mời cho cả hai.** Hết nước đi thì server gửi `ReviveOffer` cho mỗi người còn trong ván (dùng lại remote của solo): miễn phí nếu người đó có lượt hồi sinh đã mua, hoặc giá của lượt kế tiếp. Client chọn theo ván đang hiển thị, nên `GameController` đổi từ `runId`/`session` của solo sang `activeRunId()`/`current()`. Đổi trạng thái lúc hồi sinh đi qua `CoopState` với lý do "revive" (giống solo) gửi cho cả hai.
- **Ai trả trước thì dùng.** Người bấm mà không có lượt đã mua thì mở hộp thoại mua; khi biên nhận được ghi xong thì dùng lượt đó cho ván đang chờ. Nếu bạn chơi đã hồi sinh trước (ván không còn hết nước đi), lượt của người trả sau nằm lại trong dữ liệu của họ cho lần sau, đúng như hành vi hiện có. Không hoàn tiền được vì hộp thoại đã mở; chấp nhận, ghi trong "Giới hạn".
- **`PurchaseService` tra "người này đang ở ván nào".** Thêm `contextOf(player)` trả `{ kind = "coop"|"solo", runId, isOver, revives }` (Co-op trước, vì một người ở phòng Co-op không còn ván solo). Lời mời đang chờ giữ thêm `kind`; `Purchases.reviveApplies(context, kind, runId)` (logic thuần, có test) quyết định lượt vừa mua còn dùng được cho ván đó không, để runId của solo và Co-op (hai bộ đếm riêng) không bị nhầm.
- **Mỗi lần hết nước đi đều trả thưởng.** Ván Coop hồi sinh rồi hết nước đi lần nữa vẫn gửi `CoopRewards` (cộng dồn, như solo) và ghi lại dòng của cặp; chỉ `coopGamesPlayed`, funnel và log "gameover" tính một lần mỗi ván.
- **Analytics.** Funnel `CoopReviveOffer` (cùng 4 bước như `ReviveOffer`, session `c<runId>.<số lần hồi sinh>`) tách khỏi solo; `RotationUsed` ghi thêm trường thứ hai `coop`.

### Việc làm, theo thứ tự

1. `GameSession.rotateWith`, `CoopSession` (ví, `rotate`, `revive`, snapshot) và test.
2. `CoopRuns`: `seq` riêng, `rotate`, `revive`, `Summary.revives` và test.
3. `Purchases.reviveApplies`, `Telemetry.coopReviveStep`, `Net` (`CoopRotate`, và `CoopMove` thành `CoopEvent`).
4. `CoopService`, `PurchaseService`, `GameService` (các hàm ghi log).
5. `CoopSync` (lượt xoay trong `pending`, `applyTurn`), `CoopRunController`, `GameController`, `Hud`/`TrayView` nếu cần.
6. Lockstep có xoay và hồi sinh (thêm file test mới, không sửa test cũ), `stylua`, `selene`, thử trong Studio với `coopbot`.

### Kết quả M23

> **Đã chạy trong Studio một lượt với `coopbot` (một client).** Phần nhìn bằng mắt (ảnh chụp màn hình Play) và hai người thật nằm ở "Chưa kiểm tra được" và "Test thủ công".
>
> Đã thấy trong Studio: Rotate bằng lượt miễn phí (ví `1/1` thành `0/1`, `seq` tăng, server khớp client), `fakepurchase` gói xoay thành `rotations=5`, xoay bằng lượt đã mua (`rotations` 5 thành 4 ở cả server và client, dòng "Rotate: 4 owned"), khối của bạn chơi không xoay được; chơi tới hết nước đi: Game Over Coop hiện "Revive · R$ 10" kèm "Clears the center 4×4 for both of you"; `fakepurchase` revive rồi nút thành "Revive · Free / You have 1"; bấm Revive thì giữa bàn được xóa, chia bộ 4 khối mới, panel đóng, ván tiếp tục (`revives=1`); hết nước đi lần hai thì giá lên bậc 2 ("Revive · R$ 15"), điểm 137 và EXP cộng dồn, `coopBest=137`, `coopGames=1` (không tính hai lần), analytics chỉ ghi một lần `RunScore` và funnel `CoopReviveOffer` đủ bước Offered, Requested, Paid, Revived.

- **Xoay:** `GameSession.rotateWith(slot, free, paid)` (xoay nhận ví từ ngoài); `rotate` cũ gọi nó nên solo không đổi. `CoopSession` có ví miễn phí theo chỗ ngồi (`freeRotations`, trong snapshot), `rotate(seat, slot, paid)` kiểm `mayPlace`, `freeRotationsOf`, `revive`. Bộ đếm chung của `GameSession` đặt 0 trong Coop.
- **Thứ tự sự kiện:** `CoopRuns` có `seq` riêng đếm nước đặt và lượt xoay (bằng số nước khi chưa ai xoay); `rotate` và `revive` mới, `Summary.revives`, `peek` trả thêm `seq`. Lượt xoay **không** đặt lại đồng hồ treo máy. Remote `CoopMove` đổi tên `CoopEvent("move" | "turn", …)` vì Roblox chỉ bảo đảm thứ tự trong một remote (mình đã tra); thêm `CoopRotate`.
- **Server:** `CoopService.rotate` trừ lượt đã mua khỏi dữ liệu ngay (trước khi có thể bị dùng hai lần), gửi lượt xoay cho người còn trong ván, gửi `Profile`; lượt bị từ chối gửi lại `CoopReject` kèm `Profile`. `CoopService.revive`, `summaryOf`, `onGameOver`. **Mỗi lần hết nước đi đều trả thưởng** (hồi sinh rồi hết nữa vẫn gửi `CoopRewards` cộng dồn, ghi lại dòng của cặp); chỉ log "gameover", funnel `CoopInvite` bước 4 và `coopGamesPlayed` tính một lần mỗi ván.
- **Hồi sinh:** `PurchaseService` dùng `contextOf(player)` (Coop trước, rồi solo thường); lời mời đang chờ giữ `kind`; `Purchases.reviveApplies` quyết định lượt vừa mua còn dùng được không. Lời mời gửi cho cả hai người; ai được ghi biên nhận trước thì dùng, lượt của người sau nằm lại trong dữ liệu. Mua gói xoay cũng mở được trong Coop. Revive đổi trạng thái bằng `CoopState` với lý do `"revive"` cho cả hai.
- **Client:** `CoopSync` giữ lượt xoay chưa xác nhận trong `pending` (cùng thứ tự với nước đặt), `rotate`, `applyTurn`, `freeRotations`. `GameController.tryRotate` là một đường chung cho solo và Coop; nút Rotate chỉ hiện ở khối của mình; dòng dưới khay ghi "Rotate: 1 free · 2 owned" cùng dòng chờ bạn chơi; nút Revive và lời mời dùng ván đang hiển thị (`activeRunId`, `current`). Lệnh debug mới: `coop rotate [slot]`, `coop revive`; `describe` ghi thêm `seq`, ví miễn phí và số lần hồi sinh.
- **Analytics:** funnel `CoopReviveOffer` (session `c<runId>.<số lần hồi sinh>`), funnel `RotationOffer` dùng session `c<runId>` cho Coop, `RotationUsed` thêm trường thứ hai `coop`.
- **Test:** **309 pass** (thêm 36: `CoopTurns.spec` 35 và `CoopTurnsLockstep.spec` 1); **không test cũ nào bị sửa** (chỉ `tests/run.luau` thêm hai dòng). Gồm: `rotateWith` không đụng bộ đếm của phiên, mỗi người một lượt miễn phí, chỉ xoay khối của mình (hoặc của người đã rời), lượt đã mua, khối chỉ vừa khi xoay, revive xóa giữa bàn và giữ ví, `CoopRuns` đánh số lượt xoay như nước đặt, từ chối lượt sai, giới hạn 12/giây, xoay không hoãn "Take over", revive cho cả hai và cho người ở lại, ván hồi sinh hết nước lần nữa không tính hai lần, `CoopSync` (xoay tại chỗ, xác nhận, lượt của bạn chơi, lượt lệch phí thì xin trạng thái, lượt bị từ chối, xoay rồi đặt), `reviveApplies`, hai mục analytics. **Lockstep 200 ván** với tin nhắn trễ, hai người vừa đặt vừa xoay (có lượt mua), 201 lần hồi sinh, 40 người rời giữa chừng: 1.042 lượt xoay (256 lượt mua, 51 lượt bị từ chối), **0 lần resync**, hai client và server luôn khớp từng ô, cả ví lượt mua. `stylua` sạch, `selene src` sạch, 63 file `src` đều biên dịch được (không có luau-lsp nên chưa kiểm kiểu `--!strict`).
- **Chưa kiểm tra được:**
  - **Nhìn bằng mắt:** hình dạng nút Rotate ở khay Coop (chỉ đọc được qua `PlayerGui`, không chụp được màn hình Play), thanh EXP sau hồi sinh; phía bạn chơi nhìn thấy khối xoay, và lời mời Revive hiện ở **cả hai** client (chỉ có một client thật trong Studio, bot không nhận lời mời).
  - **Mua thật:** hộp thoại Robux cho revive và gói xoay trong Coop, hai người cùng bấm mua một lúc (lượt của người sau phải nằm lại trong dữ liệu), `ProcessReceipt` với một ván Coop. `fakepurchase` thử được phần cấp phát nhưng không thử được hộp thoại.
  - Thứ tự `CoopEvent` trên mạng thật (test mô phỏng thứ tự trong một remote); xem có resync lạ khi xoay nhanh.
- **Giới hạn đã biết:** hộp thoại mua đã mở không đóng được khi bạn chơi hồi sinh trước, người đó vẫn có thể trả Robux và lượt nằm lại trong dữ liệu cho lần sau (không tự hoàn tiền). `applyTurn` và `applyMove` có thể làm lớp đã xác nhận lệch một nhịp khi báo lệch, tới khi trạng thái đầy đủ về thay thế (client luôn xin lại trạng thái).
- **Test thủ công** (sau khi xong cả giai đoạn và publish): hai người chơi Coop, mỗi người xoay khối của mình bằng lượt miễn phí rồi thấy lượt xoay hiện ở khay của bạn chơi; hết lượt miễn phí bấm Rotate thì mở hộp thoại gói xoay, mua xong số lượt đã mua cập nhật; không xoay được khối của bạn chơi; hết nước đi thì cả hai thấy nút Revive và giá, một người trả thì cả hai tiếp tục chơi; cả hai cùng bấm mua một lúc thì chỉ một lần hồi sinh và lượt kia còn trong dữ liệu (dòng "You have N"); người ở lại hồi sinh được sau khi bạn chơi rời; hồi sinh rồi hết nước lần nữa thì Game Over cộng dồn EXP, bảng Coop giữ điểm cao hơn; xoay liên tục không làm nút Take over biến mất; xem funnel `CoopReviveOffer` và sự kiện `RotationUsed` có `coop` trên Analytics.

### Vẽ lại giao diện Co-op theo mockup Figma

Mockup: file ChikaBlocks-UI, trang Screens, mục "Co-op — PC 1280×720" (12 frame; chỉ có bản PC). Đã so từng màn với màn thật trong Studio (Play, `coopbot`) và sửa chỗ lệch:

- **Nút không bấm được** (`Clay.setEnabled`, token `ButtonDisabled*` trong `Theme`): mặt xanh nhạt, chữ và viền xám, thay cho nút hồng bị làm mờ. Dùng ở lobby, tab "This week" của Leaderboard và nút Play again khi đã bấm.
- **Lobby (`CoopView`):** hàng là thẻ trắng viền mảnh, nút to hơn; thẻ phòng màu tím nhạt, căn giữa; dòng "Waiting for X to answer…" khi lời mời đang chờ; trạng thái server vắng có mascot và nút Invite friends hồng ở giữa (xanh dưới danh sách khi có người); thẻ cao vừa nội dung.
- **Thẻ mời (`CoopInviteView`):** thanh đếm vàng nằm dưới tên người mời, nút to hơn.
- **Khay Co-op (`TrayView`):** thẻ bạn chơi vuông như các ô khay, viền và tên màu tím, viền vàng và "<tên> left" khi họ rời.
- **Game Over Co-op (`Hud`):** điểm từng người là một dòng chữ thường (không còn pill vương miện); nút luôn là "Play again", dòng bên dưới ghi "X wants to play again" hoặc "Waiting for X…" (nút chuyển xanh nhạt sau khi bấm).
- **Pause Co-op:** thêm dòng "The board keeps going while you are here."
- **Leaderboard tab Co-op:** "All time" không tô hồng, "This week" xanh nhạt, tên cặp căn giữa hàng.

Đã chụp lại và khớp: lobby (có người, trong phòng), khay Co-op, Game Over, Pause, Leaderboard tab Co-op. **Chưa so được** vì gói Figma Starter hết lượt gọi công cụ: Waiting + Take over, Partner left, Lobby khi đang mời / khi trống, thẻ mời, Main Menu (đã xem nhưng chưa so từng pixel). Thanh EXP ở Game Over để nguyên vì dùng chung với màn solo (mockup Co-op vẽ thành một hàng "Lv 7 [thanh] +120 EXP"). Mockup chỉ có bản PC: bản điện thoại dọc chưa kiểm.

## Bảo mật

- Mọi remote: giới hạn tần suất → kiểm kiểu từng tham số → kiểm luật → mới làm. Client chỉ gửi ý định (mời ai, đặt ô nào), không gửi kết quả.
- Quyền đặt theo chỗ ngồi do server kiểm; client không đặt hộ được trừ khi server đã `release` chỗ kia.
- Đồng hồ treo máy và hạn lời mời tính ở server.
- Leo bảng Coop bằng nick phụ rồi chơi một mình: bị chặn vì điểm chốt lúc người kia rời hoặc bị tiếp quản. Một người điều khiển hai tài khoản cùng lúc thì vẫn phải chơi thật cả hai bên; chấp nhận.
- Bộ khối sắp tới vẫn không ai biết trước (seed ở server).

## Rủi ro

| Rủi ro | Cách xử lý |
|---|---|
| Tách `GameController` làm hỏng solo | Lockstep solo và toàn bộ test hiện có phải pass không sửa; chạy lại danh sách thử Studio của M6 cho solo |
| Thả đè nhau gây khó chịu khi ping cao | Khối bay về khay rõ ràng; bóng khối của bạn chơi (BA); đo bằng `CoopConflict` |
| Server chỉ có một người | Nút Invite friends; Coop là lý do để rủ bạn |
| Kiểm tra `WholeSet` 4 khối chậm | Đo ở M20; trần riêng cho Coop nếu cần |
| Không thử được 2 client qua Studio MCP | `coopbot` cho phần tự động; các bước cần 2 cửa sổ thật mình sẽ nhờ bạn bấm ở một bên nếu MCP không điều khiển được cả hai |
| Phá đám (cố tình đặt bừa, treo máy) | Tiếp quản sau 45 giây; rời phòng không mất gì |
| Quét bảng Coop khi xóa dữ liệu chậm dần | Đủ dùng tới hàng nghìn cặp; sau đó thêm chỉ mục |

## Bạn cần làm

1. Khi có mockup Figma cho màn Co-op, thông báo mời và khay 2 người thì gửi để vẽ lại; trước đó làm gray-box (AZ).
2. Sau M21: thử với hai tài khoản thật trên hai thiết bị (Studio chỉ giả lập được trên một máy).

## Quyết định đã chốt

| Điểm | Câu hỏi | Quyết định |
|---|---|---|
| **AP.** Luật PVP (câu hỏi mở số 6) | Đua điểm hay tấn công bằng khối rác? | ✅ **Chưa chốt.** GĐ5 chỉ dựng phần dùng chung chắc chắn (`Rooms`: lời mời, phòng, rời phòng), không đoán luật PVP. |
| **AQ.** Một người rời giữa ván | Chơi tiếp hay kết thúc? | ✅ **Chốt:** người ở lại chơi tiếp một mình với cả 4 khối; điểm Coop chốt tại lúc người kia rời. |
| **AR.** Lượt đặt | Tự do hay luân phiên? | ✅ **Chốt:** tự do, cùng lúc; server nhận nước tới trước, nước đè lên bị trả về khay. |
| **AS.** Bảng Coop | Theo người hay theo cặp? | ✅ **Chốt:** theo cặp ("A & B"). Xóa dữ liệu bằng cách quét bảng (xem M22). |
| **AT.** EXP trong Coop | Mỗi người nhận bao nhiêu? | ✅ **Chốt:** 50% điểm đội cho mỗi người (tổng EXP phát ra bằng một ván solo cùng điểm). Đã cân nhắc và bỏ: theo đóng góp riêng (dễ thành tranh nhau xóa hàng), 100% (Coop thành cách cày level nhanh gấp đôi). |
| **AU.** Treo máy | Có cho tiếp quản không, sau bao lâu? | ✅ **Chốt:** có, sau 45 giây bạn chơi im lặng trong khi mình hết nước. |
| **AV.** Xoay trong Coop (M23) | Lượt xoay tính thế nào? | ✅ **Chốt:** mỗi người 1 lượt miễn phí mỗi ván + lượt đã mua của mình, chỉ xoay khối của mình. |
| **AW.** Hồi sinh trong Coop (M23) | Ai trả? | ✅ **Chốt:** ai cũng mua được, hồi sinh cho cả đội; giá theo số lần hồi sinh của ván. |
| **AX.** Bảng Coop theo tuần | Có tab This week không? | ✅ **Chốt:** bản đầu chỉ All time. Thêm theo tuần thì mỗi tuần thêm một store phải quét khi xóa dữ liệu. |
| **AY.** Mời người đang chơi solo | Cho mời không? | ✅ **Chốt:** cho mời, bằng thông báo nhỏ không che bảng; nhận lời thì ván solo kết thúc. |
| **AZ.** Giao diện | Gray-box hay chờ mockup? | ✅ **Chốt:** gray-box theo `Theme`/`Clay` hiện có, vẽ lại khi có mockup (như GĐ3). |
| **BA.** Bóng khối của bạn chơi | Có hiện bạn chơi đang nhắm ô nào không? | ✅ **Chốt:** có, làm cuối M21; bỏ được nếu thấy rối mắt. |
