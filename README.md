# Mr. Calender

面向 iPhone 的本地优先日历与生活管理 App。首版入口是今日、日历、健康、吃什么和设置。

## 已包含

- 自定义日程、课程 `.ics` 导入、重复课程、例外日期、调课、取消和开课前 15 分钟提醒。
- 中国大陆 2026 节假日/调休标注，以及元旦、春节、清明、端午、中秋、国庆、情人节、万圣节、感恩节和圣诞节标注。
- 首次启动填写睡眠、起床和饮食限制；睡眠计划按次日最早定时安排倒推。
- 喝水、运动、睡眠提醒，完成/稍后 15 分钟/跳过；通知最多排程最近 60 项。
- 食堂、学校周边、商场等餐厅分类，菜品配料确认、过敏原硬过滤和近两日去重转盘。
- 体检文字/PDF/图片入口；用户确认文本后可调用 DeepSeek `deepseek-v4-pro` 生成结构化生活建议。API Key 只写入 iOS Keychain，源码不含密钥。
- HealthKit 只读运动记录，支持 Apple Watch 运动记录后续匹配自动完成。

## 打开和运行

1. 安装 Xcode 26.2 或更新版本（当前设备报告 iOS 26.6.2，建议安装支持 iOS 26 的 Xcode）。
2. 双击 `MrCalender.xcodeproj`，在 Signing & Capabilities 选择自己的 Team，确认 HealthKit capability。
3. 选择 iPhone 15 Pro 真机或模拟器，运行。首次启动填写作息；设置中请求通知、HealthKit 权限，并输入 DeepSeek API Key。
4. 真机上验证 Apple Watch 运动记录、通知操作和文件导入。

## 核心测试

没有完整 Xcode 的机器上可以运行：

```sh
cd /Users/chaoran/Mr.Calender
sh scripts/check-core.sh
```

它通过 `swiftc` 运行 18 个核心行为检查。完整 Xcode 环境再运行 `swift test --disable-sandbox`，会执行 XCTest 套件。

## 隐私与发布准备

报告默认保存在本机；发送给 Agent 前需要用户主动点击分析。HealthKit 原始数据不发送。正式发布前需要完善隐私政策、真实 Bundle ID、签名、App Store 元数据、通知和 HealthKit capability 审核，以及把节日数据独立更新为每年版本。

项目设计与限制记录在 `docs/superpowers/specs/2026-09-18-mr-calender-design.md`、`docs/DECISIONS.md` 和 `docs/ics-report.md`。
