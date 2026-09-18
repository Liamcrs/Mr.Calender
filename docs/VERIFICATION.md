# Verification · 2026-09-18

## Passed

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project MrCalender.xcodeproj -scheme MrCalender -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build` → `** BUILD SUCCEEDED **`。Xcode 26.6 使用 iPhoneSimulator 26.5 SDK 完成 arm64/x86_64 模拟器构建。
- `sh scripts/check-core.sh` → `PASS: 18 core behavioral checks` and `PASS: ICS behavioral checks`。
- `swiftc -typecheck Sources/MrCalenderCore/*.swift Tests/Portable/ICSChecks.swift Tests/Portable/main.swift` → exit 0。
- `plutil -lint Config/Info.plist Config/MrCalender.entitlements Config/PrivacyInfo.xcprivacy MrCalender.xcodeproj/project.pbxproj` → all OK。
- `git diff --check` → no output。
- ICS portable suite (weekly COUNT, EXDATE/RDATE, overrides/cancellations, stable ID, all-day, folded UTF-8, DST, malformed input and bounds) → exit 0，详见 `docs/ics-report.md`。

## Environment limits

- 完整 Xcode 已安装并接受许可；系统全局 active developer directory 现在为 `/Applications/Xcode.app/Contents/Developer`。
- 未在模拟器/真机验证 SwiftUI、UserNotifications、HealthKit、文件选择器、钥匙串和 DeepSeek 网络请求。
- 构建日志包含 CoreSimulatorService 连接警告，但不影响无模拟器设备选择的编译产物；启动模拟器仍需在 Xcode/Simulator 中初始化运行时。

## First device checks

在 Xcode 真机运行后，按顺序检查：首次设置、通知授权及完成/稍后/跳过、Apple Health 授权和 Apple Watch 训练匹配、ICS 预览导入、DeepSeek 错误/超时/撤销 Key、报告文本确认、饮食过敏过滤和删除课程。
