# Verification · 2026-09-18

## Passed

- `sh scripts/check-core.sh` → `PASS: 18 core behavioral checks` and `PASS: ICS behavioral checks`。
- `swiftc -typecheck Sources/MrCalenderCore/*.swift Tests/Portable/ICSChecks.swift Tests/Portable/main.swift` → exit 0。
- `plutil -lint Config/Info.plist Config/MrCalender.entitlements Config/PrivacyInfo.xcprivacy MrCalender.xcodeproj/project.pbxproj` → all OK。
- `git diff --check` → no output。
- ICS portable suite (weekly COUNT, EXDATE/RDATE, overrides/cancellations, stable ID, all-day, folded UTF-8, DST, malformed input and bounds) → exit 0，详见 `docs/ics-report.md`。

## Environment limits

- 当前机器只有 `/Library/Developer/CommandLineTools`，没有完整 Xcode 和 iOS SDK；`swift test` 在 `import XCTest` 处失败，报告为 `no such module 'XCTest'`。
- 未在模拟器/真机验证 SwiftUI、UserNotifications、HealthKit、文件选择器、钥匙串和 DeepSeek 网络请求。
- `mas install` 能查询 Xcode 26.2，但安装需要当前 macOS 用户的 sudo 密码，因此没有完成安装。

## First device checks

在 Xcode 真机运行后，按顺序检查：首次设置、通知授权及完成/稍后/跳过、Apple Health 授权和 Apple Watch 训练匹配、ICS 预览导入、DeepSeek 错误/超时/撤销 Key、报告文本确认、饮食过敏过滤和删除课程。
