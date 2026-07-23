import json
import asyncio
import subprocess
import os
import shutil
from pathlib import Path
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
import httpx
from app.config import settings

router = APIRouter()

GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/openai"

# ──────────────────────────────────────────────
# Tool definitions for Gemini function calling
# ──────────────────────────────────────────────

AGENT_TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "read_file",
            "description": "Read the content of a file at the given absolute path",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Absolute path to the file"},
                },
                "required": ["path"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "write_file",
            "description": "Write content to a file, creating it and parent directories if needed",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Absolute path to the file"},
                    "content": {"type": "string", "description": "File content to write"},
                },
                "required": ["path", "content"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "list_files",
            "description": "List files and directories at the given path",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Absolute path to the directory"},
                },
                "required": ["path"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "run_command",
            "description": "Execute a shell command in the specified working directory. Use for running builds, installs, git commands etc.",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {"type": "string", "description": "Shell command to execute"},
                    "cwd": {"type": "string", "description": "Working directory for the command"},
                },
                "required": ["command", "cwd"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "create_directory",
            "description": "Create a directory (and any needed parent directories)",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Absolute path of directory to create"},
                },
                "required": ["path"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "delete_file",
            "description": "Delete a file or directory",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Absolute path to delete"},
                },
                "required": ["path"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "search_in_files",
            "description": "Search for text patterns across files in a directory",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Text to search for"},
                    "path": {"type": "string", "description": "Directory to search in"},
                },
                "required": ["query", "path"],
            },
        },
    },
]

# ──────────────────────────────────────────────
# Tool executors
# ──────────────────────────────────────────────

def _safe_path(path: str) -> Path:
    p = Path(path)
    allowed = ('/root', '/sdcard', '/storage', '/var', '/tmp', '/home', '/data', '/mnt')
    if p.is_absolute():
        if any(str(p).startswith(prefix) for prefix in allowed):
            return p.resolve()
        resolved = p.resolve()
        if any(str(resolved).startswith(prefix) for prefix in allowed):
            return resolved
    # Relative → resolve from workspace
    return (Path(settings.workspace_root) / path).resolve()


def execute_tool(name: str, args: dict) -> str:
    try:
        if name == "read_file":
            p = _safe_path(args["path"])
            if not p.exists():
                return f"Error: File not found: {p}"
            if p.stat().st_size > 200_000:
                return f"Error: File too large ({p.stat().st_size} bytes). Read smaller chunks."
            return p.read_text(encoding="utf-8", errors="replace")

        elif name == "write_file":
            p = _safe_path(args["path"])
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(args["content"], encoding="utf-8")
            return f"Written {len(args['content'])} chars to {p}"

        elif name == "list_files":
            p = _safe_path(args["path"])
            if not p.exists():
                return f"Error: Path not found: {p}"
            items = []
            for child in sorted(p.iterdir()):
                kind = "DIR" if child.is_dir() else "FILE"
                size = f" ({child.stat().st_size}B)" if child.is_file() else ""
                items.append(f"[{kind}] {child.name}{size}")
            return "\n".join(items) if items else "(empty directory)"

        elif name == "run_command":
            cwd = str(_safe_path(args.get("cwd", settings.workspace_root)))
            cmd = args["command"]
            result = subprocess.run(
                cmd, shell=True, cwd=cwd,
                capture_output=True, text=True, timeout=120,
                env={**os.environ, "TERM": "xterm-256color"}
            )
            output = ""
            if result.stdout:
                output += result.stdout[-3000:]  # cap output
            if result.stderr:
                output += "\n[stderr]\n" + result.stderr[-1500:]
            if result.returncode != 0:
                output += f"\n[exit code: {result.returncode}]"
            return output.strip() or "(no output)"

        elif name == "create_directory":
            p = _safe_path(args["path"])
            p.mkdir(parents=True, exist_ok=True)
            return f"Created directory: {p}"

        elif name == "delete_file":
            p = _safe_path(args["path"])
            if not p.exists():
                return f"Error: Not found: {p}"
            if p.is_dir():
                shutil.rmtree(p)
            else:
                p.unlink()
            return f"Deleted: {p}"

        elif name == "search_in_files":
            search_root = _safe_path(args["path"])
            query = args["query"]
            result = subprocess.run(
                ["grep", "-r", "-n", "-l", query, str(search_root)],
                capture_output=True, text=True, timeout=10
            )
            files = [f for f in result.stdout.strip().split("\n") if f][:10]
            if not files:
                return f"No matches found for '{query}'"
            lines_output = []
            for f in files:
                lr = subprocess.run(["grep", "-n", query, f], capture_output=True, text=True, timeout=5)
                for line in lr.stdout.strip().split("\n")[:5]:
                    lines_output.append(f"{f}: {line}")
            return "\n".join(lines_output)

        else:
            return f"Error: Unknown tool: {name}"

    except subprocess.TimeoutExpired:
        return "Error: Command timed out (120s)"
    except Exception as e:
        return f"Error: {str(e)}"


# ──────────────────────────────────────────────
# System prompt for the agent
# ──────────────────────────────────────────────

AGENT_SYSTEM_PROMPT = """You are Vega Agent — an autonomous AI coding assistant running on a mobile device.

You have access to tools to read/write files, run terminal commands, and explore the filesystem.

FILESYSTEM LAYOUT:
- /root/workspace — default working directory (Linux container projects)
- /storage/emulated/0/ — Android phone internal storage (real phone files: Documents, Download, DCIM, Pictures, Music, etc.)
- /sdcard/ — same as /storage/emulated/0/ (symlink)
- /root/ — Linux container home directory

RULES:
1. Think step by step. Plan before acting.
2. Always check if a directory exists before creating files in it.
3. When creating projects — use CLI generators (flutter create, npx create-react-app, etc.) via run_command.
4. After running commands, read the output carefully to catch errors.
5. If a command fails — analyze the error and fix it, don't give up.
6. Be concise in your explanations — focus on actions.
7. When you are done — say DONE and summarize what was created/changed.
8. Work in the EXACT directory the user specifies.
9. Respond in the same language as the user (Russian if they write Russian).
10. When the user asks about phone files, ALWAYS look in /storage/emulated/0/ or /sdcard/, NOT in /root/workspace.

You are running inside a Linux container on Android. Common tools available: python3, node, npm, flutter, git, curl, pip.
"""


def parse_message_content(content: str):
    import re
    pattern = r'!\[image\]\(data:([^)]+)\)'
    matches = re.findall(pattern, content)

    if not matches:
        return content, []

    clean_text = re.sub(pattern, '[Изображение]', content).strip()

    images = []
    for data_uri in matches:
        images.append({
            "type": "image_url",
            "image_url": {"url": f"data:{data_uri}"}
        })

    return clean_text, images


# ──────────────────────────────────────────────
# WebSocket Agent Endpoint
# ──────────────────────────────────────────────

@router.websocket("/agent/run")
async def agent_run(ws: WebSocket):
    await ws.accept()
    
    try:
        # Receive initial config
        init_data = await ws.receive_text()
        config = json.loads(init_data)
        
        task = config.get("task", "")
        cwd = config.get("cwd", settings.workspace_root)
        gemini_api_key = config.get("gemini_api_key", "") or settings.gemini_api_key
        model = config.get("model", "gemini-2.5-flash")
        max_iterations = config.get("max_iterations", 30)
        
        if not task:
            await ws.send_json({"type": "error", "message": "No task provided"})
            return
        
        if not gemini_api_key:
            await ws.send_json({"type": "error", "message": "No Gemini API key. Set it in settings."})
            return
        
        # Notify start
        await ws.send_json({"type": "start", "task": task, "cwd": cwd})
        
        # Clean images from prompt for Gemini visual model OpenAI-compatible structure
        clean_text, images = parse_message_content(task)
        if images:
            user_content = []
            if clean_text and clean_text != '[Изображение]':
                user_content.append({"type": "text", "text": f"Task: {clean_text}\n\nWorking directory: {cwd}"})
            else:
                user_content.append({"type": "text", "text": f"Task: (See image)\n\nWorking directory: {cwd}"})
            user_content.extend(images)
        else:
            user_content = f"Task: {task}\n\nWorking directory: {cwd}"

        # Build initial messages
        messages = [
            {"role": "system", "content": AGENT_SYSTEM_PROMPT},
            {"role": "user", "content": user_content},
        ]
        
        iteration = 0
        
        async with httpx.AsyncClient(
            base_url=GEMINI_BASE_URL,
            timeout=120.0,
            headers={
                "Authorization": f"Bearer {gemini_api_key}",
                "Content-Type": "application/json",
            }
        ) as client:
            
            while iteration < max_iterations:
                iteration += 1
                
                await ws.send_json({"type": "thinking", "iteration": iteration})
                
                # Call Gemini with function calling
                try:
                    resp = await client.post("/chat/completions", json={
                        "model": model,
                        "messages": messages,
                        "tools": AGENT_TOOLS,
                        "tool_choice": "auto",
                    })
                    
                    if resp.status_code != 200:
                        error_body = resp.text[:500]
                        await ws.send_json({"type": "error", "message": f"Gemini error {resp.status_code}: {error_body}"})
                        break
                    
                    data = resp.json()
                    choice = data["choices"][0]
                    message = choice["message"]
                    
                except Exception as e:
                    await ws.send_json({"type": "error", "message": f"API error: {str(e)}"})
                    break
                
                # Add assistant message to history
                messages.append(message)
                
                # If there's text content, stream it to user
                text_content = message.get("content") or ""
                if text_content:
                    await ws.send_json({"type": "message", "content": text_content})
                    
                    # Check if agent declared it's done
                    if "DONE" in text_content.upper() or choice.get("finish_reason") == "stop":
                        if not message.get("tool_calls"):
                            await ws.send_json({"type": "done", "iterations": iteration})
                            break
                
                # Process tool calls
                tool_calls = message.get("tool_calls", [])
                if not tool_calls:
                    # No more tool calls and no DONE — agent finished naturally
                    await ws.send_json({"type": "done", "iterations": iteration})
                    break
                
                # Execute all tool calls
                tool_results = []
                for tc in tool_calls:
                    tool_id = tc.get("id", "")
                    fn_name = tc["function"]["name"]
                    try:
                        fn_args = json.loads(tc["function"]["arguments"])
                    except Exception:
                        fn_args = {}
                    
                    # Send step notification
                    await ws.send_json({
                        "type": "tool_call",
                        "tool": fn_name,
                        "args": fn_args,
                        "call_id": tool_id,
                    })
                    
                    # Execute tool (in thread pool to not block event loop)
                    result = await asyncio.get_event_loop().run_in_executor(
                        None, execute_tool, fn_name, fn_args
                    )
                    
                    # Send result
                    await ws.send_json({
                        "type": "tool_result",
                        "tool": fn_name,
                        "result": result[:1000],  # truncate for UI
                        "call_id": tool_id,
                    })
                    
                    tool_results.append({
                        "role": "tool",
                        "tool_call_id": tool_id,
                        "content": result,
                    })
                
                # Add tool results to history
                messages.extend(tool_results)
            
            else:
                # Hit max iterations
                await ws.send_json({
                    "type": "done",
                    "iterations": iteration,
                    "warning": f"Reached maximum iterations ({max_iterations})"
                })
    
    except WebSocketDisconnect:
        pass
    except Exception as e:
        try:
            await ws.send_json({"type": "error", "message": str(e)})
        except Exception:
            pass
