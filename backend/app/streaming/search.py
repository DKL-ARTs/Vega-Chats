import httpx
import re
import json
import logging
from app.providers import get_provider

log = logging.getLogger("search")

async def search_duckduckgo(query: str, max_results: int = 5) -> list[dict]:
    """Scrapes DuckDuckGo Lite HTML search results without external dependencies"""
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    }
    url = "https://lite.duckduckgo.com/lite/"
    try:
        async with httpx.AsyncClient(headers=headers, timeout=10.0) as client:
            resp = await client.post(url, data={"q": query})
            if resp.status_code != 200:
                log.error(f"[Search] DuckDuckGo response code: {resp.status_code}")
                return []
            
            html = resp.text
            
            # Extract links and snippets using regex
            # Links: <a class="result-link" href="...">Title</a>
            links = re.findall(r'class="result-link"\s+href="([^"]+)"[^>]*>(.*?)</a>', html)
            # Snippets: <td class="result-snippet">Snippet text</td>
            snippets = re.findall(r'class="result-snippet"[^>]*>([\s\S]*?)</td>', html)
            
            results = []
            for i in range(min(len(links), len(snippets), max_results)):
                url_match = links[i][0]
                title = re.sub(r'<[^>]+>', '', links[i][1]).strip()
                snippet = re.sub(r'<[^>]+>', '', snippets[i]).strip()
                snippet = re.sub(r'\s+', ' ', snippet)
                
                results.append({
                    "title": title,
                    "snippet": snippet,
                    "url": url_match
                })
            return results
    except Exception as e:
        log.error(f"[Search] DuckDuckGo search error: {e}")
        return []

def clean_html(html: str) -> str:
    """Strips tags, scripts, and styles from HTML string to return readable text"""
    # Strip script and style tags
    html = re.sub(r'<(script|style)\b[^>]*>[\s\S]*?</\1>', '', html, flags=re.IGNORECASE)
    # Strip comments
    html = re.sub(r'<!--[\s\S]*?-->', '', html)
    # Preserve block spacing by injecting newlines
    html = re.sub(r'</?(div|p|h\d|li|tr|section|header|footer|aside)\b[^>]*>', '\n', html, flags=re.IGNORECASE)
    html = re.sub(r'<br\s*/?>', '\n', html, flags=re.IGNORECASE)
    # Strip remaining tags
    text = re.sub(r'<[^>]+>', '', html)
    # Unescape HTML entities
    import html as html_parser
    text = html_parser.unescape(text)
    # Collapse extra whitespace
    text = re.sub(r'[ \t]+', ' ', text)
    text = re.sub(r'\n\s*\n+', '\n\n', text)
    return text.strip()

async def fetch_url_content(url: str) -> str:
    """Downloads content from HTTP/HTTPS URL and returns parsed readable text representation"""
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    }
    try:
        async with httpx.AsyncClient(headers=headers, timeout=12.0, follow_redirects=True) as client:
            resp = await client.get(url)
            if resp.status_code != 200:
                return f"Ошибка при загрузке сайта (HTTP статус {resp.status_code})"
            
            cleaned = clean_html(resp.text)
            if len(cleaned) > 15000:
                cleaned = cleaned[:15000] + "\n\n...[содержимое веб-страницы обрезано из-за большого объема]..."
            return cleaned
    except Exception as e:
        return f"Не удалось прочитать содержимое сайта: {e}"

async def decide_and_perform_search(
    messages: list[dict], 
    model: str, 
    provider_name: str, 
    api_key: str
) -> tuple[str, str]:
    """
    Checks if a query contains a URL (fetches it directly) or if it requires general DuckDuckGo search.
    Returns (query/url, formatted_results).
    """
    if not messages:
        return None, None

    last_user_msg = ""
    for msg in reversed(messages):
        if msg.get("role") == "user":
            last_user_msg = msg.get("content", "")
            if isinstance(last_user_msg, list):
                last_user_msg = " ".join([item.get("text", "") for item in last_user_msg if item.get("type") == "text"])
            break

    if not last_user_msg:
        return None, None

    # Check for direct URL pasting
    urls = re.findall(r'(https?://[^\s\)\}\]>\'"]+)', last_user_msg)
    if urls:
        target_url = urls[0]
        log.info(f"[Search] Direct URL detected, fetching content of: {target_url}")
        content = await fetch_url_content(target_url)
        
        # If download failed completely, we fallback to DDG search for it.
        # Otherwise, we return the parsed content of the web page.
        if "Не удалось прочитать содержимое" in content or "Ошибка при загрузке сайта" in content:
            log.warning(f"[Search] Direct fetch failed for {target_url}, falling back to DDG search")
        else:
            formatted_results = (
                f"\n\n--- СОДЕРЖИМОЕ ВЕБ-САЙТА {target_url} ---\n"
                f"{content}\n"
                f"--- КОНЕЦ СОДЕРЖИМОГО ВЕБ-САЙТА ---\n"
                f"Внимание: Выше предоставлено реальное содержимое веб-сайта, который запросил пользователь. "
                f"Используй его для анализа, оценки, поиска ошибок и ответа на запрос пользователя о данном сайте."
            )
            return target_url, formatted_results

    # LLM Classifier Prompt
    classifier_prompt = (
        "Ты — автоматический классификатор веб-поиска.\n"
        "Проанализируй последнее сообщение пользователя и определи, нужна ли свежая информация из интернета для ответа на него (новости, погода, факты после 2024 года, текущие события, программирование по новым библиотекам).\n"
        f"Сообщение пользователя: \"{last_user_msg}\"\n\n"
        "Если поиск ТРЕБУЕТСЯ, напиши ОДИН поисковый запрос (2-5 слов на русском или английском) без кавычек и лишних знаков.\n"
        "Если поиск НЕ ТРЕБУЕТСЯ, ответь строго словом \"NO\".\n"
        "Отвечай БЕЗ пояснений и кавычек."
    )

    try:
        provider = get_provider(provider_name)
        classifier_model = "gemini-2.5-flash" if provider_name == "gemini" else model
        
        response = await provider.chat(
            messages=[{"role": "user", "content": classifier_prompt}],
            model=classifier_model,
            api_key=api_key
        )
        
        decision = response.strip().strip('"\'')
        if decision.upper() == "NO" or not decision:
            return None, None

        log.info(f"[Search] Decided to search for: '{decision}'")
        search_results = await search_duckduckgo(decision)
        if not search_results:
            return decision, "Ничего не найдено в сети."

        # Format results into a readable context block
        formatted_results = f"\n\n--- РЕЗУЛЬТАТЫ ПОИСКА В СЕТИ ПО ЗАПРОСУ \"{decision}\" ---\n"
        for idx, res in enumerate(search_results, 1):
            formatted_results += f"[{idx}] {res['title']}\nСсылка: {res['url']}\nОписание: {res['snippet']}\n\n"
        formatted_results += "--- КОНЕЦ РЕЗУЛЬТАТОВ ПОИСКА ---\nИспользуй эти данные для ответа пользователю. Указывай ссылки на источники [1], [2] и т.д."
        
        return decision, formatted_results
    except Exception as e:
        log.error(f"[Search] Decision/Search failed: {e}")
        return None, None
