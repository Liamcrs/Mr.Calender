# 健康与计划交互更新 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让未来计划可提前完成，使用 DeepSeek 对话替代健康报告，记录 Apple 健康/手动运动，支持菜品照片，并自动安排系统通知。

**Architecture:** 保持 `MrCalenderCore` 为无 UI 的纯模型与排程层；AppStore 负责持久化、照片文件和通知同步；SwiftUI 页面只负责输入与展示。快照版本从 1 迁移到 2，旧数据保留并补充默认字段。

**Tech Stack:** Swift 5、SwiftUI、HealthKit、UserNotifications、PhotosUI、URLSession、XCTest。

## Global Constraints

- 仅支持 iPhone，最低部署目标沿用当前 Xcode 项目设置。
- API Key 只存 iOS Keychain，不写入快照或源代码。
- 健康 Agent 只给生活方式建议，不进行诊断或处方。
- 通知必须通过系统 `UNUserNotificationCenter`，权限拒绝时不崩溃。

---

### Task 1: 快照模型与排程核心

**Files:**
- Modify: `Sources/MrCalenderCore/Models.swift`
- Modify: `Sources/MrCalenderCore/Planning.swift`
- Modify: `Sources/MrCalenderCore/FoodAndStorage.swift`
- Modify: `Tests/MrCalenderCoreTests/PlanningTests.swift`
- Modify: `Tests/MrCalenderCoreTests/FoodAndStorageTests.swift`

**Interfaces:**
- `HealthProfile.waterEnabled` 默认 `true`；移除 `exerciseEnabled`。
- `Dish.photoPath: String?`；`MealLog` 保持兼容。
- 新增 `ManualWorkout`、`HealthChatMessage`、`WorkoutRecord`。
- `SchedulePlanner.sleepReminders(forMorning:profile:events:calendar:) -> [PlannedReminder]` 返回睡前 30/20/10 分钟。
- `SnapshotStore.decode` 接受 schema 1 并迁移到 schema 2。

- [ ] **Step 1: 写失败测试**：断言未来提醒完成后从 7 日窗口消失、睡眠返回三个提醒、默认喝水开启、旧快照迁移到版本 2、无 `ingredientsVerified` 仍可进入转盘。
- [ ] **Step 2: 运行测试确认失败**：`swift test --filter MrCalenderCoreTests`，预期因新字段/函数不存在而失败。
- [ ] **Step 3: 实现最小模型与排程**：加入新 Codable 字段和迁移解码；移除运动计划生成；将睡眠计划按次日最早事件生成三个提醒；转盘不再过滤 `ingredientsVerified`。
- [ ] **Step 4: 运行测试确认通过**：`swift test --filter MrCalenderCoreTests`，预期全部通过。
- [ ] **Step 5: 提交**：`git add Sources Tests && git commit -m "feat: update planning and health models"`。

### Task 2: AppStore、通知与照片存储

**Files:**
- Modify: `App/State/AppStore.swift`
- Modify: `App/Services/NotificationService.swift`
- Modify: `App/Services/HealthKitService.swift`

**Interfaces:**
- `AppStore.refreshReminders()` 使用 7 日窗口；任何快照变更后调用 `syncNotifications()`。
- `AppStore.addDishPhoto(data:) throws -> String` 把 JPEG 写入 `DishPhotos` 并返回相对文件名。
- `HealthKitService.workouts(on:)` 继续查询 Apple Health；新增 `WorkoutRecord` 转换方法。
- `NotificationService.schedule(_:)` 保留去重与 60 条上限，接受新的睡眠三提醒队列。

- [ ] **Step 1: 写失败测试**：用核心可调用的通知队列断言睡眠三个 ID 唯一、七天范围包含未来安排；对照片路径测试空值兼容。
- [ ] **Step 2: 运行 `swift test --filter MrCalenderCoreTests` 确认失败**。
- [ ] **Step 3: 实现 AppStore 七日刷新、自动通知排程和照片目录写入；在初始化后只读已有授权，不自动弹权限框**。
- [ ] **Step 4: 运行所有核心测试与 `git diff --check`**。
- [ ] **Step 5: 提交**：`git add App Sources Tests && git commit -m "feat: sync notifications and health records"`。

### Task 3: DeepSeek 健康对话

**Files:**
- Modify: `App/Services/AIService.swift`
- Modify: `App/Views/HealthView.swift`
- Modify: `App/Views/SettingsView.swift`

**Interfaces:**
- `HealthChatMessage` 的 `role/content/date` 持久化在 `snapshot.healthChat`。
- `AIService.chat(messages:baseURL:model:apiKey:) async throws -> String` 使用 `/chat/completions`，保留 HTTPS 校验。
- 健康页输入消息后追加用户消息，成功追加 Agent 消息，失败保留输入并显示横幅。

- [ ] **Step 1: 写失败测试**：为 `AIService` 的请求体构造纯函数断言完整对话和健康安全系统提示；为快照断言聊天可编码/解码。
- [ ] **Step 2: 运行测试确认失败**。
- [ ] **Step 3: 实现 `chat` 和健康聊天 UI；删除报告导入、ReportExtractor 入口及旧建议确认区**。
- [ ] **Step 4: 保留 Apple 健康连接按钮，并把当天运动记录展示在同页；加入手动运动记录表单**。
- [ ] **Step 5: 运行 `swift test` 与 Swift 文件语法解析；提交 `feat: replace report analysis with health chat`**。

### Task 4: 吃什么菜品照片与新录入流程

**Files:**
- Modify: `App/Views/FoodView.swift`
- Modify: `Sources/MrCalenderCore/FoodAndStorage.swift`
- Modify: `Sources/MrCalenderCore/Models.swift`

- [ ] **Step 1: 写失败测试**：菜品没有配料确认字段也能成为候选，照片路径可选且快照 round-trip 保留。
- [ ] **Step 2: 运行测试确认失败**。
- [ ] **Step 3: 使用 `PhotosPicker` 作为可选照片输入，保存前压缩 JPEG 并调用 `AppStore.addDishPhoto`；展示时用 `AsyncImage`/本地 `Image`，失败回退菜名**。
- [ ] **Step 4: 删除“已确认配料” Toggle 和相关文案，保留餐厅二级分类、转盘和餐食记录**。
- [ ] **Step 5: 运行测试并提交 `feat: add optional dish photos`**。

### Task 5: 今日跨日期计划与系统提醒交互

**Files:**
- Modify: `App/Views/TodayView.swift`
- Modify: `App/Views/CalendarView.swift`
- Modify: `App/Design/Theme.swift` only if needed for new status cards

- [ ] **Step 1: 写 UI 可验证逻辑**：把提醒按日分组的纯 helper 放入核心或视图扩展，测试未来两天的日期标签和完成过滤。
- [ ] **Step 2: 运行对应测试确认失败**。
- [ ] **Step 3: `TodayView` 展示未来 7 天的“安排/生活计划”，每行显示日期、时间和指标；完成/稍后/跳过继续调用 `AppStore.setReminder`，完成未来计划立即隐藏**。
- [ ] **Step 4: 移除手动铃铛作为唯一入口；进入页面和设置变化时自动调用通知同步，保留权限按钮用于重新申请**。
- [ ] **Step 5: 用 `xcodebuild -project MrCalender.xcodeproj -scheme MrCalender -destination 'generic/platform=iOS Simulator' build` 验证，然后提交 `feat: support early completion and automatic notifications`**。

### Task 6: 真机构建与回归

**Files:**
- Modify: `docs/VERIFICATION.md` with new manual test checklist.

- [ ] **Step 1: 运行 `sh scripts/check-core.sh`，预期核心与 ICS 检查通过**。
- [ ] **Step 2: 在 Xcode 选择 `Channel_15`，Run，确认真机安装成功且无签名/可执行文件错误**。
- [ ] **Step 3: 手动验证：通知权限、未来计划提前完成、健康对话、Apple 健康记录、手动运动、菜品拍照、睡前三次提醒、ICS 导入**。
- [ ] **Step 4: 记录结果并提交文档**：`git add docs/VERIFICATION.md && git commit -m "docs: verify health calendar update"`。
