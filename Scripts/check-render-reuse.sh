#!/bin/bash
# 渲染器复用的回归检查：长驻 WebView + 推内容应当比每次重建页面快一个数量级，
# 滚动位置记忆/恢复、搜索指令去重、markdown 壳种类也都别退化。
set -euo pipefail
cd "$(dirname "$0")/.."

# 结构性护栏：真退回「每次切文件都整页重载」的话，这些标记会先消失。
if ! grep -q "__doupiPush" Sources/DoupiViewer/MarkdownView.swift; then
    echo "FAIL: MarkdownView 不再推内容，退回每次整页加载"
    exit 1
fi
if ! grep -q "__doupiPush" Sources/DoupiViewer/CodeView.swift; then
    echo "FAIL: CodeView 不再推内容，退回每次整页加载"
    exit 1
fi
if ! grep -q "pinScroll" Sources/DoupiViewer/WebView.swift; then
    echo "FAIL: HTML 渲染器没有恢复滚动位置的钩子"
    exit 1
fi
if ! grep -q "ScrollMemory.shared.offset" Sources/DoupiViewer/MarkdownView.swift; then
    echo "FAIL: Markdown 渲染器没有按文件恢复滚动位置"
    exit 1
fi
if ! grep -q "ScrollMemory.shared.offset" Sources/DoupiViewer/CodeView.swift; then
    echo "FAIL: 代码渲染器没有按文件恢复滚动位置"
    exit 1
fi
if ! grep -q "ScrollMemory.shared.remember" Sources/DoupiViewer/WebContentSupport.swift; then
    echo "FAIL: 页面滚动位置没有写回记忆"
    exit 1
fi
if grep -qE '^[[:space:]]*\.id\(info\.id\)' Sources/DoupiViewer/ContentView.swift; then
    echo "FAIL: ContentView 又按文件 id 重建渲染器，复用失效"
    exit 1
fi

mkdir -p .build
swiftc -sdk "$(xcrun --show-sdk-path)" \
    -target arm64-apple-macos14 \
    -module-cache-path .build/render-reuse-check-cache \
    Sources/DoupiViewer/WebContentSupport.swift \
    Scripts/check-render-reuse.swift \
    -framework AppKit -framework WebKit \
    -o .build/check-render-reuse
.build/check-render-reuse
