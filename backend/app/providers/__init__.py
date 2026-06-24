from .openrouter import OpenRouterProvider

PROVIDERS = {
    "openrouter": OpenRouterProvider,
}

def get_provider(name: str = "openrouter", api_key: str = None) -> OpenRouterProvider:
    cls = PROVIDERS.get(name, OpenRouterProvider)
    return cls(api_key=api_key)
