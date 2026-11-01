# Giai đoạn 3: Giữ chân người chơi và kiếm tiền

> Plan đã duyệt; M12 xong. Các điểm cần bạn quyết định cho các mốc sau nằm ở [cuối file](#quyết-định-cần-chốt).

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
| **M13** Level và EXP | EXP sau mỗi ván, level, quà theo mốc highscore | Quyết định W, X | ✅ sau khi chốt |
| **M14** Leaderboard | Highscore và Level (toàn thời gian và theo tuần) | Quyết định Y | ✅ sau khi chốt |
| **M8** Hồi sinh (của GĐ2) | `PurchaseService`, `ProcessReceipt` không cấp trùng | Giá, Group/cá nhân, tạo product | ⏳ chờ bạn |
| **M15** Xoay khối | 1 lượt miễn phí mỗi ván, mua thêm bằng Robux | M8, quyết định Z | ⏳ |
| **M16** Donate | Nhiều mức Developer Product, bảng "Supporters" | M8, M14, quyết định AA | ⏳ |
| **M17** Rewarded video ad | Xem quảng cáo đổi 1 lần hồi sinh hoặc 1 lượt xoay | Game public, ≥ 2k người/tháng | ⏳ sau publish |

**Thứ tự đề xuất:** M12 → M13 → M14 làm ngay. Khi bạn chốt xong giá và Group thì làm M8 → M15 → M16. M10/M11 chen vào khi có mockup. M17 làm sau khi publish và đủ điều kiện.

M12 nên có trước khi publish (M11) để đo được ngay từ những người chơi đầu tiên.

## Dữ liệu người chơi

M12 đã nâng profile lên `version = 2` (thêm `onboardingStep`). Các mốc sau thêm trường mới; trường nào cần suy ra từ dữ liệu cũ thì thêm một bước migrate, còn lại `Reconcile` của ProfileStore tự điền mặc định:

| Trường | Dùng cho | Mặc định |
|---|---|---|
| `onboardingStep` | M12: bước funnel cuối cùng đã log (✅ đã có) | 0; profile cũ đã chơi hết ít nhất 1 ván thì 6, mới xong tutorial thì 3 |
| `exp`, `level` | M13 | 0, 1 |
| `milestonesClaimed` | M13: các mốc highscore đã nhận quà | `{}` |
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
- **Quà theo mốc highscore** (vd. 1.000 / 5.000 / 10.000 / 25.000 điểm): xem quyết định W.
- **Test:** EXP và level ở các ngưỡng, nhận quà mỗi mốc đúng một lần, migrate profile v1 sang v2.

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

## M15: Xoay khối

- Hiện mỗi hướng xoay là một khối riêng trong `Pieces`. Xoay = đổi khối trong khay sang khối của hướng kế tiếp. Cần thêm bảng `rotateCW` cho mọi khối; khối đối xứng (1x1, vuông) thì không xoay được.
- **`GameSession:rotate(slot)`** và remote `RotatePiece(runId, moveIndex, slot)`. Server kiểm tra còn lượt (1 lượt miễn phí mỗi ván, sau đó trừ vào `rotations`). Client dự đoán như với `PlacePiece`.
- **Điều khiển:** nút xoay nhỏ trên ô khay (chạm/chuột), phím R, nút Y trên tay cầm.
- **Mua thêm lượt:** Developer Product qua `PurchaseService` của M8. Hết lượt mà bấm xoay thì hiện gợi ý mua.
- Lockstep test hiện có (client = server) được mở rộng để có cả nước xoay.

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
| **W.** Quà theo mốc highscore (câu hỏi mở số 5) | Cosmetic, danh hiệu hay gì khác? | **Danh hiệu** hiện cạnh tên trên leaderboard và menu, kèm **Badge** của Roblox (hiện trên profile người chơi, giúp game được thấy nhiều hơn). Cosmetic để GĐ4 có cửa hàng rồi tính. |
| **X.** Tốc độ lên level | Nhanh hay chậm? | EXP = điểm ván / 10; level kế tiếp cần `100 + 50 × (level − 1)` EXP. Với ván trung bình khoảng 3.000 điểm thì 10 ván đầu được khoảng 5–6 level, sau đó chậm dần. Tune trong `Config`. |
| **Y.** Kiểu leaderboard | Bảng tự vẽ trong menu hay bảng có sẵn của Roblox? | **Tự vẽ trong menu.** Bảng có sẵn của Roblox nằm trong player list, mà game đã tắt player list (game chỉ có UI). Tự vẽ thì có được tab theo tuần và M10 vẽ lại cho đồng bộ. |
| **Z.** Lượt xoay đã mua | Chỉ dùng trong ván đang chơi, hay giữ lại cho ván sau? | **Giữ lại** (lưu trong profile). Người chơi thấy mua không phí, và dễ bán gói nhiều lượt. |
| **AA.** Donate | Bao nhiêu mức, giá bao nhiêu? Có hiện tên người donate công khai không? | 4 mức (vd. 10 / 50 / 100 / 500 Robux) và **có** bảng Supporters công khai. |
| Từ M8 | Giá hồi sinh lần 1 và lần 2, giá lượt xoay; publish dưới **Group** hay tài khoản cá nhân | Group nếu hai người chia doanh thu. Giá chốt khi làm M8. |
