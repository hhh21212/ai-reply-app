# ai-reply-app

> 自用 AI 应答软件 —— 连接可配置的 OpenAI 兼容 API，对话后自动提取摘要归档。

一个运行在 Android 上的 AI 对话助手：接入任意 OpenAI 兼容接口（DeepSeek、通义、Kimi 等），日常对话之后自动用大模型抽取一句话摘要，把关键信息沉淀到本地，随时回查。

## ✨ 功能

- 🔌 **可配置 API**：baseUrl / model / apiKey 在设置页填写，密钥用 `flutter_secure_storage` 加密存储
- 💬 **流式对话**：基于 Dio 的 OpenAI 兼容 `/chat/completions` 客户端
- 📝 **摘要归档**：每段对话自动抽取摘要，本地 SQLite（Drift）持久化，支持搜索回查
- 💾 **备份**：数据导出 / 恢复
- 🎨 简洁的 Material 3 界面

## 🧱 技术栈

- **Flutter / Dart**（`>=3.13.0`）
- **Riverpod** — 状态管理
- **Drift + sqlite3** — 本地数据库
- **Dio** — 网络请求
- **flutter_secure_storage / shared_preferences** — 配置与密钥存储

## 📁 结构

```
lib/
├── data/            # Drift 数据库与 DAO
├── providers/       # Riverpod 状态（chat / archive / settings）
├── screens/         # 聊天、归档、设置、归档详情
├── services/        # api_client、summary_service、backup_service、settings_service
└── widgets/         # 消息气泡等 UI 组件
```

## 🚀 运行

```bash
flutter pub get
flutter run
```

> 首次使用请在「设置」页填入你的 API 地址、模型名和密钥。

## ⚠️ 注意

- 本应用密钥仅保存在本机安全存储，不会上传任何第三方。
- 仅作为个人学习与自用工具，不提供预置模型服务。

## 📄 License

[MIT](LICENSE)
