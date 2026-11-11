# Giai đoạn 5: Coop 2 người

> Plan đã duyệt. Mọi điểm AP đến BA đã chốt, xem [cuối file](#quyết-định-đã-chốt). Đã làm: M19 (xem [Kết quả M19](#kết-quả-m19)) và M20 (xem [Kết quả M20](#kết-quả-m20)); M21–M23 chưa code.

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
  │ ◀──── CoopMove(runId, seq, seat, moveId, slot, x, y, score, set?, isOver)
  │                                               không hợp lệ (bạn chơi đã chiếm ô): chỉ gửi người đặt
  │ ◀──── CoopReject(runId, moveId) ────────────  khối quay về khay
  │
  │ CoopRequestState() ────────────────────────▶  thấy lệch (seq nhảy cóc, điểm khác, quá 2 giây chưa xác nhận)
  │ ◀──── CoopState(state, "resync" | "takeover")
```

- **Server xếp thứ tự.** Mỗi nước được nhận mang một số `seq` tăng dần của cả ván. `moveId` là bộ đếm riêng của từng client, chỉ để client nhận ra nước của mình.
- **Client giữ hai lớp (`CoopSync`):**
  - *Đã xác nhận*: `CoopSession` dựng từ `CoopState`, chỉ áp các `CoopMove` theo đúng `seq`.
  - *Đang chờ*: các nước của mình đã gửi mà chưa được xác nhận (thường 0 hoặc 1 nước).
  - Thứ hiện trên màn hình = đã xác nhận + áp lại các nước đang chờ. Khi nước của bạn chơi tới, client áp vào lớp đã xác nhận rồi dựng lại; nước đang chờ nào không còn vừa thì bỏ ngay (khối bay về khay), không đợi `CoopReject`.
- Điểm và combo do server tính. Client so điểm của lớp đã xác nhận với `score` trong `CoopMove`; lệch thì xin lại trạng thái.
- Bộ khối mới đi kèm `CoopMove` của nước thứ 4 (`set` = 4 id). Seed không rời server, như solo.
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

## M23: Xoay và hồi sinh trong Coop (phác thảo)

Plan chi tiết viết khi tới mốc này; hướng đã chốt:

- **Xoay (AV):** mỗi người có 1 lượt miễn phí mỗi ván và dùng lượt đã mua của chính mình, chỉ xoay khối của mình. `GameSession.rotate` cần nhận "ví" lượt xoay từ ngoài vào thay vì giữ một bộ đếm chung.
- **Hồi sinh (AW):** ai trong hai người cũng mua được, hồi sinh cho cả đội; giá theo số lần hồi sinh của ván. Lời mời hồi sinh hiện cho cả hai; ai trả trước thì dùng, lượt của người trả sau nằm lại trong dữ liệu của họ (như hành vi hiện có). `PurchaseService` cần một chỗ tra "người này đang ở ván nào" chung cho solo và Coop.

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
