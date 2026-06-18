---
name: zhongwen
description: 中文文本安全处理。用于生成、编辑或导出源码、模板、JSON、YAML、SQL、日志、错误信息、界面文案、CSV 或 Excel 中的中文内容，避免乱码、`???` 或 `\\uXXXX` 转义。
---

# Chinese Text Safe

## Overview

Keep Chinese text readable end to end. Emit Chinese characters directly whenever the target format supports them, and treat encoding as part of the implementation.

## Core Rules

- Write Chinese literals directly in code, config, templates, fixtures, and test data.
- Do not replace Chinese with `???`, mojibake, `\u4e2d\u6587`, HTML entities, percent-encoding, or Base64 unless the target format strictly requires it.
- Prefer UTF-8 for files. Match an existing repository convention only when it is already deliberate and safe for Chinese text.
- Disable serializer settings that escape non-ASCII by default. Example: Python JSON should use `ensure_ascii=False`.
- Prefer `.xlsx` over `.csv` for Excel delivery. If CSV is required for Microsoft Excel on Windows, write UTF-8 with BOM such as `utf-8-sig` unless the project already uses another proven Excel-safe path.
- If a terminal renders Chinese incorrectly but the saved file bytes are correct, keep the readable UTF-8 file and note the console limitation instead of downgrading the text to escapes.

## Workflow

1. Detect whether the task contains Chinese labels, messages, UI copy, sample data, or exported content.
2. Keep the literal Chinese text readable in source files whenever the format allows it.
3. Set reader, writer, serializer, response, and export encodings explicitly instead of relying on platform defaults.
4. Add a focused verification step when generating CSV, Excel, or download code. Use a sample such as `错误：学号重复`.
5. If the surrounding toolchain cannot safely preserve raw Chinese, explain the constraint and choose the narrowest necessary escaping.

## Common Fixes

- Python JSON: use `json.dumps(data, ensure_ascii=False)`.
- Python text files: pass `encoding="utf-8"`; for Excel-facing CSV on Windows use `encoding="utf-8-sig"`.
- Node.js text output: write with `utf8`; for Excel-facing CSV prepend BOM when needed.
- Java or Kotlin: use `StandardCharsets.UTF_8` explicitly for file I/O and HTTP responses.
- C#: use `new UTF8Encoding(true)` when BOM is needed for Excel-facing CSV.
- Browser downloads: set `charset=utf-8`; if exporting CSV for Excel, include BOM or switch to `.xlsx`.
- Spreadsheet libraries: prefer native `.xlsx` writers because worksheet text is Unicode-safe by design.

## Before Finishing

- Confirm the final file actually contains readable Chinese characters.
- Confirm sample exports open correctly in the target app.
- Leave Chinese literals readable in code unless a strict protocol forbids it.
