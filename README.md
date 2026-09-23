# Mr. Calender

[![CI](https://github.com/Liamcrs/Mr.Calender/actions/workflows/ci.yml/badge.svg)](https://github.com/Liamcrs/Mr.Calender/actions/workflows/ci.yml)

面向 iPhone 的本地优先日历与生活管理 App。它把课程与日程、健康计划、饮食选择和系统通知放在一个简洁的工作流里。

> 项目名称中的 `Calender` 是产品名称的既有拼写，代码、Bundle 和仓库也保持这一名称。

## 功能

- **今日**：查看未来 7 天的日程和生活计划；喝水提醒保留为系统通知，不在“今日”列表中堆叠显示。
- **日历**：创建日程、指定时间、填写多行备注；标注中国传统节日和常见西方节日；支持导入多个命名 `.ics` 课表，并可分别启用、隐藏、重新导入和删除；课程开始前 15 分钟通知。
- **健康**：通过健康问诊 Agent 对话整理作息、饮食和生活建议；支持手动记录运动，也可以读取 HealthKit/Apple Watch 的运动记录。
- **喝水与睡眠**：用户设置每日饮水量和提醒间隔；喝水提醒避开睡眠时段与已有日程；根据次日最早安排和睡眠目标生成睡前通知。
- **吃什么**：按食堂、学校周边、商场等分类维护餐厅和菜品；可选上传菜品照片；大转盘随机选择，并结合过敏原和近期用餐记录过滤。
- **通知**：课程、喝水、饮食和睡眠提醒使用系统通知；提醒支持完成、稍后 15 分钟和跳过。
- **封面**：`App/Assets.xcassets/AppIcon.appiconset` 中包含正式 App 图标资源。

## 技术结构

```text
App/
  MrCalenderApp.swift       SwiftUI 入口
  Views/                    今日、日历、健康、吃什么、设置
  State/AppStore.swift      本地状态、迁移和提醒刷新
  Services/                 通知、HealthKit、DeepSeek、文件解析
  Assets.xcassets/          AppIcon
Sources/MrCalenderCore/     可独立测试的模型、规划和 ICS 解析核心
  Timetables.swift          命名课表的启用、替换和删除逻辑
Tests/                      XCTest 与便携行为检查
Config/                     Info.plist、Entitlements、隐私配置
```

## 环境要求

- macOS + Xcode 26 或更新版本
- iOS 17 或更新版本；HealthKit/Apple Watch 验证需要真实设备
- Swift 5.9 或更新版本
- Apple Developer Team（真机签名时在 Xcode 的 Signing & Capabilities 中选择）

## 开始运行

1. 克隆仓库并打开 `MrCalender.xcodeproj`。
2. 在 target `MrCalender` 的 Signing & Capabilities 中选择自己的 Team，确认 HealthKit capability。
3. 选择 iPhone 真机或模拟器，运行 App。
4. 首次启动填写睡眠、起床时间和饮食限制；在设置中按需授予通知、HealthKit 权限。
5. 在“健康”页面的问诊对话中配置 DeepSeek API Key。Key 只保存到 iOS Keychain，不应写入源码、README 或 Git 历史。

### DeepSeek 配置说明

应用使用 `deepseek-v4-pro` 进行健康问诊建议。请在 App 内输入自己的 Key；不要把 Key 放进 `Info.plist`、环境变量提交文件或公开仓库。健康建议仅供生活管理参考，不替代医生诊断。

## 课表导入

在“日历”页面点击“导入课表”，先为课表命名，再选择 `.ics` 文件。已导入的课表可独立启用、隐藏、重新导入和删除。重新导入会用新文件替换该课表的全部课程，未包含在新文件中的旧课程会被删除；仅含取消记录的文件可能清空全部课程。课表的身份、名称和启用／隐藏状态保持不变，其他课表不受影响。导入和删除仅在本地保存成功后生效。

解析器目前实现的 RFC 5545 子集包括 `DAILY`、`WEEKLY`、`INTERVAL`、`COUNT`、`UNTIL`、未编号的每周 `BYDAY`、`EXDATE`、`RDATE`、`RECURRENCE-ID` 以及 Foundation 时区；规则展开范围受限，以避免异常文件造成无限计算。

## 测试

便携核心检查：

```sh
sh scripts/check-core.sh
```

完整 Swift Package 测试：

```sh
swift test --disable-sandbox
```

不签名构建 iOS App：

```sh
xcodebuild -project MrCalender.xcodeproj -scheme MrCalender -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/MrCalenderDerivedData CODE_SIGNING_ALLOWED=NO build
```

核心测试覆盖日历节日、饮食过滤、ICS 解析、喝水/睡眠计划、提醒去重和提前完成计划等行为。

## 隐私、权限与发布准备

- 日程、餐厅、菜品和计划默认保存在本机。
- HealthKit 只读取用户授权的运动记录；不会写入健康数据，也不会把原始健康记录发送给 AI。
- 健康问诊内容只有在用户主动提交后才会发送到 DeepSeek。
- 通知、HealthKit 和文件导入权限均由系统弹窗控制。
- 正式发布前仍需替换示例 Bundle ID、配置正式签名、补充隐私政策和 App Store 元数据，并按年度维护节假日数据。

## 许可证

本项目使用 [MIT License](LICENSE.md)。
