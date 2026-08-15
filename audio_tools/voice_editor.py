#!/usr/bin/env python3
"""剧情配音可视化编辑器（仅使用 Python 标准库）。

从项目根目录运行：uv run audio_tools/voice_editor.py
然后浏览器打开 http://127.0.0.1:8765
"""

from __future__ import annotations

import argparse
import hashlib
import json
import mimetypes
import os
import re
import shutil
import tempfile
import threading
import uuid
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, quote, urlparse

PROJECT_ROOT = Path(__file__).resolve().parents[1]
PLOTLINE_ROOT = PROJECT_ROOT / "plotline"
VOICE_ROOT = PROJECT_ROOT / "assets" / "VO"
CHAT_MARKER = "PlotlineManager.chat"
FILE_OPERATION_LOCK = threading.Lock()


def script_path(plot_id: str) -> Path:
    parts = plot_id.split("-")
    if len(parts) < 3 or not all(part.isdigit() for part in parts):
        raise ValueError("无效剧本 ID")
    return PLOTLINE_ROOT / parts[0] / f"{parts[0]}-{parts[1]}" / f"{plot_id}.gd"


def voice_dir(plot_id: str) -> Path:
    path = script_path(plot_id)
    return VOICE_ROOT / path.relative_to(PLOTLINE_ROOT).with_suffix("")


def list_scripts() -> list[dict]:
    result = []
    for path in sorted(PLOTLINE_ROOT.glob("*/*/*.gd")):
        plot_id = path.stem
        try:
            lines = parse_chats(path.read_text("utf-8"))
        except Exception as exc:  # 单个脚本异常不阻断编辑器
            result.append({"id": plot_id, "count": 0, "error": str(exc)})
            continue
        directory = voice_dir(plot_id)
        live_hashes = {item["hash"] for item in lines if item["hash"]}
        files = list(directory.glob("*.ogg")) if directory.is_dir() else []
        result.append({
            "id": plot_id,
            "count": len(lines),
            "voiced": sum(bool(item["hash"] and (directory / f'{item["hash"]}.ogg').is_file()) for item in lines),
            "dead": sum(path.stem not in live_hashes for path in files),
        })
    return result


def _extract_call(source: str, open_pos: int) -> tuple[str, int]:
    depth = 0
    quote_char = ""
    escaped = False
    for pos in range(open_pos, len(source)):
        char = source[pos]
        if quote_char:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote_char:
                quote_char = ""
            continue
        if char in ('"', "'"):
            quote_char = char
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return source[open_pos + 1:pos], pos + 1
    raise ValueError(f"第 {source.count(chr(10), 0, open_pos) + 1} 行的 chat() 未闭合")


def _split_arguments(arguments: str) -> list[str]:
    parts, start, depth = [], 0, 0
    quote_char, escaped = "", False
    for pos, char in enumerate(arguments):
        if quote_char:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote_char:
                quote_char = ""
            continue
        if char in ('"', "'"):
            quote_char = char
        elif char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        elif char == "," and depth == 0:
            parts.append(arguments[start:pos].strip())
            start = pos + 1
    parts.append(arguments[start:].strip())
    return parts


def _gd_string(expression: str) -> str | None:
    expression = expression.strip()
    if len(expression) < 2 or expression[0] not in ('"', "'") or expression[-1] != expression[0]:
        return None
    if expression[0] == '"':
        try:
            return json.loads(expression)
        except json.JSONDecodeError:
            pass
    body = expression[1:-1]
    return bytes(body, "utf-8").decode("unicode_escape") if "\\" in body and body.isascii() else body.replace("\\'", "'").replace("\\n", "\n")


def _gd_value(expression: str):
    """解析 chat 参数使用的字面量子集；无法静态确定时抛出 ValueError。"""
    expression = expression.strip()
    string_value = _gd_string(expression)
    if string_value is not None:
        return string_value
    if expression.startswith("[") and expression.endswith("]"):
        inner = expression[1:-1].strip()
        return [] if not inner else [_gd_value(part) for part in _split_arguments(inner)]
    if expression == "true":
        return True
    if expression == "false":
        return False
    if expression in ("null", "<null>"):
        return None
    if re.fullmatch(r"[-+]?\d+", expression):
        return int(expression)
    if re.fullmatch(r"[-+]?(?:\d+\.\d*|\d*\.\d+)(?:[eE][-+]?\d+)?", expression):
        return float(expression)
    raise ValueError(f"无法静态解析参数：{expression}")


def _chat_hash(values: list) -> str:
    # 与 Godot JSON.stringify([speaker, text, illustrations, direction]) 的紧凑 JSON 对齐。
    signature = json.dumps(values, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(signature.encode("utf-8")).hexdigest()


def validate_voice_key(key: str) -> str:
    # 安全的跨平台 basename；保留对旧中文文件名的支持。
    invalid_chars = '<>:"/\\|?*'
    reserved = {"CON", "PRN", "AUX", "NUL", *(f"COM{i}" for i in range(1, 10)), *(f"LPT{i}" for i in range(1, 10))}
    base_name = key.split(".", 1)[0].upper()
    if (
        not key or key in (".", "..") or key[-1] in (".", " ")
        or any(char in invalid_chars or ord(char) < 32 for char in key)
        or base_name in reserved
    ):
        raise ValueError("无效语音文件名")
    return key


def _find_chat_marker(source: str, start: int) -> int:
    """只在 GDScript 代码区寻找调用，跳过字符串和行注释。"""
    pos = start
    while pos < len(source):
        char = source[pos]
        if char == "#":
            newline = source.find("\n", pos + 1)
            pos = len(source) if newline < 0 else newline + 1
            continue
        if char in ('"', "'"):
            quote_char = char
            triple = source.startswith(char * 3, pos)
            pos += 3 if triple else 1
            while pos < len(source):
                if triple and source.startswith(quote_char * 3, pos):
                    pos += 3
                    break
                if not triple and source[pos] == quote_char:
                    pos += 1
                    break
                if source[pos] == "\\":
                    pos += 2
                else:
                    pos += 1
            continue
        if source.startswith(CHAT_MARKER, pos):
            before = source[pos - 1] if pos else ""
            after_pos = pos + len(CHAT_MARKER)
            after = source[after_pos] if after_pos < len(source) else ""
            if (not before or not (before.isalnum() or before == "_")) and (not after or not (after.isalnum() or after == "_")):
                return pos
        pos += 1
    return -1


def parse_chats(source: str) -> list[dict]:
    result, cursor = [], 0
    while True:
        marker = _find_chat_marker(source, cursor)
        if marker < 0:
            break
        open_pos = marker + len(CHAT_MARKER)
        while open_pos < len(source) and source[open_pos].isspace():
            open_pos += 1
        if open_pos >= len(source) or source[open_pos] != "(":
            cursor = open_pos
            continue
        call, cursor = _extract_call(source, open_pos)
        args = _split_arguments(call)
        if len(args) < 2:
            continue
        speaker = _gd_string(args[0])
        if speaker is None and args[0].startswith("["):
            array_args = _split_arguments(args[0][1:-1])
            speaker = _gd_string(array_args[0]) if array_args else None
        text = _gd_string(args[1])
        voice_hash = None
        hash_error = ""
        try:
            values = [
                _gd_value(args[0]),
                _gd_value(args[1]),
                _gd_value(args[2]) if len(args) >= 3 else [],
                _gd_value(args[3]) if len(args) >= 4 else "auto",
            ]
            voice_hash = _chat_hash(values)
        except ValueError as exc:
            hash_error = str(exc)
        result.append({
            "index": len(result) + 1,
            "speaker": speaker if speaker is not None else args[0],
            "text": text if text is not None else args[1],
            "line": source.count("\n", 0, marker) + 1,
            "hash": voice_hash,
            "hash_error": hash_error,
        })
    return result


def remove_parenthetical(text: str) -> str:
    output, depth = [], 0
    for char in text:
        if char == "（":
            depth += 1
        elif char == "）" and depth:
            depth -= 1
        elif depth == 0:
            output.append(char)
    return "".join(output)


def plain_text(lines: list[dict]) -> str:
    output = []
    for item in lines:
        text = re.sub(r"\[br\]", " ", item["text"], flags=re.I)
        text = re.sub(r"\[[^\]]*\]", "", text)
        text = remove_parenthetical(text)
        text = re.sub(r"\s+", " ", text).strip()
        output.append(f'{item["speaker"]}：{text}')
    return "\n".join(output)


HTML = r'''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>剧情配音编辑器</title><style>
:root{color-scheme:dark;--bg:#171b1f;--panel:#20262b;--fill:#293138;--line:#3a444b;--text:#edf1f2;--muted:#9ba8ad;--accent:#75b8ae;--danger:#d98c82}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font-family:system-ui,"Microsoft YaHei",sans-serif}.app{max-width:1180px;margin:auto;padding:22px}.top{display:flex;gap:12px;align-items:end;flex-wrap:wrap;margin-bottom:16px}.field{display:grid;gap:6px}.field label,.status{font-size:13px;color:var(--muted)}select,button{font:inherit;color:var(--text);background:var(--fill);border:1px solid var(--line);border-radius:7px;padding:9px 12px}select{min-width:260px}button{cursor:pointer}button:hover{border-color:var(--accent)}button.primary{background:var(--accent);color:#10201e;border-color:var(--accent)}.summary{margin-left:auto;color:var(--muted)}.notice{padding:10px 12px;background:var(--panel);border:1px solid var(--line);border-radius:7px;margin-bottom:12px;color:var(--muted);font-size:13px}.list{display:grid;gap:7px}.row{display:grid;grid-template-columns:230px 1fr;background:var(--panel);border:1px solid var(--line);border-radius:9px;min-height:82px;overflow:hidden}.row.dragover{outline:2px solid var(--accent);outline-offset:2px}.voice{padding:10px;border-right:1px solid var(--line);display:grid;grid-template-columns:auto 1fr;gap:7px;align-content:center}.number{grid-row:1/3;align-self:center;color:var(--muted);font-variant-numeric:tabular-nums;width:28px}.voice button{padding:7px 9px}.voice .play[draggable=true]{cursor:grab}.voice .play.missing{color:var(--muted);cursor:default}.upload input{display:none}.upload{display:block}.upload button{width:100%}.dialogue{padding:12px 15px;display:grid;gap:7px;align-content:center}.speaker{font-weight:700;color:var(--accent)}.text{line-height:1.55;white-space:pre-wrap}.meta{font-size:12px;color:var(--muted)}.dead-panel{margin:14px 0;padding:12px;background:var(--panel);border:1px solid var(--line);border-radius:9px}.dead-title{display:flex;justify-content:space-between;align-items:center;margin-bottom:9px}.dead-title strong{color:var(--danger)}.dead-list{display:flex;gap:8px;flex-wrap:wrap}.dead-item{display:flex;gap:6px;align-items:center;background:var(--fill);border:1px solid var(--line);border-radius:7px;padding:6px}.dead-item code{max-width:280px;overflow:hidden;text-overflow:ellipsis}.dead-item button{padding:5px 8px;cursor:grab}.empty{text-align:center;padding:60px;color:var(--muted)}@media(max-width:680px){.row{grid-template-columns:1fr}.voice{border-right:0;border-bottom:1px solid var(--line)}.summary{margin-left:0;width:100%}}
</style></head><body><main class="app"><div class="top"><div class="field"><label for="scripts">剧本</label><select id="scripts"></select></div><button id="refresh">刷新</button><button class="primary" id="copy">复制对话纯文本</button><span class="summary" id="summary"></span></div><div class="notice">语音按完整 chat 参数的 SHA-256 挂载。拖动已有语音或下方“死音频”到任意对话可交换/挂载；也可把本地 <code>.ogg</code> 文件直接拖到对话行上传。纯文本会过滤 BBCode 和全角括号（……）内容。</div><div id="status" class="status"></div><section class="dead-panel"><div class="dead-title"><strong>死音频文件</strong><span id="deadCount"></span></div><div id="deadList" class="dead-list"></div></section><section id="list" class="list"></section></main>
<script>
const $=s=>document.querySelector(s);let current='',lines=[],orphans=[],dragKey='';
async function request(url,options){const r=await fetch(url,options);if(!r.ok)throw new Error(await r.text());return r.json()}
function msg(s,error=false){$('#status').textContent=s;$('#status').style.color=error?'var(--danger)':'var(--muted)'}
async function loadScripts(keep=true){try{const data=await request('/api/scripts');const old=keep?current:'';$('#scripts').innerHTML=data.scripts.map(s=>`<option value="${s.id}">${s.id} · ${s.voiced||0}/${s.count} · 死音频 ${s.dead||0}${s.error?' · 解析错误':''}</option>`).join('');current=data.scripts.some(s=>s.id===old)?old:(data.scripts[0]?.id||'');$('#scripts').value=current;await loadDialogue()}catch(e){msg(e.message,true)}}
async function loadDialogue(){dragKey='';current=$('#scripts').value;if(!current){$('#list').innerHTML='<div class="empty">没有找到剧本</div>';return}try{const data=await request('/api/dialogue?id='+encodeURIComponent(current));lines=data.lines;orphans=data.orphans;$('#summary').textContent=`${lines.filter(x=>x.voiced).length} / ${lines.length} 句有语音`;render();msg(`已加载 ${current}`)}catch(e){msg(e.message,true)}}
function render(){const stamp=Date.now();$('#list').innerHTML=lines.map(x=>`<article class="row" data-index="${x.index}" data-key="${x.hash||''}"><div class="voice"><span class="number">${x.index}</span><button class="play ${x.voiced?'':'missing'}" ${x.voiced?`draggable="true" data-key="${x.hash}" data-audio="${x.audio}&v=${stamp}"`:'disabled'}>${x.hash?(x.voiced?'▶ 播放语音':'— 暂无语音'):'! 参数无法解析'}</button><label class="upload"><input type="file" accept="audio/ogg,.ogg" data-key="${x.hash||''}" ${x.hash?'':'disabled'}><button type="button" ${x.hash?'':'disabled'}>${x.voiced?'重新上传':'上传 .ogg'}</button></label></div><div class="dialogue"><div class="speaker">${escapeHtml(x.speaker)}</div><div class="text">${escapeHtml(x.text)}</div><div class="meta">脚本第 ${x.line} 行 · ${x.hash?`哈希 ${x.hash.slice(0,12)}…`:escapeHtml(x.hash_error)}</div></div></article>`).join('');renderDead(stamp);bindRows()}
function renderDead(stamp){$('#deadCount').textContent=`${orphans.length} 个`;$('#deadList').innerHTML=orphans.length?orphans.map(x=>`<div class="dead-item"><button class="dead-play" draggable="true" data-key="${escapeHtml(x.key)}" data-audio="${x.audio}&v=${stamp}">▶</button><code title="${escapeHtml(x.key)}.ogg">${escapeHtml(x.key)}.ogg</code></div>`).join(''):'<span class="status">当前剧本没有死音频</span>'}
function escapeHtml(s){return String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function bindRows(){document.querySelectorAll('.play:not(.missing),.dead-play').forEach(b=>{b.onclick=()=>{stopAudio();window.preview=new Audio(b.dataset.audio);window.preview.play()};b.ondragstart=e=>{dragKey=b.dataset.key;e.dataTransfer.effectAllowed='move';e.dataTransfer.setData('application/x-voice-key',dragKey);b.ondragend=()=>{dragKey=''}}});document.querySelectorAll('.upload button:not(:disabled)').forEach(b=>b.onclick=()=>b.previousElementSibling.click());document.querySelectorAll('input[type=file]').forEach(i=>i.onchange=()=>uploadFile(i.files[0],i.dataset.key,i));document.querySelectorAll('.row').forEach(r=>{r.ondragover=e=>{if(r.dataset.key&&(e.dataTransfer.files.length||e.dataTransfer.types.includes('Files')||dragKey||e.dataTransfer.types.includes('application/x-voice-key'))){e.preventDefault();r.classList.add('dragover')}};r.ondragleave=()=>r.classList.remove('dragover');r.ondrop=async e=>{e.preventDefault();r.classList.remove('dragover');const to=r.dataset.key;if(!to)return;if(e.dataTransfer.files.length){await uploadFile(e.dataTransfer.files[0],to);return}const from=e.dataTransfer.getData('application/x-voice-key')||dragKey;dragKey='';if(from&&from!==to)await swap(from,to)}})}
function stopAudio(){if(window.preview){window.preview.pause();window.preview=null}}
async function uploadFile(file,key,input=null){if(!file||!key)return;if(!file.name.toLowerCase().endsWith('.ogg')){msg('只接受 .ogg 文件',true);return}try{msg(`正在上传 ${file.name}…`);await request(`/api/upload?id=${encodeURIComponent(current)}&key=${encodeURIComponent(key)}`,{method:'POST',headers:{'Content-Type':'audio/ogg'},body:file});await loadDialogue();msg(`已挂载 ${file.name}`)}catch(e){msg(e.message,true)}finally{if(input)input.value=''}}
async function swap(from,to){try{stopAudio();await request('/api/swap',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:current,from,to})});await loadDialogue();msg('语音已交换/挂载')}catch(e){msg(e.message,true)}finally{dragKey=''}}
$('#scripts').onchange=loadDialogue;$('#refresh').onclick=()=>loadScripts(true);$('#copy').onclick=async()=>{try{const d=await request('/api/plain?id='+encodeURIComponent(current));await navigator.clipboard.writeText(d.text);msg(`已复制 ${d.count} 行纯文本`)}catch(e){msg(e.message,true)}};loadScripts(false);
</script></body></html>'''


class Handler(BaseHTTPRequestHandler):
    server_version = "VoiceEditor/1.0"

    def log_message(self, fmt: str, *args) -> None:
        print(f"[voice-editor] {self.address_string()} - {fmt % args}")

    def json_response(self, data: object, status: int = 200) -> None:
        payload = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def error_response(self, message: str, status: int = 400) -> None:
        self.json_response({"error": message}, status)

    def query(self) -> dict[str, list[str]]:
        return parse_qs(urlparse(self.path).query)

    def get_plot_id(self) -> str:
        plot_id = self.query().get("id", [""])[0]
        path = script_path(plot_id)
        if not path.is_file():
            raise ValueError("剧本不存在")
        return plot_id

    def do_GET(self) -> None:
        try:
            parsed = urlparse(self.path)
            if parsed.path == "/":
                body = HTML.encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            elif parsed.path == "/api/scripts":
                self.json_response({"scripts": list_scripts()})
            elif parsed.path == "/api/dialogue":
                plot_id = self.get_plot_id()
                lines = parse_chats(script_path(plot_id).read_text("utf-8"))
                directory = voice_dir(plot_id)
                live_hashes = {item["hash"] for item in lines if item["hash"]}
                for item in lines:
                    key = item["hash"]
                    item["voiced"] = bool(key and (directory / f"{key}.ogg").is_file())
                    item["audio"] = f'/audio?id={quote(plot_id)}&key={quote(key)}' if key else ""
                orphans = []
                if directory.is_dir():
                    for path in sorted(directory.glob("*.ogg")):
                        if path.stem not in live_hashes:
                            orphans.append({
                                "key": path.stem,
                                "audio": f'/audio?id={quote(plot_id)}&key={quote(path.stem)}',
                            })
                self.json_response({"id": plot_id, "lines": lines, "orphans": orphans})
            elif parsed.path == "/api/plain":
                plot_id = self.get_plot_id()
                lines = parse_chats(script_path(plot_id).read_text("utf-8"))
                self.json_response({"text": plain_text(lines), "count": len(lines)})
            elif parsed.path == "/audio":
                plot_id = self.get_plot_id()
                key = validate_voice_key(self.query().get("key", [""])[0])
                path = voice_dir(plot_id) / f"{key}.ogg"
                if not path.is_file():
                    self.send_error(404)
                    return
                body = path.read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", mimetypes.guess_type(path.name)[0] or "audio/ogg")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(body)
            else:
                self.send_error(404)
        except (ValueError, OSError) as exc:
            self.error_response(str(exc))

    def do_POST(self) -> None:
        try:
            parsed = urlparse(self.path)
            if parsed.path == "/api/upload":
                plot_id = self.get_plot_id()
                key = validate_voice_key(self.query().get("key", [""])[0])
                lines = parse_chats(script_path(plot_id).read_text("utf-8"))
                live_hashes = {item["hash"] for item in lines if item["hash"]}
                if key not in live_hashes:
                    raise ValueError("目标对话哈希不存在")
                length = int(self.headers.get("Content-Length", "0"))
                if length <= 0 or length > 100 * 1024 * 1024:
                    raise ValueError("文件为空或超过 100 MB")
                body = self.rfile.read(length)
                if not body.startswith(b"OggS"):
                    raise ValueError("文件不是有效的 OGG 容器")
                directory = voice_dir(plot_id)
                directory.mkdir(parents=True, exist_ok=True)
                destination = directory / f"{key}.ogg"
                with tempfile.NamedTemporaryFile(dir=directory, delete=False) as tmp:
                    tmp.write(body)
                    temp_path = Path(tmp.name)
                with FILE_OPERATION_LOCK:
                    os.replace(temp_path, destination)
                self.json_response({"ok": True})
            elif parsed.path == "/api/swap":
                length = int(self.headers.get("Content-Length", "0"))
                if length <= 0 or length > 16 * 1024:
                    raise ValueError("交换请求为空或过大")
                data = json.loads(self.rfile.read(length))
                if not isinstance(data, dict):
                    raise ValueError("交换请求必须是 JSON 对象")
                plot_id = str(data.get("id", ""))
                path = script_path(plot_id)
                if not path.is_file():
                    raise ValueError("剧本不存在")
                first = validate_voice_key(str(data["from"]))
                second = validate_voice_key(str(data["to"]))
                live_hashes = {item["hash"] for item in parse_chats(path.read_text("utf-8")) if item["hash"]}
                if first == second or second not in live_hashes:
                    raise ValueError("目标对话哈希无效")
                directory = voice_dir(plot_id)
                a, b = directory / f"{first}.ogg", directory / f"{second}.ogg"
                directory.mkdir(parents=True, exist_ok=True)
                with FILE_OPERATION_LOCK:
                    if not a.exists():
                        raise ValueError("被拖动的语音不存在")
                    if not b.exists():
                        os.replace(a, b)
                    else:
                        # 先复制两份独立备份，再逐个原子替换。第二步失败时原始 B 仍在 b，
                        # 只需用 backup_a 恢复 a；任何情况下都不会丢失两份音频内容。
                        token = uuid.uuid4().hex
                        backup_a = directory / f".voice_swap_a_{token}.tmp"
                        backup_b = directory / f".voice_swap_b_{token}.tmp"
                        preserve_backup_a = False
                        shutil.copy2(a, backup_a)
                        try:
                            shutil.copy2(b, backup_b)
                        except OSError:
                            backup_a.unlink(missing_ok=True)
                            raise
                        try:
                            os.replace(backup_b, a)
                            try:
                                os.replace(backup_a, b)
                            except OSError as swap_error:
                                try:
                                    os.replace(backup_a, a)
                                except OSError as restore_error:
                                    preserve_backup_a = True
                                    raise OSError(
                                        f"交换失败且自动恢复失败；原始源文件保留在 {backup_a.name}: {restore_error}"
                                    ) from swap_error
                                raise
                        finally:
                            if backup_b.exists():
                                backup_b.unlink()
                            if backup_a.exists() and not preserve_backup_a:
                                backup_a.unlink()
                self.json_response({"ok": True})
            else:
                self.send_error(404)
        except (ValueError, TypeError, AttributeError, KeyError, OSError, json.JSONDecodeError) as exc:
            self.error_response(str(exc))


def main() -> None:
    parser = argparse.ArgumentParser(description="剧情配音可视化编辑器")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--no-browser", action="store_true")
    args = parser.parse_args()
    VOICE_ROOT.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    url = f"http://{args.host}:{args.port}"
    print(f"剧情配音编辑器已启动：{url}")
    print("按 Ctrl+C 停止。")
    if not args.no_browser:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
