# Giai đoạn 3: Giữ chân người chơi và kiếm tiền

> Plan đã duyệt; M12, M13, M14 và M15 xong. Các điểm cần bạn quyết định cho các mốc sau nằm ở [cuối file](#quyết-định-cần-chốt).

## Bối cảnh

- GĐ2 còn 3 mốc, đều đang chờ bạn:
  - **M8** hồi sinh bằng Robux: chờ giá, chọn Group hay tài khoản cá nhân, và tạo Developer Product.
  - **M10** giao diện thật: chờ mockup và linh vật.
  - **M11** publish thử: làm sau M10.
- Phần lớn GĐ3 không phụ thuộc mockup, nên làm được ngay trong lúc chờ. UI của GĐ3 vẫn là gray-box, M10 sẽ vẽ lại cùng lúc với phần còn lại.
- Mọi thứ liên quan tới Robux (xoay khối, donate) dùng chung hạ tầng mua hàng của M8, nên **M8 phải xong trước**.
- Rewarded video ad chỉ bật được khi game đã public và có **≥ 2.000 người chơi mỗi tháng** (người tạo game phải từ 13 tuổi và đã xác minh danh tính). Mốc này để cuối, làm khi đủ điều kiện.

## Các mốc

| Mốc | Nội dung | Cần trước | Làm được ngay? |
|---|---|---|---|
| **M12** Analytics | Funnel tutorial, các sự kiện ván chơi qua `AnalyticsService` | Không | ✅ Xong |
| **M13** Level và EXP | EXP sau mỗi ván, level, quà theo mốc highscore và mốc level | Quyết định W, X | ✅ Xong (badge chờ ID) |
| **M14** Leaderboard | Highscore và Level (toàn thời gian và theo tuần) | Quyết định Y | ✅ Xong |
| **M8** Hồi sinh (của GĐ2) | `PurchaseService`, `ProcessReceipt` không cấp trùng | Giá, Group/cá nhân, tạo product | ✅ Xong (dùng lại cho M15, M16) |
| **M15** Xoay khối | 1 lượt miễn phí mỗi ván, mua thêm bằng Robux | M8, quyết định Z, AM, AN, AO | ✅ Xong (chờ thử giao dịch thật khi publish) |
| **M16** Donate | Nhiều mức Developer Product, bảng "Supporters" | M8, M14, quyết định AA | ⏳ |
| **M17** Rewarded video ad | Xem quảng cáo đổi 1 lần hồi sinh hoặc 1 lượt xoay | Game public, ≥ 2k người/tháng | ⏳ sau publish |

**Thứ tự đề xuất:** M12 → M13 → M14 làm ngay. Khi bạn chốt xong giá và Group thì làm M8 → M15 → M16. M10/M11 chen vào khi có mockup. M17 làm sau khi publish và đủ điều kiện.

M12 nên có trước khi publish (M11) để đo được ngay từ những người chơi đầu tiên.

## Dữ liệu người chơi

M12 đã nâng profile lên `version = 2` (thêm `onboardingStep`). Các mốc sau thêm trường mới; trường nào cần suy ra từ dữ liệu cũ thì thêm một bước migrate, còn lại `Reconcile` của ProfileStore tự điền mặc định:

| Trường | Dùng cho | Mặc định |
|---|---|---|
| `onboardingStep` | M12: bước funnel cuối cùng đã log (✅ đã có) | 0; profile cũ đã chơi hết ít nhất 1 ván thì 6, mới xong tutorial thì 3 |
| `exp`, `level` | M13 (✅ đã có) | 0, 1 |
| `milestonesClaimed` | M13: các mốc (highscore và level) đã nhận quà (✅ đã có) | `{}` |
| `badgesAwarded` | M13: các mốc đã trao badge xong (✅ đã có) | `{}` |
| `weekly` | M14: tuần ISO, điểm cao nhất và EXP kiếm được trong tuần (✅ đã có) | `{ week = "", bestScore = 0, exp = 0 }` |
| `rotations` | M15: lượt xoay đã mua, chưa dùng | 0 |
| `robuxDonated` | M16: tổng Robux đã donate (lấy `CurrencySpent` từ receipt) | 0 |
| `purchaseIds` | M8/M15/M16: các `PurchaseId` đã xử lý, giữ 100 cái gần nhất | `{}` |

## M12: Analytics

- **`AnalyticsService` chỉ gọi từ server**, gom trong một module `Analytics`. Tên sự kiện và giá trị trường tùy chỉnh ít biến thể (không dùng UserId hay chữ tự do).
- **Funnel lần đầu chơi** (`LogOnboardingFunnelStepEvent`, chỉ tính lần đầu):
  1. Vào game, thấy menu
  2. Bắt đầu ván tutorial
  3. Đặt nước đầu tiên
  4. Xóa hàng đầu tiên
  5. Thua ván đầu tiên
  6. Bắt đầu ván thứ hai
- **Sự kiện tùy chỉnh** (`LogCustomEvent`): điểm cuối ván, số nước mỗi ván, combo cao nhất, ván bị bỏ giữa chừng.
- **Kiếm tiền** (từ M8): funnel "mời hồi sinh → bấm → mua xong" để đo tỉ lệ chuyển đổi.
- Server cần biết khi nào client thấy menu: thêm một remote nhẹ `ClientReady`, có giới hạn tần suất. Các bước còn lại server đã tự biết.
- **Test:** Lune test với `AnalyticsService` giả (kiểm tra thứ tự bước, mỗi bước chỉ log một lần). Trong Studio, kiểm tra không có lỗi. Dashboard trong Creator Hub chỉ có số liệu khi game đã publish.

### Kết quả M12

- **Thiết kế thực tế:**
  - `Telemetry` (`src/server/Telemetry.luau`, logic thuần) quyết định log gì; `GameService` truyền vào một sink gọi `AnalyticsService` (bọc `pcall`, lỗi chỉ cảnh báo trong Studio).
  - Một bước funnel chỉ được log ngay sau bước trước nó, nên không bao giờ nhảy bước. Vì vậy các bước được đặt tên theo trạng thái (`MovePlaced`, `LineCleared`, `GameOver`, `NextRunStarted`) chứ không phải "lần đầu": người chơi thua trước khi xóa được hàng thì bước 4 và 5 được tính ở ván sau.
  - Mỗi ván kết thúc log `RunScore`, `RunMoves`, `RunMaxCombo`, chia theo `CustomField01` = loại ván (`tutorial`/`normal`) và `CustomField02` = cách kết thúc (`gameover`/`left`/`restart`). Ván bị mở lại khi chưa có nước nào thì không tính là `restart` (đó là `StartGame` được gửi lại).
  - `GameRuns`: kết quả nước đi có thêm `linesCleared`; thêm `summary()` (điểm, số nước, combo cao nhất, đã thua chưa).
  - Remote mới `ClientReady` (client gửi khi menu hiện lần đầu, giới hạn 1 lần mỗi 5 giây).
  - Debug server: lệnh `events` (50 sự kiện gần nhất, chạy được cả khi người chơi đã rời); `resetdata` đưa cả `onboardingStep` về 0.
- **108 test pass** (thêm 13: `Telemetry`, migrate profile v1 → v2, tóm tắt ván trong `GameRuns`).

| Kiểm tra trong Studio | Kết quả |
|---|---|
| Profile cũ (2 ván) vào game | Lên `version=2`, `onboardingStep=6`; không log bước funnel nào |
| `resetdata` rồi vào lại game | Bước 1 `MenuShown` khi menu hiện |
| Bấm Play, kéo khối theo gợi ý | Bước 2 `RunStarted`, 3 `MovePlaced`, 4 `LineCleared` |
| Chơi tới thua, bấm Play again | Bước 5 `GameOver`, 3 số của ván (46 điểm, 11 nước, combo 1, `tutorial,gameover`), bước 6 `NextRunStarted` |
| Mở ván mới giữa chừng (sau 3 nước) | `RunScore=11`, `RunMoves=3` với `normal,restart` |
| Rời game giữa ván (kick, sau 4 nước) | `RunScore=28`, `RunMoves=4` với `normal,left` |
| Output | `AnalyticsService: ... event fired` cho mọi sự kiện; không có lỗi |

- **Chưa kiểm tra được:** số liệu trên dashboard của Creator Hub (chỉ có khi game đã publish). Funnel "mời hồi sinh → mua" làm cùng M8.

## M13: Level, EXP và quà theo mốc

- **`Progression`** (shared, logic thuần, test bằng Lune): EXP nhận được từ điểm ván, EXP cần để lên level, các mốc highscore. Số liệu nằm trong `Config`.
- **Server tính EXP** từ điểm do chính server tính, cộng vào profile khi ván kết thúc (kể cả ván bỏ giữa chừng thì tính theo điểm lúc rời).
- **Màn Game Over:** thêm thanh EXP chạy lên và dòng "Level up!" nếu lên level. Menu hiện level hiện tại.
- **Quà theo mốc** (quyết định W): mốc highscore và mốc level nằm chung một bảng `Milestones` trong `Config`. Mỗi mốc gồm id, loại (`score` hoặc `level`), ngưỡng và phần thưởng `{ title, badge, cosmetic }`. Ô `cosmetic` để trống tới GĐ4.

| Loại | Mốc ví dụ | Danh hiệu ví dụ |
|---|---|---|
| Highscore | 1.000 / 5.000 / 10.000 / 25.000 | Block Rookie / Line Clearer / Combo Master / Grid Legend |
| Level | 5 / 10 / 20 / 30 / 50 | Regular / Puzzler / Block Smith / Veteran / Block Master |

  - **Server cấp quà** khi best hoặc level tăng, và kiểm tra lại mỗi lần người chơi vào game. Quà được suy ra từ best và level đã lưu, nên mốc hoặc phần thưởng thêm sau này (vd. cosmetic ở GĐ4) tự được cấp cho người đã đạt mốc từ trước, không ai bị thiệt.
  - **Danh hiệu là cosmetic title** chỉ kiếm được bằng thành tích, không bán. Mặc định hiện danh hiệu xếp cao nhất người chơi đang có (thứ tự xếp trong bảng, xen kẽ hai loại). Cho người chơi tự chọn danh hiệu để tới GĐ4, làm cùng cửa hàng cosmetic.
  - **Badge:** mỗi mốc một badge (9 badge theo bảng trên). Bạn tạo badge trong Creator Hub rồi gửi ID cho mình. Chưa có ID thì game vẫn chạy, chỉ bỏ qua bước trao badge. Server dùng `BadgeService:AwardBadgeAsync` (bọc `pcall`). Lần trao lỗi sẽ được thử lại ở lần vào game sau.
  - **Màn Game Over:** hiện "New title unlocked!" khi vừa đạt mốc.
- **Test:** EXP và level ở các ngưỡng; mỗi mốc chỉ cấp quà một lần; mốc thêm sau được cấp bù cho người đã đạt; chọn đúng danh hiệu cao nhất; trao badge lỗi thì lần sau thử lại.

### Kết quả M13

- **Thiết kế thực tế:**
  - `Progression` (`src/shared/Progression.luau`, logic thuần, dùng chung hai phía): EXP theo điểm, EXP cần cho mỗi level, nhận mốc, danh hiệu đang hiện, badge còn nợ. Số liệu và bảng 9 mốc nằm trong `Config` (`EXP_SCORE_DIVISOR`, `LEVEL_EXP_BASE`, `LEVEL_EXP_STEP`, `MILESTONES`).
  - **EXP được cộng dần theo từng nước** (theo điểm server tính), không đợi hết ván. Nhờ vậy ván bỏ giữa chừng hay bị mở lại vẫn được tính đủ, mà không phụ thuộc thứ tự xử lý khi người chơi rời game.
  - `RewardService`: nhận mốc mới mỗi khi điểm hoặc level tăng, và mỗi lần người chơi vào game (cấp bù mốc thêm sau). Badge được trao ở luồng riêng, kiểm tra `UserHasBadgeAsync` trước; lỗi thì để lần sau thử lại. Hiện cả 9 mốc có `badgeId = 0` nên chưa trao badge nào.
  - Remote mới `RunRewards(runId, rewards)` gửi khi thua: EXP nhận được, level trước và sau, danh hiệu mở trong ván. `Profile` có thêm `level`, `exp`, `title`.
  - Profile giữ `version = 2`. Các trường mới đều có mặc định hợp lý cho người chơi cũ, nên `Reconcile` tự điền, không cần migrate.
  - Menu hiện "Level N · Danh hiệu". Màn Game Over có thanh EXP chạy (đầy rồi chạy lại khi lên level), "Level up!" và "New title: …". Bảng tự thu nhỏ (`UIScale`) khi màn hình không đủ cao.
  - Debug server: `data` hiện level, EXP, mốc, badge, danh hiệu; thêm `addexp` và `setbest`; `resetdata` xóa cả tiến trình.
- **117 test pass** (thêm 9 test cho `Progression`, cập nhật test template `PlayerData`).

| Kiểm tra trong Studio | Kết quả |
|---|---|
| Profile cũ vào game | Được điền level 1, 0 EXP; menu hiện "Level 1" |
| Ván 997 điểm | +99 EXP, thanh EXP 99%; chưa đạt mốc 1.000 |
| Ván 2.094 điểm | Lên level 3, thanh EXP 45,5% (91/200, khớp server); "New title: Block Rookie" |
| `addexp 500` | Lên level 5, nhận mốc `level5`; menu đổi sang "Level 5 · Regular" (xếp cao hơn Block Rookie) |
| Vào lại game | Level 5 · Regular vẫn còn |
| iPhone 17 Pro ngang, Game Over có lên level và danh hiệu mới | Bảng thu nhỏ còn 78%, nằm trọn trong màn hình |
| Output | Không có lỗi |

- **Chưa kiểm tra được:** trao badge thật (cần bạn tạo 9 badge trong Creator Hub và gửi ID để điền vào `Config.MILESTONES`).
- **Lưu ý:** khi bảng Game Over thu nhỏ trên điện thoại ngang, nút cao khoảng 40 pt, hơi dưới mức 44 pt khuyến nghị. M10 sẽ dàn lại bảng này theo mockup.
- **Sửa lại con số ở quyết định X:** lúc đề xuất mình tính sai. Với công thức đã chốt, 10 ván 1.000 điểm lên level 6; 10 ván 3.000 điểm lên level 10 (không phải 5–6 như đã ghi). Xem quyết định X bên dưới.

## M14: Leaderboard

- **`OrderedDataStore`** (chỉ lưu số nguyên), server ghi:
  - `Highscore`: ghi khi kết thúc ván có kỷ lục mới.
  - `Level`: ghi khi lên level.
  - Theo tuần: tên store kèm tuần (vd. `Highscore_2026W45`), tự reset mỗi tuần.
- **Đọc:** mỗi server một vòng lặp lấy top 50 mỗi 60 giây, lưu cache, gửi cho client khi mở bảng. Client không bao giờ đọc DataStore.
- **Ngân sách:** ghi ordered tối đa `30 + 5 × số người chơi` lần/phút mỗi server. Chỉ ghi khi có kỷ lục mới nên dư rất nhiều.
- **Giao diện:** một màn "Leaderboard" mở từ menu, có tab All time / This week và tab Highscore / Level. Xem quyết định Y.
- Studio dùng store riêng (đuôi `_Dev`) như M7, để không lẫn với game thật.
- **Test:** logic chọn tên store theo tuần và gộp top (Lune); trong Studio, chơi vài ván rồi xem bảng.

### Kết quả M14

- **Thiết kế thực tế:**
  - `Leaderboards` (`src/server/Leaderboards.luau`, logic thuần): 4 bảng `Highscore_all`, `Highscore_week`, `Level_all`, `Level_week`. Tuần theo chuẩn ISO (bắt đầu 0h thứ Hai, giờ UTC); store tuần mang tên tuần (vd. `Highscore_2026W45`), nên sang tuần mới là bảng trống. Studio dùng store đuôi `_Dev`.
  - **Tab "This week" của bảng Level xếp theo EXP kiếm được trong tuần**, vì bản thân level không reset theo tuần.
  - **Danh hiệu lưu chung với điểm:** giá trị = chỉ số × 100 + vị trí danh hiệu (`Progression.titleIndex`). Nhờ vậy bảng hiện được danh hiệu mà không phải đọc profile của từng người, và thứ tự vẫn xếp theo điểm (thêm 1 điểm luôn hơn mọi danh hiệu).
  - `LeaderboardService`: chỉ ghi bảng có thay đổi; ghi sau mỗi lần thua, khi người chơi rời game, và mỗi phút trong lúc chơi. Mỗi phút đọc top 50 của cả 4 bảng, tra tên hiển thị theo lô (`UserService:GetUserInfosByUserIdsAsync`), lưu cache để gửi cho client. Bảng không đọc được thì giữ bản cũ. Không ghi bảng mà người chơi chưa có gì (điểm 0, level 1).
  - Remote mới `RequestLeaderboard` (giới hạn 1 lần mỗi 2 giây) và `Leaderboard(snapshot)`: 4 bảng cùng giá trị của chính người chơi.
  - `LeaderboardView` (gray-box, M10 vẽ lại theo mockup) mở từ nút "Leaderboard" mới trên menu. Có tab All time / This week và Highscore / Level, mỗi dòng gồm hạng, tên, danh hiệu, giá trị; cuối màn là giá trị của chính bạn. Đóng bằng Back, Backspace hoặc nút B tay cầm. Màn thấp (điện thoại ngang) thì ẩn tiêu đề và gom 4 tab vào một hàng.
  - Debug: server có lệnh `boards` (ghi, đọc lại ngay, in 4 bảng); client có lệnh `leaderboard [open|close]`.
- **123 test pass** (thêm 6 test cho `Leaderboards`: tuần ISO qua năm mới, tên store, mã hóa, thống kê tuần, chỉ ghi khi đổi).

| Kiểm tra trong Studio | Kết quả |
|---|---|
| Chơi một ván (802 điểm) rồi `boards` | Ghi và đọc lại đủ 4 bảng từ `OrderedDataStore` thật: highscore 1.344, highscore tuần 802, level 3, EXP tuần 80, kèm "Block Rookie" |
| Bấm nút Leaderboard trên menu (PC) | Mở màn, hiện #1 với tên, danh hiệu, 1.344; "Your best: 1344" |
| Bấm "This week" rồi "Level" | Hiện 80 EXP; "Your EXP this week: 80" |
| Back, Backspace | Đóng màn, về menu; Enter trên menu vẫn bắt đầu ván |
| iPhone 17 Pro ngang | Lần đầu danh sách chỉ thấy 1–2 dòng; đã sửa thành dạng gọn (4 tab một hàng, ẩn tiêu đề), thấy khoảng 5 dòng |
| Output | Không có lỗi |

- **Chưa kiểm tra được:** nhiều người chơi trên cùng bảng (Studio chỉ có một tài khoản), và lúc chuyển tuần thật. Logic chuyển tuần đã có test.
- **Giới hạn:** `OrderedDataStore` không cho tra thứ hạng của một người cụ thể, nên ngoài top 50 chỉ hiện giá trị của bạn, không hiện hạng.

## M15: Xoay khối

Các quyết định đã chốt: **AM** game over giữ nguyên (xoay không cứu ván), **AN** mỗi khối tốn một lượt (khối đó xoay tự do tới khi đặt xuống), **AO** một gói **5 lượt, 25 R$**, lượt mua được giữ cho các ván sau (quyết định Z).

### Cách chơi

- Mỗi ván có **1 lượt xoay miễn phí**, hết thì dùng lượt đã mua (`rotations` trong profile). Hết cả hai thì bấm xoay sẽ mời mua gói 5 lượt.
- Xoay một khối trong khay lần đầu tốn 1 lượt. Sau đó khối ấy xoay thoải mái (mỗi lần 90° theo chiều kim đồng hồ) cho tới khi đặt xuống. Khối đối xứng (chấm, vuông 2×2 và 3×3) không xoay được nên không có nút xoay, không tốn lượt.
- Xoay không đổi bộ khối kế tiếp và không đổi điểm; không làm đổi số nước (`moveCount`) nên không ảnh hưởng thống kê ván.
- Game over giữ nguyên: hết chỗ đặt khối nào trong khay thì thua, dù xoay có thể đặt vừa. Nút Revive vì vậy vẫn có giá trị.
- Không có trong tutorial và trong ván xem trước (chỉ ván thường).

### Thiết kế

- **`Pieces.rotateCW(piece)`:** tìm khối cùng hình sau khi xoay trong bảng `Pieces` (đủ cả 4 hướng cho mọi khối, kiểm bằng test). Khối đối xứng trả về chính nó, kèm `Pieces.canRotate`.
- **`GameSession:rotate(slot, paidAvailable)`:** kiểm tra hợp lệ như `place` (chưa thua, đúng ô còn khối). Ô đã mở khoá thì xoay miễn phí; chưa thì cần lượt miễn phí còn lại hoặc `paidAvailable > 0`, trả `{ slot, piece, charged = "free" | "paid" | nil }`. Snapshot thêm `freeRotations` và các ô đã mở khoá; mở khoá được xoá khi khối được đặt, khi chia bộ mới và khi hồi sinh.
- **`GameRuns.rotate` và `Net.RotatePiece(runId, moveIndex, slot)`:** server kiểm `runId`, `moveIndex == moveCount` (xoay xảy ra giữa hai nước), giới hạn tần suất; trừ `rotations` khi `charged == "paid"`. Sai thì gửi lại toàn bộ state (resync) như nước đi sai. Client dự đoán ngay, như với `PlacePiece`.
- **`Net.RequestRotations`:** client bấm xoay khi hết lượt thì server mở hộp mua của Roblox với product xoay (qua `PurchaseService`). Mua xong cộng 5 lượt, chờ lưu xong rồi gửi lại `Profile` (có `rotations`). Cấp theo `PurchaseId` như hồi sinh: không cấp trùng.
- **`Purchases.process`** được tổng quát hoá: mỗi product có một hàm cấp riêng (hồi sinh theo mức giá, xoay cộng 5 lượt) thay vì chỉ hồi sinh.
- **Dữ liệu:** thêm `rotations` (mặc định 0). `Reconcile` tự điền nên version vẫn là 3.
- **`Config`:** `ROTATION_PRODUCT`, `ROTATION_PACK = 5`, `FREE_ROTATIONS_PER_RUN = 1`. Giá lấy từ `GetProductInfoAsync`, không ghi cứng.
- **Analytics:** funnel `RotationOffer` (1 hết lượt và được mời, 2 bấm mua, 3 mua xong) và sự kiện `RotationUsed` (free / paid).

### Giao diện (gray-box theo style hiện tại; mockup chưa có nút xoay)

- Nút xoay tròn nhỏ ở góc mỗi ô khay (chạm và chuột), chỉ hiện với khối xoay được. Một nhãn "×N" cho số lượt đã mua, và "Free" khi còn lượt miễn phí.
- Phím **R** xoay ô đang chọn, nút **Y** trên tay cầm. Xoay khi đang kéo thì chưa hỗ trợ (bản này).
- Hết lượt mà bấm xoay: nút chuyển thành "Get 5 · R$ 25".
- Mình sẽ thử xem font có biểu tượng xoay không; nếu không, dùng nhãn chữ "R" thay vì chờ asset.

### Test

- Lune: mọi khối xoay đúng hình và quay lại sau tối đa 4 lần; `GameSession:rotate` (miễn phí, đã mua, đã mở khoá, hết lượt, khối đối xứng, sau khi thua, giá trị không hợp lệ, mở khoá bị xoá đúng lúc); `GameRuns.rotate`; `Purchases` với product xoay (cấp một lần, không cấp trùng); lockstep client = server mở rộng thêm nước xoay.
- Studio (PC, iPhone dọc và ngang): xoay bằng chuột, phím R, chạm; hết lượt thì mời mua; mua giả bằng `fakepurchase` rồi kiểm số lượt và lưu; không có cảnh báo resync.

### Bạn cần làm

Tạo Developer Product **"5 Rotations" giá 25 R$** trong đúng experience đã có ba product hồi sinh, rồi gửi ID. Mình làm được trước khi có ID (để `ROTATION_PRODUCT = 0`, nút mua ẩn); khi có ID thì điền vào `Config` là mua được.

### Giới hạn đã biết

- Lượt xoay đã mua bị trừ trong bộ nhớ, lưu theo chu kỳ của ProfileStore. Nếu server sập đúng lúc đó, người chơi có thể được lại vài lượt (giống lượt hồi sinh đã mua); chấp nhận được.
- Xoay chưa dùng được trong lúc kéo khối.

### Kết quả M15

- **Quyết định:** AM (game over giữ nguyên), AN (mỗi khối một lượt) và AO (một gói 5 lượt, 25 R$) theo đúng lựa chọn của bạn. Product `3727205638` (bạn gọi là "pass ID", dùng như Developer Product vì cần mua lặp lại).
- **`Pieces.rotateCW` và `Pieces.canRotate`:** tìm khối cùng hình sau một phần tư vòng quay trong bảng `Pieces`, nên không phải khai bảng xoay tay. Chấm, vuông 2×2 và 3×3 không xoay được.
- **`GameSession:rotate(slot, paidAvailable)`:** khối chưa mở khoá cần một lượt (miễn phí trước, rồi lượt đã mua), khối đã mở khoá xoay tự do tới khi đặt xuống. Snapshot thêm `freeRotations` và các ô đã mở khoá. Mở khoá được xoá khi đặt khối, chia bộ mới và hồi sinh.
- **Game over (điều chỉnh nhỏ so với plan):** khối đã mở khoá được tính là đặt được nếu **một hướng nào đó** còn vừa. Nếu không, người chơi đã trả lượt cho khối đó vẫn có thể thua dù khối còn xoay vừa. Khối chưa mở khoá vẫn chỉ xét hướng hiện tại, nên xoay không cứu được ván và nút Revive giữ nguyên giá trị.
- **Server:** `GameRuns.rotate` (cùng kiểu kiểm tra `runId`/`moveIndex` như `place`, giới hạn 12 lần mỗi giây, chỉ ván thường), remote `RotatePiece` và `RequestRotations`. Lượt đã mua trừ ở server (`PlayerData.useRotation`) rồi gửi lại `Profile` (thêm `rotations`). Sai thì gửi lại state và profile như nước đi sai.
- **Mua gói:** `Purchases.process` tổng quát hoá (`productOf` thay cho `tierOf`; mỗi product có `kind`: hồi sinh theo mức giá hoặc gói xoay). `PurchaseService` mở hộp mua khi client hết lượt và bấm xoay, cộng 5 lượt một lần cho mỗi `PurchaseId`, chờ lưu xong rồi gửi `Profile`. Giá đọc từ Roblox và công bố qua attribute `RotationPrice` của `ReplicatedStorage`. `Config.ROTATION_PRODUCT = 0` thì nút mua ẩn.
- **Dữ liệu:** thêm `rotations` (mặc định 0); `Reconcile` tự điền nên version vẫn là 3.
- **Analytics:** funnel `RotationOffer` (1 Requested, 2 Paid) và sự kiện `RotationUsed` (free / paid).
- **Client:** nút xoay ở góc dưới phải mỗi ô khay (chỉ với khối xoay được, ẩn khi khối đang cầm, khi game over và trong tutorial), phím **R** xoay ô đang chọn, nút **Y** trên tay cầm. Dòng dưới khay ghi số lượt ("Rotate: 1 free", "Rotate: 5 owned", hoặc "Rotate: 5 for R$ 25" khi hết). Font của game không có mũi tên xoay nên dùng "🔄" (emoji dự phòng của Roblox), đặt ở góc ô để không che ô nào của khối.
- **158 test pass** (thêm 17: xoay của `Pieces` 3, `GameSession` 6, `GameRuns` 4, gói xoay trong `Purchases` 2, `PlayerData` 1, `Telemetry` 1; lockstep client = server mở rộng thêm 587 lượt xoay qua 200 ván).

| Kiểm tra trong Studio | Kết quả |
|---|---|
| Bấm nút xoay bằng chuột thật (ô 3) | I3_H thành I3_V, server khớp khay, dùng lượt miễn phí, dòng dưới khay chuyển thành "Rotate: 5 for R$ 25" |
| Bấm lại cùng nút | Xoay tiếp miễn phí (khối đã mở khoá) |
| Bấm xoay khối khác khi hết lượt | Không xoay, server ghi funnel `RotationOffer 1 Requested` (hộp mua của Roblox mở) |
| `fakepurchase` product xoay, cùng `PurchaseId` hai lần | `rotations=5` cả hai lần (không cấp trùng), funnel có `2 Paid`, dòng "Rotate: 5 owned" |
| Xoay khối khác bằng lượt đã mua | Server `rotations=4`, client và server cùng khay, sự kiện `RotationUsed [paid]` |
| Phím R | Xoay ô đang chọn |
| 6 ván, mỗi ván 14 lần xoay ngẫu nhiên xen kẽ nước đi | Không có cảnh báo resync hay lỗi; client và server cùng trạng thái; nút ẩn khi game over |
| iPhone 17 Pro dọc (401×777) và ngang (749×381) | Nút nhìn rõ, không che ô nào của khối L5, không tràn màn hình |
| Output | Không có lỗi từ game |

- **Chưa kiểm tra được:**
  - Hộp mua thật của Roblox và giao dịch Robux thật (cần publish). Trong Studio mới thử bằng `fakepurchase`.
  - Nút Y trên tay cầm thật (bấm phím R qua MCP, cùng một action).
  - Xoay khi đang kéo khối: chưa hỗ trợ (nút và phím bị bỏ qua khi có khối đang cầm).
  - Nút trên điện thoại ngang nhỏ khoảng 23 px (ô khay ở đó chỉ 67 px); to hơn sẽ đè lên khối.
- **Giới hạn:** lượt đã mua bị trừ trong bộ nhớ và lưu theo chu kỳ ProfileStore; nếu server sập đúng lúc đó, người chơi có thể được lại vài lượt (giống lượt hồi sinh đã mua).

## M16: Donate

- 3–4 mức Developer Product (giá theo quyết định AA). Cộng `receipt.CurrencySpent` (số Robux người chơi thực trả) vào `robuxDonated`.
- **Bảng "Supporters"** dùng lại M14 (`OrderedDataStore` `RobuxDonated`).
- Nút "Support us" ở menu, không hiện giữa ván.
- Hoàn tiền: khi game có doanh thu thật thì nối webhook *Transaction Refunded* để trừ lại. Để ngoài phạm vi GĐ3, ghi vào rủi ro.

## M17: Rewarded video ad (khi đủ điều kiện)

- Phần thưởng phải là một Developer Product cố định (không ngẫu nhiên), cấp qua `ProcessReceipt` của M8.
- Client chỉ hiện nút "Watch an ad" khi `AdService:GetAdAvailabilityNowAsync` báo có quảng cáo. Server gọi `ShowRewardedVideoAdAsync`.
- Vị trí: màn Game Over (đổi 1 lần hồi sinh) và khi hết lượt xoay (đổi 1 lượt). Mỗi ván tối đa 1 lần.

## Kiểm thử chung

- Logic thuần (Progression, xoay khối, chọn tên store, xử lý receipt với dữ liệu giả) có Lune test, giữ 100% test pass.
- Mỗi mốc test trong Studio như GĐ2: PC, điện thoại dọc và ngang, bàn phím.
- Mua hàng trong Studio dùng giao dịch test (không mất Robux thật); kiểm tra gọi `ProcessReceipt` lặp lại không cấp trùng.

## Quyết định cần chốt

| Điểm | Câu hỏi | Đề xuất |
|---|---|---|
| **W.** Quà theo mốc (câu hỏi mở số 5) | Cosmetic, danh hiệu hay gì khác? | ✅ **Chốt (bổ sung của bạn):** cả mốc highscore **và mốc level** đều có quà: **danh hiệu** (cosmetic title, hiện cạnh tên ở menu và leaderboard) kèm **Badge** của Roblox; từ GĐ4 thêm **cosmetic** cho cùng các mốc. Danh hiệu chỉ kiếm bằng thành tích, không bán. |
| **X.** Tốc độ lên level | Nhanh hay chậm? | ✅ **Chốt:** EXP = điểm ván / 10; level kế tiếp cần `100 + 50 × (level − 1)` EXP. Tốc độ thật: 10 ván 1.000 điểm lên level 6, 10 ván 3.000 điểm lên level 10 (lúc đề xuất ghi nhầm là 5–6). Tune trong `Config`. |
| **Y.** Kiểu leaderboard | Bảng tự vẽ trong menu hay bảng có sẵn của Roblox? | ✅ **Chốt:** tự vẽ trong menu, tab All time / This week và Highscore / Level, kèm danh hiệu. M10 vẽ lại theo mockup. Bảng donate (Supporters) làm riêng ở M16, không chung với bảng thi đấu. |
| **Z.** Lượt xoay đã mua | Chỉ dùng trong ván đang chơi, hay giữ lại cho ván sau? | **Giữ lại** (lưu trong profile). Người chơi thấy mua không phí, và dễ bán gói nhiều lượt. |
| **AA.** Donate | Bao nhiêu mức, giá bao nhiêu? Có hiện tên người donate công khai không? | 4 mức (vd. 10 / 50 / 100 / 500 Robux) và **có** bảng Supporters công khai. |
| Từ M8 | Giá hồi sinh lần 1 và lần 2, giá lượt xoay; publish dưới **Group** hay tài khoản cá nhân | Group nếu hai người chia doanh thu. Giá chốt khi làm M8. |
| **AM.** Xoay và game over | Hết chỗ đặt khối nhưng xoay một khối sẽ vừa thì có thua không? | ✅ **Chốt:** vẫn game over. Xoay chỉ để lên kế hoạch, không cứu ván. |
| **AN.** Cách tính lượt xoay | Mỗi lần chạm hay mỗi khối? | ✅ **Chốt:** mỗi khối một lượt, khối đó xoay tự do tới khi đặt xuống. |
| **AO.** Gói lượt xoay | Bán bao nhiêu lượt, giá bao nhiêu? | ✅ **Chốt:** một gói 5 lượt giá 25 R$ (bạn tạo product và gửi ID). |
