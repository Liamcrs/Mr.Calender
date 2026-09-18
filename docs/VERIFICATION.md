# Verification · 2026-09-18

## Passed

- `sh scripts/check-core.sh` → `PASS: 18 core behavioral checks` and `PASS: ICS behavioral checks`。
- `swift test --disable-sandbox --filter MrCalenderCoreTests` → 25 tests passed。
- `swiftc -frontend -parse` on changed Swift sources → exit 0。
- `plutil -lint Config/Info.plist Config/MrCalender.entitlements Config/PrivacyInfo.xcprivacy MrCalender.xcodeproj/project.pbxproj` → all OK。
- `git diff --check` → no output。
- Xcode GUI 真机运行已验证应用可安装并启动到 `Channel_15`；通知、HealthKit、照片和 DeepSeek 仍需在设备上逐项点按验证。
- ICS portable suite (weekly COUNT, EXDATE/RDATE, overrides/cancellations, stable ID, all-day, folded UTF-8, DST, malformed input and bounds) → exit 0，详见 `docs/ics-report.md`。

## Environment limits

- 完整 Xcode 已安装并接受许可；系统全局 active developer directory 现在为 `/Applications/Xcode.app/Contents/Developer`。
- Xcode 27 命令行构建目前被 SwiftUI 宏服务 `SwiftUIMacros.StateMacro: malformed response` 阻断；该错误也会出现在未改动的 SwiftUI 文件上。以 Xcode GUI 真机运行作为补充验证。
- 设备控制台可能出现 `cannot add handler to 0 from 0 - dropping`、LaunchServices `-54` 等 iOS 27/Xcode 噪声日志，不代表核心逻辑失败。

## First device checks

在设备上按顺序检查：首次设置、系统通知授权、Apple Health/Apple Watch 训练读取、ICS 预览导入、DeepSeek 错误/超时/撤销 Key、可选菜品照片、饮食过敏过滤和删除课程。
