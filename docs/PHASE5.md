# Giai đoạn 5: Coop 2 người

> Plan đã duyệt, chưa code. Mọi điểm AP đến BA đã chốt, xem [cuối file](#quyết-định-đã-chốt).

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
