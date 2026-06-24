from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    openrouter_api_key: str = ""
    openrouter_base_url: str = "https://openrouter.ai/api/v1"
    default_model: str = "openrouter/auto"
    host: str = "0.0.0.0"
    port: int = 8765
    workspace_root: str = "/tmp/workspace"
    
    class Config:
        env_file = ".env"

settings = Settings()
