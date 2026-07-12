from .openrouter import OpenRouterProvider
from .gemini import GeminiProvider

PROVIDERS = {
    "openrouter": OpenRouterProvider,
    "gemini": GeminiProvider,
}

def get_provider(name: str = "openrouter", api_key: str = None):
    cls = PROVIDERS.get(name, OpenRouterProvider)
    return cls(api_key=api_key)
