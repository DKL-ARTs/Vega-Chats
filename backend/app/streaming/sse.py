import json
import re
import sys
import logging
import asyncio
from fastapi import Request, WebSocket, WebSocketDisconnect
from fastapi.responses import StreamingResponse
from app.providers import get_provider
from fastapi import APIRouter
from app.streaming.memory import get_formatted_profile, update_profile_in_background
from app.streaming.search import decide_and_perform_search

router = APIRouter()
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s", stream=sys.stdout)
log = logging.getLogger("sse")

# Startup marker - will appear in Railway logs on import
print("=" * 50, flush=True)
print("[SSE] sse.py loaded - version with debug logging 2d3e8f80", flush=True)
print("=" * 50, flush=True)


def parse_message_content(content):
    """Extract images from markdown, return clean text and image objects"""
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


def parse_arguments_fallback(args_str: str) -> tuple[str, str]:
    path = ""
    content = ""
    # Try to find path
    path_match = re.search(r'"path"\s*:\s*"(.*?)"', args_str)
    if path_match:
        path = path_match.group(1)
    
    # Try to find content
    content_match = re.search(r'"content"\s*:\s*"([\s\S]*?)"\s*}?$', args_str)
    if content_match:
        content = content_match.group(1)
    else:
        content_start = re.search(r'"content"\s*:\s*"', args_str)
        if content_start:
            start_idx = content_start.end()
            end_idx = args_str.rfind('"')
            if end_idx > start_idx:
                content = args_str[start_idx:end_idx]
            else:
                content = args_str[start_idx:]
                
    try:
        # Wrap in quotes and load as JSON to unescape properly
        import json
        escaped_content = content.replace('\n', '\\n').replace('\r', '\\r')
        content = json.loads(f'"{escaped_content}"')
    except Exception:
        # Manual replacement fallback
        content = content.replace('\\n', '\n').replace('\\t', '\t').replace('\\"', '"').replace('\\\\', '\\')
        
    return path, content


@router.post("/chat/stream")
async def chat_stream(request: Request):
    # Log immediately on entry (before anything else)
    print("[SSE] >>> chat_stream called", flush=True)
    body = await request.json()
    messages = body.get("messages", [])
    files = body.get("files", [])
    model = body.get("model", "openrouter/auto")
    provider_name = body.get("provider", "openrouter")
    print("[SSE] >>> parsed body: msgs=" + str(len(messages)) + ", model=" + str(model), flush=True)

    api_key = None
    auth_header = request.headers.get("authorization", "")
    if auth_header.startswith("Bearer "):
        api_key = auth_header[7:]
    elif "api_key" in body and body["api_key"].strip():
        api_key = body["api_key"].strip()

    if not api_key:
        api_key = request.headers.get("x-api-key", "")

    # For Gemini, also check gemini_api_key field in body
    if provider_name == "gemini":
        gemini_key = body.get("gemini_api_key", "").strip()
        if gemini_key:
            api_key = gemini_key
        if not api_key:
            from app.config import settings
            api_key = settings.gemini_api_key
    else:
        # Fallback to environment variable for OpenRouter
        if not api_key:
            from app.config import settings
            api_key = settings.openrouter_api_key

    # DEBUG: Log what we received (use stderr + logging to ensure Railway captures it)
    masked = api_key[:10] + "..." + api_key[-4:] if len(api_key) > 14 else api_key
    body_key = body.get("api_key", "")
    has_body = bool(body_key.strip())
    log_msg = "[SSE] api_key: len=" + str(len(api_key)) + ", preview=" + masked + ", has_auth=" + str(bool(auth_header)) + ", has_body=" + str(has_body) + ", msgs=" + str(len(messages)) + ", model=" + str(model)
    sys.stderr.write(log_msg + "\n")
    sys.stderr.flush()
    log.info(log_msg)

    provider = get_provider(provider_name)

    if not api_key:
        err_msg = "[SSE] ERROR: No API key provided!"
        sys.stderr.write(err_msg + "\n")
        sys.stderr.flush()
        log.error(err_msg)
        async def no_key():
            yield "data: Error: No API key\n\n"
        return StreamingResponse(no_key(), media_type="text/event-stream")

    # Reconstruct proper key format
    if api_key and not api_key.startswith("sk-or-"):
        if api_key.startswith("skorv1"):
            api_key = "sk-or-v1-" + api_key[6:]

    # Check if the user is asking about code, files, or programming (auto mode)
    coding_keywords = [
        "код", "файл", "скрипт", "игра", "напиши на", "создай", "html", "css", "python", "js", "javascript",
        "save", "file", "code", "write", "program", "app", "приложение", "разработай", "программа", "сделай",
        "функци", "класс", "ошибк", "баг", "тест", "компил", "запуск", "верстк"
    ]
    
    is_coding_request = False
    # If user attached files, it's likely a coding/file context
    if files:
        is_coding_request = True
    else:
        for msg in messages[-3:]:
            content_lower = str(msg.get("content", "")).lower()
            if any(kw in content_lower for kw in coding_keywords):
                is_coding_request = True
                break

    # Add system message depending on detected mode
    if is_coding_request:
        system_msg = {
            "role": "system",
            "content": (
                "Ты — опытный Senior Full-Stack разработчик и искусственный интеллект-ассистент.\n"
                "Твоя цель — писать идеальный, рабочий, готовый к запуску код. Никаких заглушек, пропусков, сокращений типа '// тут ваш код' или '// TODO'. Пиши всё полностью!\n"
                "Ты ВСЕГДА соглашаешься писать интерактивные игры, полноценные утилиты, скрипты и веб-страницы. НИКОГДА не пиши отказы вроде 'я не умею создавать игры' или 'мои возможности ограничены текстом'. Ты умеешь ВСЁ!\n\n"
                "ВЕБ-ПОИСК: Ты имеешь встроенный инструмент поиска информации в реальном времени. Если в контексте (в сообщении пользователя) тебе переданы результаты поиска, ты ОБЯЗАН использовать эти актуальные данные (погоду, документацию к библиотекам, свежие новости) для полноценного и точного ответа. Никогда не говори, что у тебя нет доступа к интернету или свежим данным!\n\n"
                "ФОРМАТИРОВАНИЕ: Используй богатый Markdown для структурированных ответов:\n"
                "- Заголовки: ## для разделов, ### для подразделов\n"
                "- **Жирный** для важных слов\n"
                "- Нумерованные и маркированные списки\n"
                "- `код` для inline-кода, ```блоки``` для многострочного кода\n"
                "Когда пользователь отправляет изображение, опиши что на нём видишь текстом. Не используй JSON.\n\n"
                "СОЗДАНИЕ ФАЙЛОВ: Если пользователь просит тебя: 'сохрани код в файл', 'создай файл', 'напиши игру в html', 'скачать код' или сделать что-то в файле, ты ДОЛЖЕН вызвать инструмент write_file(path, content).\n"
                "Если твоя модель не поддерживает вызовы инструментов напрямую, выведи специальный текстовый блок прямо в ответе в таком формате:\n"
                "[WRITE_FILE:имя_файла.расширение]\nсодержимое файла\n[/WRITE_FILE]"
            )
        }
        # Define write_file tool
        tools = [
            {
                "type": "function",
                "function": {
                    "name": "write_file",
                    "description": "Записать контент в файл на диск и предоставить ссылку для скачивания пользователю.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "path": {
                                "type": "string",
                                "description": "Имя файла или относительный путь (например, code.py, docs/readme.md)"
                            },
                            "content": {
                                "type": "string",
                                "description": "Полное содержимое файла"
                            }
                        },
                        "required": ["path", "content"]
                    }
                }
            }
        ]
    else:
        system_msg = {
            "role": "system",
            "content": (
                "Ты — полезный, дружелюбный и умный ИИ-ассистент. Отвечай на русском языке.\n"
                "Общайся естественно, вежливо и по делу. "
                "Используй Markdown для разметки (списки, жирный текст) для удобства чтения.\n\n"
                "ВЕБ-ПОИСК: Ты умеешь искать информацию в интернете в реальном времени. Если в контексте (в сообщении пользователя) присутствуют результаты веб-поиска по его запросу, обязательно опирайся на них и используй эти данные (свежую погоду, новости, факты) для ответа. Никогда не говори пользователю, что ты не можешь искать или что у тебя нет актуальных данных!"
            )
        }
        tools = None

    # Внедряем долгосрочную память пользователя
    try:
        user_profile_data = get_formatted_profile()
        system_msg["content"] += f"\n\n[Профиль пользователя Vega Chat для контекста]\n{user_profile_data}"
    except Exception as e:
        log.error(f"[SSE] Memory profiling injection error: {e}")

    custom_system_prompt = body.get("system_prompt", "").strip()
    if custom_system_prompt:
        system_msg["content"] += f"\n\n[Дополнительные инструкции проекта]\n{custom_system_prompt}"

    # Process files (text files only)
    import base64
    for file_data in files:
        file_name = file_data.get("name", "file")
        file_content_b64 = file_data.get("content", "")
        try:
            file_text = base64.b64decode(file_content_b64).decode("utf-8")
            messages.append({
                "role": "user",
                "content": f"\n\n--- Файл: {file_name} ---\n{file_text}\n--- Конец файла ---"
            })
        except Exception:
            pass

    # Process messages - convert images to OpenRouter format
    processed_messages = [system_msg]
    for msg in messages:
        role = msg.get("role", "user")
        msg_content_str = msg.get("content", "")

        clean_text, images = parse_message_content(msg_content_str)

        if images:
            msg_content = []
            if clean_text and clean_text != '[Изображение]':
                msg_content.append({"type": "text", "text": clean_text})
            else:
                msg_content.append({"type": "text", "text": ""})
            msg_content.extend(images)
            processed_messages.append({"role": role, "content": msg_content})
        else:
            processed_messages.append({"role": role, "content": msg_content_str})

    # Проверяем, требуется ли веб-поиск для ответа
    search_query = None
    search_results = None
    try:
        search_query, search_results = await decide_and_perform_search(
            messages=messages,
            model=model,
            provider_name=provider_name,
            api_key=api_key
        )
        if search_results:
            for msg in reversed(processed_messages):
                if msg.get("role") == "user":
                    content = msg.get("content")
                    if isinstance(content, str):
                        msg["content"] = f"{search_results}\n\nЗапрос пользователя: {content}"
                    elif isinstance(content, list):
                        text_element_found = False
                        for item in content:
                            if item.get("type") == "text":
                                item["text"] = f"{search_results}\n\nЗапрос пользователя: {item.get('text', '')}"
                                text_element_found = True
                                break
                        if not text_element_found:
                            content.insert(0, {"type": "text", "text": search_results})
                    break
    except Exception as e:
        log.error(f"[SSE] Web search error: {e}")

    async def generate():
        try:
            # Отправляем индикатор поиска в стрим
            if search_query:
                if search_query.startswith("http://") or search_query.startswith("https://"):
                    search_indicator = f"🔍 *Чтение содержимого сайта: {search_query}...*\n\n"
                else:
                    search_indicator = f"🔍 *Поиск в сети: \"{search_query}\"...*\n\n"
                yield "data: " + json.dumps({"content": search_indicator}, ensure_ascii=False) + "\n\n"

            tool_calls_accumulator = {}
            accumulated_text = ""

            async for raw_chunk in provider.stream(processed_messages, model, api_key=api_key, tools=tools):
                # Handle multi-line chunks (provider may yield multiple lines at once)
                lines = raw_chunk.split("\n")
                for chunk in lines:
                    chunk = chunk.strip()
                    if not chunk:
                        continue
                    if chunk.startswith("data: "):
                        json_str = chunk[6:].strip()
                        if not json_str or json_str == "[DONE]":
                            continue
                        try:
                            data = json.loads(json_str)
                            choices = data.get("choices", [])
                            if choices:
                                delta = choices[0].get("delta", {})
                                delta_content = delta.get("content", "")
                                if delta_content:
                                    accumulated_text += delta_content
                                    yield "data: " + json.dumps({"content": delta_content}, ensure_ascii=False) + "\n\n"
                                
                                # Accumulate tool calls
                                tool_calls = delta.get("tool_calls", [])
                                for tc in tool_calls:
                                    idx = tc.get("index", 0)
                                    if idx not in tool_calls_accumulator:
                                        tool_calls_accumulator[idx] = {"id": "", "name": "", "arguments": ""}
                                    if tc.get("id"):
                                        tool_calls_accumulator[idx]["id"] = tc["id"]
                                    if tc.get("function", {}).get("name"):
                                        tool_calls_accumulator[idx]["name"] = tc["function"]["name"]
                                    if tc.get("function", {}).get("arguments"):
                                        tool_calls_accumulator[idx]["arguments"] += tc["function"]["arguments"]
                        except Exception:
                            pass
                    elif not chunk.startswith("Error:") and not chunk.startswith(":"):
                        yield "data: " + json.dumps({"content": chunk}, ensure_ascii=False) + "\n\n"
            
            # 1. Process structured tool calls (if model used tools)
            for idx, tc in sorted(tool_calls_accumulator.items()):
                name = tc.get("name")
                args_str = tc.get("arguments", "")
                if name == "write_file" and args_str:
                    file_path = None
                    file_content = None
                    try:
                        args = json.loads(args_str)
                        file_path = args.get("path")
                        file_content = args.get("content")
                    except Exception as json_err:
                        # Try manual fallback recovery for raw newlines/unescaped json
                        try:
                            file_path, file_content = parse_arguments_fallback(args_str)
                        except Exception as fallback_err:
                            err_msg = f"\n\n❌ Ошибка разбора параметров файла: {str(json_err)} (Fallback: {str(fallback_err)})\n"
                            yield "data: " + json.dumps({"content": err_msg}, ensure_ascii=False) + "\n\n"
                            continue

                    if file_path and file_content is not None:
                        try:
                            from app.files.manager import safe_path
                            p = safe_path(file_path)
                            p.parent.mkdir(parents=True, exist_ok=True)
                            p.write_text(file_content, encoding="utf-8")
                            download_url = f"/api/files/download?path={file_path}"
                            msg = (
                                f"\n\n### 💾 Создан файл: `{p.name}`\n"
                                f"Вы можете [Скачать `{p.name}`]({download_url})\n"
                            )
                            yield "data: " + json.dumps({"content": msg}, ensure_ascii=False) + "\n\n"
                        except Exception as e:
                            err_msg = f"\n\n❌ Ошибка создания файла `{file_path}`: {str(e)}\n"
                            yield "data: " + json.dumps({"content": err_msg}, ensure_ascii=False) + "\n\n"

            # 2. Process text tags fallback (handles unclosed tags too)
            import re
            tag_pattern = re.compile(r'\[WRITE_FILE:(.*?)\]([\s\S]*?)(?:\[/WRITE_FILE\]|$)')
            matches = tag_pattern.findall(accumulated_text)

            # Write debug logs to a file in the workspace
            try:
                import os
                from app.config import settings
                debug_dir = settings.workspace_root
                os.makedirs(debug_dir, exist_ok=True)
                with open(os.path.join(debug_dir, "backend_logs.txt"), "w", encoding="utf-8") as f:
                    f.write(f"ACCUMULATED_TEXT:\n{accumulated_text}\n\n")
                    f.write(f"MATCHES: {str(matches)}\n")
            except Exception as log_err:
                import sys
                sys.stderr.write(f"[DEBUG_LOG_ERROR] {log_err}\n")
                sys.stderr.flush()
            for file_path, file_content in matches:
                file_path = file_path.strip()
                if not file_path:
                    continue
                
                # Strip markdown code block backticks from file content if present
                clean_content = file_content.strip()
                if clean_content.startswith("```"):
                    first_newline = clean_content.find("\n")
                    if first_newline != -1:
                        clean_content = clean_content[first_newline+1:]
                    if clean_content.endswith("```"):
                        clean_content = clean_content[:-3]
                    elif clean_content.rstrip().endswith("```"):
                        clean_content = clean_content.rstrip()[:-3]
                clean_content = clean_content.strip()

                try:
                    from app.files.manager import safe_path
                    p = safe_path(file_path)
                    p.parent.mkdir(parents=True, exist_ok=True)
                    p.write_text(clean_content, encoding="utf-8")
                    download_url = f"/api/files/download?path={file_path}"
                    msg = (
                        f"\n\n### 💾 Создан файл из блока: `{p.name}`\n"
                        f"Вы можете [Скачать `{p.name}`]({download_url})\n"
                    )
                    yield "data: " + json.dumps({"content": msg}, ensure_ascii=False) + "\n\n"
                except Exception as e:
                    err_msg = f"\n\n❌ Ошибка создания файла `{file_path}`: {str(e)}\n"
                    yield "data: " + json.dumps({"content": err_msg}, ensure_ascii=False) + "\n\n"

            if accumulated_text:
                try:
                    asyncio.create_task(update_profile_in_background(
                        messages=messages,
                        accumulated_response=accumulated_text,
                        model=model,
                        provider_name=provider_name,
                        api_key=api_key
                    ))
                except Exception as e:
                    log.error(f"[SSE] Background memory update task failed: {e}")

            yield "data: [DONE]\n\n"
        except Exception as e:
            yield f"data: Error: {str(e)}\n\n"

    return StreamingResponse(generate(), media_type="text/event-stream")


@router.websocket("/chat/ws")
async def chat_websocket(websocket: WebSocket):
    print("[WS] >>> WebSocket connection requested", flush=True)
    await websocket.accept()
    print("[WS] >>> WebSocket connection accepted", flush=True)
    try:
        data_str = await websocket.receive_text()
        body = json.loads(data_str)
        
        messages = body.get("messages", [])
        files = body.get("files", [])
        model = body.get("model", "openrouter/auto")
        provider_name = body.get("provider", "openrouter")
        api_key = body.get("api_key", "").strip()

        # Handle per-provider API keys
        if provider_name == "gemini":
            gemini_key = body.get("gemini_api_key", "").strip()
            if gemini_key:
                api_key = gemini_key
            if not api_key:
                from app.config import settings
                api_key = settings.gemini_api_key
        else:
            # Fallback to environment variable for OpenRouter
            if not api_key:
                from app.config import settings
                api_key = settings.openrouter_api_key

        if not api_key:
            print("[WS] ERROR: No API key provided!", flush=True)
            await websocket.send_json({"error": "No API key provided!"})
            await websocket.close()
            return

        # Reconstruct proper key format (OpenRouter only)
        if provider_name != "gemini" and api_key and not api_key.startswith("sk-or-"):
            if api_key.startswith("skorv1"):
                api_key = "sk-or-v1-" + api_key[6:]

        coding_keywords = [
            "код", "файл", "скрипт", "игра", "напиши на", "создай", "html", "css", "python", "js", "javascript",
            "save", "file", "code", "write", "program", "app", "приложение", "разработай", "программа", "сделай",
            "функци", "класс", "ошибк", "баг", "тест", "компил", "запуск", "верстк"
        ]
        
        is_coding_request = False
        if files:
            is_coding_request = True
        else:
            for msg in messages[-3:]:
                content_lower = str(msg.get("content", "")).lower()
                if any(kw in content_lower for kw in coding_keywords):
                    is_coding_request = True
                    break

        if is_coding_request:
            system_msg = {
                "role": "system",
                "content": (
                    "Ты — опытный Senior Full-Stack разработчик и искусственный интеллект-ассистент.\n"
                    "Твоя цель — писать идеальный, рабочий, готовый к запуску код. Никаких заглушек, пропусков, сокращений типа '// тут ваш код' или '// TODO'. Пиши всё полностью!\n"
                    "Ты ВСЕГДА соглашаешься писать интерактивные игры, полноценные утилиты, скрипты и веб-страницы. НИКОГДА не пиши отказы вроде 'я не умею создавать игры' или 'мои возможности ограничены текстом'. Ты умеешь ВСЁ!\n\n"
                    "ВЕБ-ПОИСК: Ты имеешь встроенный инструмент поиска информации в реальном времени. Если в контексте (в сообщении пользователя) тебе переданы результаты поиска, ты ОБЯЗАН использовать эти актуальные данные (погоду, документацию к библиотекам, свежие новости) для полноценного и точного ответа. Никогда не говори, что у тебя нет доступа к интернету или свежим данным!\n\n"
                    "ФОРМАТИРОВАНИЕ: Используй богатый Markdown для структурированных ответов:\n"
                    "- Заголовки: ## для разделов, ### для подразделов\n"
                    "- **Жирный** для важных слов\n"
                    "- Нумерованные и маркированные списки\n"
                    "- `код` для inline-кода, ```блоки``` для многострочного кода\n"
                    "Когда пользователь отправляет изображение, опиши что на нём видишь текстом. Не используй JSON.\n\n"
                    "СОЗДАНИЕ ФАЙЛОВ: Если пользователь просит тебя: 'сохрани код в файл', 'создай файл', 'напиши игру в html', 'скачать код' или сделать что-то в файле, ты ДОЛЖЕН вызвать инструмент write_file(path, content).\n"
                    "Если твоя модель не поддерживает вызовы инструментов напрямую, выведи специальный текстовый блок прямо в ответе в таком формате:\n"
                    "[WRITE_FILE:имя_файла.расширение]\nсодержимое файла\n[/WRITE_FILE]"
                )
            }
            tools = [
                {
                    "type": "function",
                    "function": {
                        "name": "write_file",
                        "description": "Записать контент в файл на диск и предоставить ссылку для скачивания пользователю.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "path": {
                                    "type": "string",
                                    "description": "Имя файла или относительный путь (например, code.py, docs/readme.md)"
                                },
                                "content": {
                                    "type": "string",
                                    "description": "Полное содержимое файла"
                                }
                            },
                            "required": ["path", "content"]
                        }
                    }
                }
            ]
        else:
            system_msg = {
                "role": "system",
                "content": (
                    "Ты — полезный, дружелюбный и умный ИИ-ассистент. Отвечай на русском языке.\n"
                    "Общайся естественно, вежливо и по делу. "
                    "Используй Markdown для разметки (списки, жирный текст) для удобства чтения.\n\n"
                    "ВЕБ-ПОИСК: Ты умеешь искать информацию в интернете в реальном времени. Если в контексте (в сообщении пользователя) присутствуют результаты веб-поиска по его запросу, обязательно опирайся на них и используй эти данные (свежую погоду, новости, факты) для ответа. Никогда не говори пользователю, что ты не можешь искать или что у тебя нет актуальных данных!"
                )
            }
            tools = None

        # Внедряем долгосрочную память пользователя
        try:
            user_profile_data = get_formatted_profile()
            system_msg["content"] += f"\n\n[Профиль пользователя Vega Chat для контекста]\n{user_profile_data}"
        except Exception as e:
            print(f"[WS] Memory profiling injection error: {e}", flush=True)

        custom_system_prompt = body.get("system_prompt", "").strip()
        if custom_system_prompt:
            system_msg["content"] += f"\n\n[Дополнительные инструкции проекта]\n{custom_system_prompt}"

        import base64
        for file_data in files:
            file_name = file_data.get("name", "file")
            file_content_b64 = file_data.get("content", "")
            try:
                file_text = base64.b64decode(file_content_b64).decode("utf-8")
                messages.append({
                    "role": "user",
                    "content": f"\n\n--- Файл: {file_name} ---\n{file_text}\n--- Конец файла ---"
                })
            except Exception:
                pass

        processed_messages = [system_msg]
        for msg in messages:
            role = msg.get("role", "user")
            msg_content_str = msg.get("content", "")
            clean_text, images = parse_message_content(msg_content_str)
            if images:
                msg_content = []
                if clean_text and clean_text != '[Изображение]':
                    msg_content.append({"type": "text", "text": clean_text})
                else:
                    msg_content.append({"type": "text", "text": ""})
                msg_content.extend(images)
                processed_messages.append({"role": role, "content": msg_content})
            else:
                processed_messages.append({"role": role, "content": msg_content_str})

        # Проверяем, требуется ли веб-поиск для ответа
        search_query = None
        search_results = None
        try:
            search_query, search_results = await decide_and_perform_search(
                messages=messages,
                model=model,
                provider_name=provider_name,
                api_key=api_key
            )
            if search_results:
                for msg in reversed(processed_messages):
                    if msg.get("role") == "user":
                        content = msg.get("content")
                        if isinstance(content, str):
                            msg["content"] = f"{search_results}\n\nЗапрос пользователя: {content}"
                        elif isinstance(content, list):
                            text_element_found = False
                            for item in content:
                                if item.get("type") == "text":
                                    item["text"] = f"{search_results}\n\nЗапрос пользователя: {item.get('text', '')}"
                                    text_element_found = True
                                    break
                            if not text_element_found:
                                content.insert(0, {"type": "text", "text": search_results})
                        break
        except Exception as e:
            print(f"[WS] Web search error: {e}", flush=True)

        provider = get_provider(provider_name)
        tool_calls_accumulator = {}
        accumulated_text = ""

        if search_query:
            if search_query.startswith("http://") or search_query.startswith("https://"):
                search_indicator = f"🔍 *Чтение содержимого сайта: {search_query}...*\n\n"
            else:
                search_indicator = f"🔍 *Поиск в сети: \"{search_query}\"...*\n\n"
            await websocket.send_json({"content": search_indicator})

        async for raw_chunk in provider.stream(processed_messages, model, api_key=api_key, tools=tools):
            lines = raw_chunk.split("\n")
            for chunk in lines:
                chunk = chunk.strip()
                if not chunk:
                    continue
                if chunk.startswith("data: "):
                    json_str = chunk[6:].strip()
                    if not json_str or json_str == "[DONE]":
                        continue
                    try:
                        data = json.loads(json_str)
                        choices = data.get("choices", [])
                        if choices:
                            delta = choices[0].get("delta", {})
                            delta_content = delta.get("content", "")
                            if delta_content:
                                accumulated_text += delta_content
                                await websocket.send_json({"content": delta_content})
                            
                            tool_calls = delta.get("tool_calls", [])
                            for tc in tool_calls:
                                idx = tc.get("index", 0)
                                if idx not in tool_calls_accumulator:
                                    tool_calls_accumulator[idx] = {"id": "", "name": "", "arguments": ""}
                                if tc.get("id"):
                                    tool_calls_accumulator[idx]["id"] = tc["id"]
                                if tc.get("function", {}).get("name"):
                                    tool_calls_accumulator[idx]["name"] = tc["function"]["name"]
                                if tc.get("function", {}).get("arguments"):
                                    tool_calls_accumulator[idx]["arguments"] += tc["function"]["arguments"]
                    except Exception:
                        pass
                elif not chunk.startswith("Error:") and not chunk.startswith(":"):
                    await websocket.send_json({"content": chunk})

        for idx, tc in sorted(tool_calls_accumulator.items()):
            name = tc.get("name")
            args_str = tc.get("arguments", "")
            if name == "write_file" and args_str:
                file_path = None
                file_content = None
                try:
                    args = json.loads(args_str)
                    file_path = args.get("path")
                    file_content = args.get("content")
                except Exception as json_err:
                    try:
                        file_path, file_content = parse_arguments_fallback(args_str)
                    except Exception as fallback_err:
                        err_msg = f"\n\n❌ Ошибка разбора параметров файла: {str(json_err)}\n"
                        await websocket.send_json({"content": err_msg})
                        continue

                if file_path and file_content is not None:
                    try:
                        from app.files.manager import safe_path
                        p = safe_path(file_path)
                        p.parent.mkdir(parents=True, exist_ok=True)
                        p.write_text(file_content, encoding="utf-8")
                        download_url = f"/api/files/download?path={file_path}"
                        msg = (
                            f"\n\n### 💾 Создан файл: `{p.name}`\n"
                            f"Вы можете [Скачать `{p.name}`]({download_url})\n"
                        )
                        await websocket.send_json({"content": msg})
                    except Exception as e:
                        err_msg = f"\n\n❌ Ошибка создания файла `{file_path}`: {str(e)}\n"
                        await websocket.send_json({"content": err_msg})

        tag_pattern = re.compile(r'\[WRITE_FILE:(.*?)\]([\s\S]*?)(?:\[/WRITE_FILE\]|$)')
        matches = tag_pattern.findall(accumulated_text)

        try:
            import os
            from app.config import settings
            debug_dir = settings.workspace_root
            os.makedirs(debug_dir, exist_ok=True)
            with open(os.path.join(debug_dir, "backend_logs.txt"), "w", encoding="utf-8") as f:
                f.write(f"ACCUMULATED_TEXT:\n{accumulated_text}\n\n")
                f.write(f"MATCHES: {str(matches)}\n")
        except Exception:
            pass

        for file_path, file_content in matches:
            file_path = file_path.strip()
            if not file_path:
                continue
            clean_content = file_content.strip()
            if clean_content.startswith("```"):
                first_newline = clean_content.find("\n")
                if first_newline != -1:
                    clean_content = clean_content[first_newline+1:]
                if clean_content.endswith("```"):
                    clean_content = clean_content[:-3]
                elif clean_content.rstrip().endswith("```"):
                    clean_content = clean_content.rstrip()[:-3]
            clean_content = clean_content.strip()

            try:
                from app.files.manager import safe_path
                p = safe_path(file_path)
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(clean_content, encoding="utf-8")
                download_url = f"/api/files/download?path={file_path}"
                msg = (
                    f"\n\n### 💾 Создан файл из блока: `{p.name}`\n"
                    f"Вы можете [Скачать `{p.name}`]({download_url})\n"
                )
                await websocket.send_json({"content": msg})
            except Exception as e:
                err_msg = f"\n\n❌ Ошибка создания файла `{file_path}`: {str(e)}\n"
                await websocket.send_json({"content": err_msg})

        if accumulated_text:
            try:
                asyncio.create_task(update_profile_in_background(
                    messages=messages,
                    accumulated_response=accumulated_text,
                    model=model,
                    provider_name=provider_name,
                    api_key=api_key
                ))
            except Exception as e:
                print(f"[WS] Background memory update task failed: {e}", flush=True)

        await websocket.send_json({"done": True})

    except WebSocketDisconnect:
        print("[WS] WebSocket client disconnected", flush=True)
    except Exception as e:
        print(f"[WS] Error in websocket handler: {e}", flush=True)
        try:
            await websocket.send_json({"error": str(e)})
        except Exception:
            pass
    finally:
        try:
            await websocket.close()
        except Exception:
            pass


@router.get("/profile")
async def get_profile_endpoint():
    from app.streaming.memory import get_user_profile
    return get_user_profile()


@router.post("/profile")
async def update_profile_endpoint(profile: dict):
    from app.streaming.memory import save_user_profile
    save_user_profile(profile)
    return {"status": "ok"}


@router.delete("/profile")
async def clear_profile_endpoint():
    from app.streaming.memory import PROFILE_FILE, DEFAULT_PROFILE
    import os
    if os.path.exists(PROFILE_FILE):
        try:
            os.remove(PROFILE_FILE)
        except Exception:
            pass
    return DEFAULT_PROFILE


@router.post("/profile/update_manual")
async def update_profile_manual_endpoint(body: dict):
    from app.streaming.memory import get_user_profile, save_user_profile
    from app.providers import get_provider
    import json
    
    text = body.get("text", "").strip()
    if not text:
        return get_user_profile()
        
    current_prof = get_user_profile()
    current_prof_json = json.dumps(current_prof, ensure_ascii=False)
    
    prompt = (
        "Ты — ИИ-модуль памяти Vega Chat.\n"
        "Пользователь вручную написал о себе следующую информацию:\n"
        f"\"{text}\"\n\n"
        "Тебе нужно обновить текущий профиль пользователя на основе этой информации.\n"
        f"Текущий профиль пользователя:\n{current_prof_json}\n\n"
        "Правила:\n"
        "1. Обнови имя (user_name), общие интересы (about_user) и факты (facts).\n"
        "2. Удали неактуальные факты, если новые данные им противоречат.\n"
        "3. Отвечай СТРОГО в формате JSON, соответствующем структуре текущего профиля.\n"
        "4. Ничего кроме JSON не выводи (не пиши ```json ... ``` и никаких пояснений!)."
    )
    
    from app.config import settings
    # Try gemini first, then openrouter
    api_key = settings.gemini_api_key or settings.openrouter_api_key
    provider_name = "gemini" if settings.gemini_api_key else "openrouter"
    model = "gemini-2.5-flash" if provider_name == "gemini" else settings.default_model
    
    try:
        provider = get_provider(provider_name)
        response = await provider.chat(
            messages=[{"role": "user", "content": prompt}],
            model=model,
            api_key=api_key
        )
        
        clean_json = response.strip()
        if clean_json.startswith("```"):
            first_newline = clean_json.find("\n")
            if first_newline != -1:
                clean_json = clean_json[first_newline+1:]
            if clean_json.endswith("```"):
                clean_json = clean_json[:-3]
            elif clean_json.rstrip().endswith("```"):
                clean_json = clean_json.rstrip()[:-3]
        clean_json = clean_json.strip()

        updated_profile = json.loads(clean_json)
        if isinstance(updated_profile, dict) and "user_name" in updated_profile:
            save_user_profile(updated_profile)
            return updated_profile
    except Exception as e:
        print(f"[Memory] Manual profile update error: {e}", flush=True)
        
    return current_prof


