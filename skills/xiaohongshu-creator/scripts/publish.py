"""
小红书内容发布脚本
支持图文笔记发布、定时发布、状态检查

登录方案：使用系统 Edge/Chrome 二进制 + 独立 profile 目录。
不占用系统浏览器的 profile，因此浏览器运行时也可正常使用。
首次运行需在弹出的窗口中登录一次，之后永久保存登录状态。
"""

import asyncio
import argparse
import os
import sys
import json
import time
from pathlib import Path
from playwright.async_api import async_playwright


def _get_system_browser() -> tuple[str, str]:
    """返回 (user_data_dir, channel)，优先 Edge，其次 Chrome"""
    local = os.environ.get("LOCALAPPDATA", "")
    prog = os.environ.get("PROGRAMFILES", "")
    prog86 = os.environ.get("PROGRAMFILES(X86)", "")

    edge_exe = Path(prog86) / "Microsoft" / "Edge" / "Application" / "msedge.exe"
    if not edge_exe.exists():
        edge_exe = Path(prog) / "Microsoft" / "Edge" / "Application" / "msedge.exe"
    edge_data = Path(local) / "Microsoft" / "Edge" / "User Data"
    if edge_exe.exists() and edge_data.exists():
        return str(edge_data), "msedge"

    chrome_exe = Path(prog) / "Google" / "Chrome" / "Application" / "chrome.exe"
    if not chrome_exe.exists():
        chrome_exe = Path(prog86) / "Google" / "Chrome" / "Application" / "chrome.exe"
    if not chrome_exe.exists():
        chrome_exe = Path(local) / "Google" / "Chrome" / "Application" / "chrome.exe"
    chrome_data = Path(local) / "Google" / "Chrome" / "User Data"
    if chrome_exe.exists() and chrome_data.exists():
        return str(chrome_data), "chrome"

    return "", ""


async def _launch_context(p):
    """
    用系统 Edge/Chrome 的默认用户数据目录启动，直接复用已登录账号。
    注意：运行前需关闭所有 Edge/Chrome 窗口，否则 profile 目录被锁定。
    """
    user_data_dir, channel = _get_system_browser()
    if not user_data_dir:
        print("未找到系统 Edge 或 Chrome，请安装后重试")
        sys.exit(1)
    print(f"使用浏览器: {channel}，用户数据: {user_data_dir}")
    try:
        context = await p.chromium.launch_persistent_context(
            user_data_dir=user_data_dir,
            channel=channel,
            headless=False,
            args=["--disable-blink-features=AutomationControlled"],
        )
        return context
    except Exception as e:
        msg = str(e).lower()
        if "already in use" in msg or "winerror 32" in msg or "lock" in msg:
            print("错误: 请先关闭所有 Edge/Chrome 窗口后再运行此脚本")
        else:
            print(f"浏览器启动失败: {e}")
        sys.exit(1)


async def _is_logged_in(context) -> bool:
    """通过 cookie 判断是否已登录小红书"""
    cookies = await context.cookies("https://www.xiaohongshu.com")
    names = {c["name"] for c in cookies}
    found = names & {"a1", "web_session", "webId", "gid"}
    if found:
        print(f"检测到登录 cookie: {found}")
        return True
    return False


async def _wait_for_login(context) -> bool:
    """
    打开小红书登录页，引导用户登录。
    每 3 秒检测一次 cookie，最多等待 5 分钟。
    返回登录后的 page 对象，失败返回 None。
    """
    page = await context.new_page()
    await page.goto("https://www.xiaohongshu.com", wait_until="domcontentloaded", timeout=30000)
    print("请在打开的浏览器窗口中登录小红书，登录完成后脚本将自动继续...")
    for _ in range(100):  # 最多等 5 分钟
        await asyncio.sleep(3)
        if await _is_logged_in(context):
            print("登录成功！")
            return page
    print("等待登录超时")
    await page.close()
    return None


async def check_login(page):
    """检查当前页面的登录状态（兼容旧调用）"""
    return await _is_logged_in(page.context)


XHS_TITLE_MAX_LEN = 20

_EMOJI_RE_PATTERN = (
    r'[\U0001F600-\U0001F64F\U0001F300-\U0001F5FF\U0001F680-\U0001F6FF'
    r'\U0001F1E0-\U0001F1FF\U00002702-\U000027B0\U0001F900-\U0001F9FF'
    r'\U0001FA00-\U0001FA6F\U0001FA70-\U0001FAFF\U00002600-\U000026FF'
    r'\U0000FE00-\U0000FE0F\U0000200D]+'
)


def _strip_emoji(text: str) -> str:
    """去掉文本中的所有 emoji 字符。"""
    import re
    return re.sub(_EMOJI_RE_PATTERN, '', text)


def _make_image_text(content: str, max_len: int = 500) -> str:
    """从正文中提取适合生成配图的简短文字。去掉 emoji 和 # 标签，取前 max_len 字。"""
    import re
    text = _strip_emoji(content)
    text = re.sub(r'#\S+', '', text)
    text = text.strip()
    if len(text) > max_len:
        text = text[:max_len]
    return text if text else content[:max_len]


def _truncate_title(title: str, max_len: int = XHS_TITLE_MAX_LEN) -> str:
    """确保标题 ≤ max_len 字。先去 emoji，再智能截断。"""
    # 先去掉 emoji，小红书标题不适合放 emoji 且会占字数
    title = _strip_emoji(title).strip()
    if len(title) <= max_len:
        return title
    print(f"警告: 标题超过{max_len}字（当前{len(title)}字），自动截断")
    truncated = title[:max_len]
    # 尝试在最后一个标点或空格处断开，避免截断在词中间
    for sep in ['！', '!', '，', ',', '。', '？', '?', '｜', '|', ' ', '、']:
        idx = truncated.rfind(sep)
        if idx > max_len // 2:
            truncated = truncated[:idx + 1]
            break
    return truncated


async def publish_content(title: str, content: str, images=None, tags=None):
    """
    发布小红书笔记（文字配图模式）。

    流程：
    1. 用简短摘要文字生成配图图片
    2. 进入发布页后，填写真正的标题（≤20字）和完整正文
    """
    title = _truncate_title(title)

    # 为文字配图阶段准备简短文字
    image_text = _make_image_text(content)

    async with async_playwright() as p:
        context = await _launch_context(p)

        try:
            if not await _is_logged_in(context):
                login_page = await _wait_for_login(context)
                if not login_page:
                    return {"status": "not_logged_in"}
                page = login_page
            else:
                page = await context.new_page()

            # 1. 直接访问图文发布页
            print("打开图文发布页...")
            await page.goto(
                "https://creator.xiaohongshu.com/publish/publish?from=menu&target=image",
                wait_until="networkidle",
                timeout=60000,
            )
            await asyncio.sleep(2)

            # 2. 点击"文字配图"
            print("点击文字配图...")
            text_to_image_btn = None
            for sel in [
                "text=文字配图",
                "div:has-text('文字配图')",
                "span:has-text('文字配图')",
                "button:has-text('文字配图')",
                "[class*='text-image']",
                "[class*='textImage']",
            ]:
                try:
                    text_to_image_btn = await page.wait_for_selector(sel, timeout=3000)
                    if text_to_image_btn:
                        break
                except Exception:
                    continue
            if text_to_image_btn:
                await text_to_image_btn.click()
                await asyncio.sleep(2)
                print("已进入文字配图模式")
            else:
                print("未找到文字配图按钮，请检查页面")
                return {"status": "error", "message": "未找到文字配图按钮"}

            # 3. 在文字配图区域填入简短摘要（仅用于生成图片）
            print("填写配图文字（简短摘要）...")
            content_input = None
            for sel in [
                "div[contenteditable='true']",
                "textarea",
                ".editor-content",
                "div[class*='editor']",
            ]:
                try:
                    content_input = await page.wait_for_selector(sel, timeout=3000)
                    if content_input:
                        break
                except Exception:
                    continue
            if content_input:
                await content_input.click()
                await asyncio.sleep(0.3)
                await page.keyboard.press("Control+a")
                await page.keyboard.press("Delete")
                await page.evaluate("(text) => navigator.clipboard.writeText(text)", image_text)
                await page.keyboard.press("Control+v")
                await asyncio.sleep(0.5)
            else:
                print("未找到文字输入框")

            # 4. 点击生成图片
            print("点击生成图片...")
            generate_btn = None
            for sel in [
                "text=生成图片",
                "button:has-text('生成图片')",
                "div:has-text('生成图片')",
                "span:has-text('生成图片')",
                "[class*='generate']",
            ]:
                try:
                    generate_btn = await page.wait_for_selector(sel, timeout=5000)
                    if generate_btn:
                        break
                except Exception:
                    continue
            if generate_btn:
                await generate_btn.click()
                print("已点击生成图片，等待生成...")
                await asyncio.sleep(10)
            else:
                print("未找到生成图片按钮")
                return {"status": "error", "message": "未找到生成图片按钮"}

            # 5. 点击"下一步"进入发布编辑页
            print("点击下一步...")
            next_btn = None
            for sel in [
                "text=下一步",
                "button:has-text('下一步')",
                "div:has-text('下一步')",
                "span:has-text('下一步')",
            ]:
                try:
                    next_btn = await page.wait_for_selector(sel, timeout=10000)
                    if next_btn:
                        break
                except Exception:
                    continue
            if next_btn:
                await next_btn.click()
                await asyncio.sleep(3)
                print("已进入发布编辑页")
            else:
                print("未找到下一步按钮")
                return {"status": "error", "message": "未找到下一步按钮"}

            # 6. 在发布页填写标题（已确保 ≤ 20 字）
            print(f"填写标题: {title}（{len(title)}字）")
            title_input = None
            for sel in [
                "input[placeholder*='标题']",
                "input[placeholder*='title']",
                ".title-input input",
                "input[class*='title']",
            ]:
                try:
                    title_input = await page.wait_for_selector(sel, timeout=5000)
                    if title_input:
                        break
                except Exception:
                    continue
            if title_input:
                await title_input.click()
                await page.keyboard.press("Control+a")
                await page.keyboard.press("Delete")
                await page.evaluate("(text) => navigator.clipboard.writeText(text)", title)
                await page.keyboard.press("Control+v")
                await asyncio.sleep(0.5)
            else:
                print("未找到标题输入框")

            # 7. 在发布页填写完整正文描述
            print("填写正文描述...")
            desc_input = None
            for sel in [
                "div[contenteditable='true']",
                "textarea",
                ".editor-content",
                "div[class*='editor']",
            ]:
                try:
                    desc_input = await page.wait_for_selector(sel, timeout=5000)
                    if desc_input:
                        break
                except Exception:
                    continue
            if desc_input:
                await desc_input.click()
                await asyncio.sleep(0.3)
                await page.keyboard.press("Control+a")
                await page.keyboard.press("Delete")
                await page.evaluate("(text) => navigator.clipboard.writeText(text)", content)
                await page.keyboard.press("Control+v")
                await asyncio.sleep(0.5)
            else:
                print("未找到正文输入框")

            # 8. 等待图片上传完成，然后点击发布
            print("等待图片上传完成...")
            for _ in range(30):  # 最多等 30 秒
                # 检查是否还有上传中的进度条/loading状态
                uploading = await page.query_selector(
                    ", ".join([
                        "[class*='upload'][class*='loading']",
                        "[class*='uploading']",
                        "[class*='progress']",
                        ".upload-loading",
                        "[class*='spinner']",
                    ])
                )
                if not uploading:
                    break
                await asyncio.sleep(1)
            await asyncio.sleep(2)

            print("尝试发布...")
            await asyncio.sleep(1)

            publish_button = None
            try:
                buttons = await page.query_selector_all("button:has-text('发布')")
                publish_button = buttons[-1] if buttons else None
            except Exception:
                pass

            if publish_button:
                print("点击发布按钮...")
                await publish_button.click()
                await asyncio.sleep(3)

                try:
                    await page.wait_for_selector(
                        "text=发布成功, .success-toast", timeout=5000
                    )
                    print("发布成功!")
                    return {"status": "published", "title": title}
                except Exception:
                    pass

                print("请在浏览器中确认发布...")
                return {"status": "ready_to_confirm", "title": title}
            else:
                print("未找到发布按钮，请手动点击")
                return {"status": "ready", "title": title}

        finally:
            await context.close()


async def check_status():
    """检查登录状态"""
    async with async_playwright() as p:
        context = await _launch_context(p)

        try:
            if await _is_logged_in(context):
                print("已登录小红书")
                return {"status": "logged_in"}

            print("未登录小红书，请在打开的浏览器窗口中登录...")
            login_page = await _wait_for_login(context)
            if login_page:
                return {"status": "logged_in"}
            return {"status": "not_logged_in"}

        finally:
            await context.close()


def _read_content(value: str | None) -> str | None:
    """如果 value 以 @开头，视为文件路径并读取内容；否则原样返回。"""
    if value and value.startswith("@"):
        filepath = value[1:]
        try:
            with open(filepath, "r", encoding="utf-8") as f:
                return f.read().strip()
        except Exception as e:
            print(f"读取文件失败 {filepath}: {e}")
            sys.exit(1)
    return value


def main():
    parser = argparse.ArgumentParser(description="小红书内容发布工具")
    parser.add_argument("command", help="命令: publish, schedule, status")
    parser.add_argument("title", nargs="?", help="笔记标题（或 @文件路径）")
    parser.add_argument("content", nargs="?", help="笔记正文（或 @文件路径）")
    parser.add_argument("--images", help="图片路径(逗号分隔)")
    parser.add_argument("--tags", help="标签(逗号分隔)")
    parser.add_argument("--delay", type=int, help="延迟秒数(定时发布)")

    args = parser.parse_args()

    if args.command == "status":
        result = asyncio.run(check_status())
        print(json.dumps(result, ensure_ascii=False))

    elif args.command == "publish":
        title = _read_content(args.title)
        content = _read_content(args.content)
        if not title or not content:
            print("错误: publish命令需要title和content参数（支持 @文件路径）")
            sys.exit(1)

        images = args.images.split(",") if args.images else None
        tags = args.tags.split(",") if args.tags else None

        result = asyncio.run(publish_content(title, content, images, tags))
        print(json.dumps(result, ensure_ascii=False))

    elif args.command == "schedule":
        title = _read_content(args.title)
        content = _read_content(args.content)
        if not title or not content:
            print("错误: schedule命令需要title和content参数（支持 @文件路径）")
            sys.exit(1)

        delay = args.delay or 0
        print(f"定时发布: {delay}秒后")
        time.sleep(delay)

        images = args.images.split(",") if args.images else None
        tags = args.tags.split(",") if args.tags else None

        result = asyncio.run(publish_content(title, content, images, tags))
        print(json.dumps(result, ensure_ascii=False))

    else:
        print(f"未知命令: {args.command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
