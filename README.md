<div align="center">
  <img src="Sources/DoupiViewer/Resources/AppIcon.icns" width="96" height="96" alt="Doupi Viewer">
  <h1>doupi</h1>
  <p>macOS 原生文件查看器 — 拖拽或打开文件，按类型分发到不同渲染器</p>
  <p>
    <img src="https://img.shields.io/badge/macOS-14%2B-brightgreen">
    <img src="https://img.shields.io/badge/Swift-5.9%2B-orange">
    <img src="https://img.shields.io/badge/license-MIT-blue">
  </p>
</div>

## 概述

<img width="3272" height="2036" alt="image" src="https://github.com/user-attachments/assets/8b62ade6-de35-4ab0-9604-30eaaaf99b3b" />


doupi 是一个 macOS 原生文件查看器。拖拽文件到窗口（或通过 ⌘+O 打开），自动识别文件类型并选择合适的预览器渲染。

### 支持的文件类型

| 类型 | 渲染器 | 特性 |
|------|--------|------|
| HTML/HTM | `WebView` | WKWebView 加载，支持 CSS/JS/图片等同级资源 |
| Markdown | `MarkdownView` | 通过 marked.js 渲染为格式化 HTML |
| TSX/JSX | `PreviewContainer` | esbuild 编译 → WKWebView 预览，自动处理依赖 |
| 代码（30+ 语言） | `CodeView` | highlight.js 语法高亮，支持全文搜索 |
| 图片 | `ImageView` | NSImageView + NSCache（64 条缓存） |
| PDF | `PDFViewer` | PDFKit 内嵌渲染 |
| 纯文本 | 原生 | ScrollView，等宽字体 |

## 使用

### 打开文件

- **拖拽**：拖拽文件到窗口中央区域
- **菜单**：⌘+O 打开文件选择面板
- **最近文件**：左侧边栏显示最近打开记录（最多 20 条）

### 搜索

- ⌘+F — 开启搜索
- ⌘+G — 下一个匹配
- ⌘+⇧+G — 上一个匹配
- Esc — 关闭搜索

### 快捷键

| 快捷键 | 功能 |
|--------|------|
| ⌘+O | 打开文件 |
| ⌘+W | 关闭文件 |
| ⌘+F | 搜索 |
| ⌘+⇧+F | 聚焦侧边栏筛选 |

## 构建

### 最低要求

- macOS 14+
- Swift 5.9+ / Xcode 15+

### Debug 构建

```bash
swift build
```

### 打包为 .app

```bash
./Scripts/bundle.sh     # Debug 打包
./build-app.sh          # Release 打包
```

打包后的 .app 在项目根目录（Debug）或 `.build/release/DoupiViewer.app`（Release）。

## 架构

### 路由

`DocumentView.swift` 按文件类型分发到对应渲染器：

```
FileInfo → DocumentView
               ├── .html → WebView
               ├── .md   → MarkdownView
               ├── .tsx  → PreviewContainer (esbuild)
               ├── .code → CodeView (highlight.js)
               ├── .img  → ImageView
               ├── .pdf  → PDFViewer
               └── .txt  → 原生文本
```

### 组件

| 模块 | 职责 |
|------|------|
| `Theme.swift` | 设计 Token（暖纸色背景 + 绿色强调） |
| `FileInfo.swift` | 文件元数据 + 类型判断 |
| `FileHistory.swift` | 最近打开记录（UserDefaults） |
| `FileSidebar.swift` | 最近文件侧边栏 + 筛选 |
| `FileDropDelegate.swift` | 拖拽 & NSOpenPanel |
| `SearchState.swift` | 搜索状态管理 |
| `PreviewCompiler.swift` | TSX 编译流水线（两阶段：本地 node_modules → CDN 回退） |

### 设计主题

暖纸色背景（`#f3f2ee`）+ 绿色强调（`#5d9a32`），所有设计 Token 集中在 `Theme.swift`。

## License

MIT
