# Checklist trước khi public

Lập ngày 2026-11-26 từ tài liệu, config và lịch sử git. Việc đã thử nhưng chưa ghi vào tài liệu vẫn để trống ở đây; tick lại khi xác nhận.

**Thứ tự đề xuất:** A4 → publish bản Private có bật PVP → A1, A2, A3 → sửa lỗi → A5 → phần B → public.

## Trước khi test

- **PVP đang tắt ngoài Studio** (`PVP.ENABLED = false` trong `src/shared/Config.luau`). Muốn thử Duel và Ranked bằng hai tài khoản trên server thật, bật cờ này rồi publish khi experience còn **Private**.
- `dev` đang hơn `main` 37 commit. Bản đã publish có thể chưa có Co-op và PVP, nên publish lại trước khi test (cách publish ở [QA.md](QA.md) mục 1).
- Test hai người cũng chạy được trong Studio (Test → Clients and Servers, 2 người), nhưng không thay được lượt thử trên server thật.

## A. Việc cần test

### A1. Một tài khoản, bản publish

Cách làm và điều kiện đạt của từng việc ở bảng trong [QA.md](QA.md) mục 2.

- [ ] Người chơi mới: tutorial hiện ngay, Output không lỗi
- [ ] Chơi hết một ván, màn Game Over đủ thông tin
- [ ] Best, level, EXP còn nguyên sau khi vào lại
- [ ] Leaderboard có tên mình, đủ bốn tab
- [ ] Mua hồi sinh thật (10 R$), Robux trừ đúng 1 lần
- [ ] Huỷ hộp mua, nút không bị kẹt
- [ ] Mua xong thoát ngay, vào lại vẫn còn lượt
- [ ] Mua gói 5 lượt xoay thật (25 R$), còn sau khi vào lại
- [ ] Donate thật 5 R$: "Your total" và Top supporters cập nhật
- [ ] Nút Invite friends (không chạy trong Studio)
- [ ] Mạng yếu: khối không bị đặt lại liên tục
- [ ] F9 → Server log không có dòng đỏ

### A2. Hai tài khoản thật (cả hai đã xong tutorial)

**Lời mời và phòng** ([PHASE5.md](PHASE5.md))

- [ ] Mời, nhận, từ chối, rút lời mời
- [ ] Lời mời hết hạn sau 30 giây, mời lại trong 60 giây
- [ ] Rời phòng, đóng client, người vào sau hiện trong danh sách
- [ ] Phím Esc / Backspace

**Co-op** ([PHASE5.md](PHASE5.md))

- [ ] Chơi trọn một ván
- [ ] Hai người thả đè nhau: khối về khay, không có cảnh báo resync
- [ ] Thấy bóng khối của bạn chơi
- [ ] Một người rời: hiện "Partner left", người ở lại kéo được khối còn lại, điểm được chốt
- [ ] Treo máy 45 giây rồi Take over
- [ ] Play again cần cả hai đồng ý
- [ ] Menu / Leave run; nhận lời mời khi đang chơi solo hoặc đang mở Leaderboard, Support
- [ ] Bảng Co-op ghi theo cặp "A & B", điểm thấp hơn không ghi đè
- [ ] EXP và level up
- [ ] Xoay khối: bạn chơi thấy khối xoay, không xoay được khối của người kia
- [ ] Mua gói xoay giữa ván Co-op
- [ ] Hồi sinh: cả hai thấy nút, một người trả thì cả hai chơi tiếp
- [ ] Cả hai cùng bấm mua: chỉ tính một lượt, lượt kia còn lại
- [ ] Người ở lại một mình vẫn hồi sinh được
- [ ] Game over lần hai cộng dồn EXP đúng
- [ ] Xoay khối không làm mất lượt Take over

**PVP Duel** ([PHASE6.md](PHASE6.md))

- [ ] Mời, nhận, từ chối
- [ ] Trọn trận 3 phút, bảng nhỏ của đối thủ cập nhật
- [ ] Gửi và nhận rác
- [ ] Một bên đóng game: bên kia thắng
- [ ] Mạng chậm: đồng hồ hai máy và nước đi sát giờ
- [ ] Đấu lại

**Ranked và bảng Rank** ([PHASE6.md](PHASE6.md))

- [ ] Ghép cặp được, điểm đổi đúng
- [ ] Trận thứ 3 của cùng một cặp trong 24 giờ báo "Unrated"
- [ ] Rời trận rồi vào lại: bị trừ điểm
- [ ] Vào bằng thiết bị thứ hai giữa trận: bị trừ điểm
- [ ] Private server không có Ranked
- [ ] Dưới level 3 thấy lý do bị khoá
- [ ] Đủ 5 trận thì hiện trên tab Rank (mỗi cặp chỉ tính 2 trận mỗi ngày, nên cần thêm đối thủ hoặc nhiều ngày)

### A3. Thiết bị

PVP chưa có mockup điện thoại và chưa được thử cảm ứng hay màn dọc; đây là phần hở lớn nhất.

- [ ] Điện thoại thật, dọc và ngang: solo
- [ ] Điện thoại thật, dọc và ngang: Co-op
- [ ] Điện thoại thật, dọc và ngang: PVP và màn chờ ghép trận
- [ ] Điện thoại thật, dọc và ngang: Leaderboard, Support
- [ ] Kéo thả không giật; ngón thứ hai xoay được khối khi đang kéo
- [ ] Tay cầm (LB/RB, A, B, Y) và bàn phím (mũi tên, Enter, Esc)

### A4. Mới sửa, chưa thử trong Studio

- [ ] Nút Ranked bị khoá hiện kèm lý do
- [ ] Forfeit phải bấm hai lần
- [ ] Hàng ba nút Ranked, Co-op, Leaderboard trên màn thấp
- [ ] Ảnh huy hiệu rank hiện đúng sau khi Roblox duyệt ảnh

### A5. Người mới và vận hành

- [ ] Phép thử 15 giây với ít nhất 5 người chưa từng thấy game ([QA.md](QA.md) mục 3)
- [ ] Ít nhất 95% người thử không gặp lỗi
- [ ] `lune run scripts/erase-user.luau <userId> --dry-run`, rồi xoá thật trên tài khoản thử; kiểm tra profile, các bảng điểm, dòng cặp Co-op và bảng `Rank_`
- [ ] Analytics có số liệu: `ReviveOffer`, onboarding, `CoopInvite`, `CoopReviveOffer`, `PvpQueue`, `PvpQueueWait`

## B. Việc còn lại trước khi public

### Nên coi là bắt buộc

- [ ] Sửa các lỗi tìm được ở phần A, nhất là giao diện điện thoại
- [ ] Review code Co-op và PVP về bảo mật và mất dữ liệu (tài liệu mới ghi đợt review cho bản publish đầu, M11)
- [ ] Bật `PVP.ENABLED` sau khi test hai người đạt (hoặc public mà chưa mở PVP)
- [ ] Đặt `PVP.RATING.REWARDS_FROM_SEASON` bằng tháng kế tiếp tháng bật PVP: bật trong 11/2026 là `2026M12`, trong 12/2026 là `2027M01` (giá trị hiện tại)
- [ ] Creator Hub: bảng câu hỏi độ tuổi
- [ ] Creator Hub: Developer Product *On Sale*, đúng giá (hồi sinh, gói xoay, donate)
- [ ] Creator Hub: server 12–16 người
- [ ] Trang game: tên, mô tả, icon và thumbnail làm từ asset của mình
- [ ] Kiểm tra chính sách donate hiện hành của Roblox
- [ ] Quyết định tên "ChikaBlocks": còn gần "Chiikawa", có rủi ro thương hiệu
- [ ] Publish vào đúng experience đang giữ các Developer Product
- [ ] Merge `dev` vào `main`
- [ ] Đổi Privacy từ Private sang Public

### Nên có, không chặn

- [ ] Badge: 9 badge mốc (`Config.MILESTONES`) và 3 badge hạng (`TIER_BADGES`), ID đang là 0
- [ ] Âm thanh và nhạc (chưa có gì trong code)
- [ ] Thông báo chuyển mùa (chờ mockup)
- [ ] Mockup điện thoại và các màn PVP còn thiếu
- [ ] Kiểm kiểu `--!strict` bằng luau-lsp

### Sau khi public

- [ ] Theo dõi Analytics và F9 ([QA.md](QA.md) mục 4): funnel mua hàng, `CoopConflict`, `PvpQueueWait`
- [ ] Ghép liên server (M29), chỉ khi hàng chờ vắng
- [ ] Quảng cáo thưởng (cần ít nhất 2.000 người chơi mỗi tháng)
- [ ] Webhook hoàn tiền
- [ ] Cosmetic và cửa hàng (giai đoạn 4)
