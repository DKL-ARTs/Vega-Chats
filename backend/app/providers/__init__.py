from .openrouter import OpenRouterProvider

PROVIDERS = {
    "openrouter": OpenRouterProvider,
}

def get_provider(name: str = "openrouter") -> OpenRouterProvider:
    cls = PROVIDERS.get(name, OpenRouterProvider)
    return cls()
