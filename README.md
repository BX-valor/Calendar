# ConferenceDeadline

一个 macOS 14+ 菜单栏小应用，展示 CCF 推荐会议（CCF-A / CCF-B，如 NeurIPS、CVPR、ACM MM、WACV 等）的摘要截止、投稿截止、rebuttal、final decision 时间以及会议地点。

## 功能

- 常驻菜单栏，点击显示会议 deadline 列表
- 按距离下一个 deadline 的时间排序
- 颜色提示：7 天内红色、30 天内黄色、已过期灰色
- 点击会议行展开完整时间线（含地点 Location / Venue）
- 显示 CCF 评级 tag（CCF-A 红、CCF-B 橙、CCF-C 蓝）
- 支持用户手动添加、编辑、删除会议
- 用户数据保存在 `~/Library/Application Support/ConferenceDeadline/userConferences.json`

## 环境要求

- macOS 14 (Sonoma) 或更高版本
- Xcode 16 或更高版本（用于编译 SwiftUI / Swift 6 项目）

## 如何运行

### 方式一：Xcode（推荐）

1. 用 Xcode 打开项目目录（即本目录）。
2. 等待 Swift Package 解析完成。
3. 选择 `ConferenceDeadline` scheme，按 `Cmd + R` 运行。

### 方式二：命令行

```bash
swift build
swift run ConferenceDeadline
```

> 注意：命令行 `swift run` 启动的是可执行文件，不会以完整 `.app` 形式运行，因此菜单栏图标和某些系统服务行为可能与 Xcode 运行略有差异。日常使用和调试建议用 Xcode。

## 项目结构

```
ConferenceDeadline/
  ConferenceDeadlineApp.swift       # @main 入口，MenuBarExtra
  Models/
    Conference.swift                # 会议数据模型
  Services/
    ConferenceDataService.swift     # JSON 加载与持久化
  ViewModels/
    ConferenceListViewModel.swift   # 排序、过滤、业务逻辑
  Views/
    MenuBarView.swift               # 菜单栏主面板
    ConferenceRowView.swift         # 单行会议 + 展开详情
    InlineEditView.swift            # 面板内编辑视图
  Resources/
    conferences.json                # 默认会议数据
scripts/
  fetch_deadlines.py                # 从 ai-deadlines 抓取会议时间
  fetch_deadlines_report.md         # 抓取后的核验报告
Package.swift
```

## 更新默认会议数据

```bash
# 使用系统 Python 或任意有 PyYAML 的环境
python3 scripts/fetch_deadlines.py
```

脚本会从 [paperswithcode/ai-deadlines](https://github.com/paperswithcode/ai-deadlines) 抓取会议时间，自动生成 `Sources/ConferenceDeadline/Resources/conferences.json`，并输出 `scripts/fetch_deadlines_report.md` 提示需要官网核实的字段。

脚本会自动：
- 覆盖 CCF-A 全量 AI 相关会议 + 部分热门 CCF-B 会议（共约 19 个）
- 为每个会议打上 `CCF-A` / `CCF-B` / `CCF-C` tag
- 提取会议地点 `location`

**注意**：ai-deadlines 不提供 rebuttal、final decision 和部分未来年份数据，请务必根据官网补充或修正。

## 数据模型

```json
{
  "id": "cvpr2026",
  "name": "CVPR",
  "year": 2026,
  "category": "CV",
  "abstractDeadline": "2025-11-07T23:59:59-12:00",
  "paperDeadline": "2025-11-13T23:59:59-12:00",
  "rebuttalDeadline": null,
  "finalDecisionDate": null,
  "conferenceDate": "2026-06-02T00:00:00-07:00",
  "location": "Vancouver, Canada",
  "venue": null,
  "website": "https://cvpr.thecvf.com/Conferences/2026",
  "timezone": "AoE",
  "tags": ["CCF-A"]
}
```

- 必填：`id`、`name`、`year`、`abstractDeadline`、`paperDeadline`、`tags`
- 可选：`category`、`rebuttalDeadline`、`finalDecisionDate`、`conferenceDate`、`location`、`venue`、`website`、`timezone`
- `tags` 必须至少包含一个 CCF 评级标签：`CCF-A`、`CCF-B` 或 `CCF-C`
- 无时区信息时默认按 AoE (UTC-12) 处理

## 项目进度

### 已完成（MVP 可用）

- [x] Swift Package 项目配置（macOS 14+）
- [x] MenuBarExtra 菜单栏入口 + SF Symbols 图标
- [x] 会议数据模型 + 时区/AoE 处理
- [x] 默认 JSON 数据加载 + 用户数据持久化
- [x] 菜单栏主面板：列表展示、倒计时、颜色提示、展开详情
- [x] 面板内直接编辑会议（InlineEditView）
- [x] 新增 / 删除会议
- [x] 从 ai-deadlines 抓取的 Python 脚本 + 核验报告
- [x] README 文档
- [x] 已在 Xcode 中跑通并验证
- [x] 领域模型扩展：tags（CCF 评级）、location、venue
- [x] 默认会议扩展：CCF-A 全量 AI 相关 + 部分 CCF-B（约 19 个）
- [x] `CONTEXT.md` 领域术语表

### 待办 / 可选优化

- [ ] 本地通知提醒（ grilling 阶段决定首版不做）
- [ ] 自动从远程源刷新数据
- [ ] UI/UX 细化和自定义图标

### 已知限制

1. **数据新鲜度**：`ai-deadlines` 不是实时更新，目前 JSON 中 2026 年会议大多已截止；ICCV 2027 / NAACL 2027 用的是估算值，需要根据官网后续更新。
2. **命令行运行差异**：`swift run` 不会生成完整 `.app` bundle，因此菜单栏体验可能与 Xcode 运行略有差异；推荐用 Xcode `Cmd + R` 运行。
