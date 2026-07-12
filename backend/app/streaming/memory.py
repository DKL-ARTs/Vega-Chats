import os
import json
import logging
import re
from app.config import settings
from app.providers import get_provider

log = logging.getLogger("memory")

PROFILE_FILE = os.path.join(settings.workspace_root, "user_profile.json")

DEFAULT_PROFILE = {
    "user_name": "Пользователь",
    "preferred_technologies": [],
    "coding_style_preferences": "Не задан (писать чистый, рабочий код)",
    "about_user": "Обычный пользователь Vega Chat",
    "facts": []
}

def get_user_profile() -> dict:
    """Loads the user profile JSON from disk or returns default"""
    if not os.path.exists(PROFILE_FILE):
        return DEFAULT_PROFILE
    try:
        with open(PROFILE_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        log.error(f"[Memory] Failed to load user profile: {e}")
        return DEFAULT_PROFILE

def save_user_profile(profile: dict):
    """Saves the user profile JSON to disk"""
    try:
        os.makedirs(os.path.dirname(PROFILE_FILE), exist_ok=True)
        with open(PROFILE_FILE, "w", encoding="utf-8") as f:
            json.dump(profile, f, ensure_ascii=False, indent=2)
    except Exception as e:
        log.error(f"[Memory] Failed to save user profile: {e}")

def get_formatted_profile() -> str:
    """Returns a string description of the user profile for LLM prompt"""
    prof = get_user_profile()
    tech = ", ".join(prof.get("preferred_technologies", [])) or "Не указаны"
    facts = "\n".join([f"- {f}" for f in prof.get("facts", [])]) or "Нет дополнительных фактов"
    
    return (
        f"Имя пользователя: {prof.get('user_name', 'Не указано')}\n"
        f"Предпочитаемые технологии/языки: {tech}\n"
        f"Пожелания к коду: {prof.get('coding_style_preferences', 'Не указаны')}\n"
        f"Интересы пользователя: {prof.get('about_user', 'Не указано')}\n"
        f"Дополнительные факты о пользователе:\n{facts}"
    )

async def update_profile_in_background(
    messages: list[dict],
    accumulated_response: str,
    model: str,
    provider_name: str,
    api_key: str
):
    """
    Asynchronously analyzes the conversation and updates the user profile facts.
    Meant to be run as a background task.
    """
    if not messages or not accumulated_response:
        return

    # Extract clean text of the conversation
    conversation_history = ""
    for msg in messages[-5:]: # Look at the last 5 messages for recency
        role = msg.get("role", "user")
        content = msg.get("content", "")
        if isinstance(content, list):
            content = " ".join([item.get("text", "") for item in content if item.get("type") == "text"])
        conversation_history += f"{role.upper()}: {content}\n"
    
    conversation_history += f"ASSISTANT: {accumulated_response}\n"

    current_prof_json = json.dumps(get_user_profile(), ensure_ascii=False, indent=2)

    prompt = (
        "Ты — ИИ-модуль памяти Vega Chat.\n"
        "Твоя задача — обновить профиль пользователя на основе диалога.\n"
        f"Текущий профиль пользователя:\n{current_prof_json}\n\n"
        f"Последний диалог:\n{conversation_history}\n"
        "Выдели новые факты о пользователе (имя, любимые языки/библиотеки, привычки кодирования, проекты, детали работы) и обнови профиль.\n"
        "Правила:\n"
        "1. Сохраняй старые факты, если они не изменились.\n"
        "2. Обновляй имя, технологии, стиль кода и факты при необходимости.\n"
        "3. Если новых фактов нет, верни исходный профиль.\n"
        "4. Отвечай СТРОГО в формате JSON, соответствующем структуре текущего профиля.\n"
        "5. Ничего кроме JSON не выводи (не пиши ```json ... ``` и никаких пояснений!)."
    )

    try:
        provider = get_provider(provider_name)
        # Use fast model for background memory task if possible
        memory_model = "gemini-2.5-flash" if provider_name == "gemini" else model
        
        response = await provider.chat(
            messages=[{"role": "user", "content": prompt}],
            model=memory_model,
            api_key=api_key
        )
        
        # Clean potential markdown block
        clean_json = response.strip()
        if clean_json.startswith("```"):
            # strip start line like ```json
            first_newline = clean_json.find("\n")
            if first_newline != -1:
                clean_json = clean_json[first_newline+1:]
            if clean_json.endswith("```"):
                clean_json = clean_json[:-3]
            elif clean_json.rstrip().endswith("```"):
                clean_json = clean_json.rstrip()[:-3]
        clean_json = clean_json.strip()

        updated_profile = json.loads(clean_json)
        
        # Simple structural validation
        if isinstance(updated_profile, dict) and "user_name" in updated_profile:
            save_user_profile(updated_profile)
            log.info("[Memory] User profile updated successfully")
        else:
            log.warning(f"[Memory] Received invalid profile format: {clean_json}")
    except Exception as e:
        log.error(f"[Memory] Failed to update user profile in background: {e}")
