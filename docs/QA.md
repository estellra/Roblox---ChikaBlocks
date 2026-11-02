# QA và publish thử (M11)

Tài liệu cho lần publish đầu tiên: việc **bạn** cần làm trong Studio và Creator Hub, danh sách kiểm tra trước khi mở cho người thử, và hướng dẫn gửi cho người thử. Phần code đã được mình rà soát và thử tải trong Studio (kết quả ở [PHASE2.md](PHASE2.md), mục M11).

## 1. Việc bạn làm để publish

Mình không publish thay được: việc này chạy trong Studio bằng tài khoản của bạn.

1. **Chọn đúng trải nghiệm.** Ba Developer Product (ID 3727116317, 3727116434, 3727116486) thuộc về một experience cụ thể. Publish **vào chính experience đó** (File → Publish to Roblox As… → chọn experience đã tạo sản phẩm). Publish vào experience mới thì `PromptProductPurchase` sẽ báo sản phẩm không thuộc game này.
2. **Sync bản build.** Chạy `rojo serve`, bấm Connect trong Studio, kiểm tra cây có `ReplicatedStorage.Shared`, `ServerScriptService.Server` (kèm `ServerPackages`) và `StarterPlayer.StarterPlayerScripts.Client`, rồi mới publish. Nếu `ServerPackages` trống (ProfileStore), chạy `wally install` trước.
3. **Cài đặt experience** (Creator Hub → Experience → Settings):
   - *Privacy:* để **Private** trong lúc chưa thử xong. Khi mời người thử, đổi sang Public nhưng chưa quảng bá, hoặc thêm họ làm cộng tác viên. Mình chưa kiểm tra giao diện hiện tại của Creator Hub nên bạn xem lại các lựa chọn đang có.
   - *Age guidelines:* hoàn thành bảng câu hỏi độ tuổi (bắt buộc trước khi mở công khai).
   - *Monetization:* kiểm tra ba product đang ở trạng thái *On Sale* và giá 10 / 15 / 25 R$.
   - *Security:* không cần bật gì thêm trên bản đã publish (DataStore thật chạy mặc định). Trong Studio game vẫn dùng store `PlayerData_Dev` riêng, nên dữ liệu thử không lẫn vào dữ liệu thật.
4. **Hình ảnh cho trang game:** tên *ChikaBlocks*, icon và thumbnail làm từ asset của mình (`assets/`), **không dùng nhân vật hoặc hình của bên thứ ba** (trang Moodboard của Figma chỉ để tham khảo).
5. **Badge:** chín badge của hệ thống mốc (M13) vẫn chưa có ID (`badgeId = 0`). Game chạy bình thường, chỉ chưa trao huy hiệu thật. Tạo badge rồi gửi ID để mình điền vào `Config.MILESTONES`.

## 2. Kiểm tra trước khi mời người thử

| # | Việc | Cách làm | Đạt khi |
|---|---|---|---|
| 1 | Vào game lần đầu | Tài khoản mới hoàn toàn (hoặc `resetdata` trong Studio) | Tutorial hiện ngay, không lỗi trong Output |
| 2 | Chơi hết một ván | Chơi tới khi hết nước | Màn Game Over có điểm, Best, EXP, nút Revive |
| 3 | **Mua hồi sinh thật** | Dùng tài khoản của bạn, mua một lần 10 R$ | Hộp mua hiện đúng giá, mua xong bảng được xoá vùng giữa 4×4, điểm giữ nguyên, **Robux bị trừ đúng 1 lần** |
| 4 | Huỷ hộp mua | Bấm Revive rồi huỷ | Nút trở lại "Revive · R$ …", không bị kẹt "Please wait…" |
| 5 | Thoát giữa chừng | Mua xong rồi đóng game ngay | Mở lại: lượt hồi sinh đã mua vẫn còn ("Revive · Free") |
| 6 | Lưu dữ liệu | Đạt điểm cao rồi thoát, vào lại | Best, level và EXP còn nguyên |
| 7 | Bảng xếp hạng | Mở Leaderboard sau vài ván | Có tên bạn, đủ bốn tab All time / This week / Highscore / Level |
| 8 | Điện thoại dọc và ngang | iPhone/Android thật | Không tràn khung, kéo thả không giật, nút bấm được |
| 9 | Tay cầm và bàn phím | Gắn tay cầm; thử phím mũi tên, Enter, Esc | Chơi và tạm dừng được |
| 10 | Mạng chậm | Đặt điện thoại ở 3G / Wi-Fi yếu, hoặc Network Simulator trong Studio | Khối đặt được ngay (client dự đoán), không bị "đặt lại" liên tục, Game Over vẫn tới |

Sau mỗi lượt chơi mở **F9 → Server log** (cần quyền chủ game) và tìm dòng lỗi màu đỏ. Mục tiêu của PLAN: **≥95% lượt thử không gặp lỗi**; tính bằng số người hoàn thành đủ mười việc trên chia cho tổng số người thử.

## 3. Hướng dẫn cho người thử

Gửi đoạn dưới cho họ (đổi `<link>` thành link game):

> **Thử game ChikaBlocks giúp mình nhé!** Game xếp khối: kéo khối ở khay dưới vào bảng 8×8, lấp đầy một hàng hoặc cột để ghi điểm. Link: `<link>`
>
> Trong lúc chơi **mình sẽ không giải thích gì** — mình muốn xem game có tự giải thích được không. Bạn hãy:
> 1. Vào game và chơi như bình thường, khoảng 10 phút. Có thể thử cả menu, bảng xếp hạng, tạm dừng, chơi lại.
> 2. Nói to điều bạn đang nghĩ ("cái này là gì?", "sao không kéo được?").
> 3. Khi hết nước đi, bạn **không cần mua** nút Revive. Chỉ cần cho mình biết bạn có hiểu nút đó làm gì không.
> 4. Cuối buổi trả lời giúp: Tutorial đã đủ hiểu chưa? Chỗ nào bực nhất? Có lúc nào game đứng, giật hoặc báo lỗi không? Máy bạn dùng là gì (điện thoại / PC / tay cầm)?

### Phép thử "người mới hiểu trong 15 giây"

Ngồi cạnh người thử (hoặc xem họ chia sẻ màn hình) và bấm giờ từ lúc game mở:

- Đạt nếu **trong 15 giây** họ kéo được ít nhất một khối vào bảng mà không cần ai chỉ.
- Ghi lại họ dừng ở đâu, bấm nhầm đâu, có bấm Skip tutorial không.
- Cần ít nhất 5 người chưa từng thấy game; ưu tiên người không chơi game xếp khối.

### Mẫu ghi lỗi

```
Máy / trình điều khiển: (iPhone 13 dọc, PC chuột, tay cầm Xbox …)
Việc đang làm:
Điều xảy ra:
Điều mong đợi:
Có làm lại được không (luôn / thỉnh thoảng / một lần):
Ảnh chụp màn hình hoặc dòng đỏ trong F9:
```

## 4. Theo dõi sau khi mở

- **Creator Hub → Analytics:** funnel `ReviveOffer` (1 Offered → 2 Requested → 3 Paid → 4 Revived), onboarding funnel (tutorial), sự kiện `RunScore`, `RunMoves`, `RunMaxCombo`.
- **Cảnh báo cần xử lý ngay:** số lượt "Requested" nhiều nhưng "Paid" bằng 0 (hộp mua có thể bị chặn), hoặc "Paid" nhiều hơn "Revived" (đã trừ Robux mà chưa hồi sinh; lượt mua được giữ lại thành lượt miễn phí, nhưng người chơi có thể hỏi).
- **Hoàn tiền / khiếu nại:** Roblox xử lý hoàn Robux phía họ; game không trừ lại lượt đã dùng.
