import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.config import settings
from app.streaming.sse import router as sse_router
from app.files.manager import router as files_router
from app.terminal.shell import router as terminal_router

app = FastAPI(title="Vega Chat API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(sse_router, prefix="/api")
app.include_router(files_router, prefix="/api")
app.include_router(terminal_router)

@app.get("/health")
async def health():
    return {"status": "ok", "version": "0.1.0"}

if __name__ == "__main__":
    import uvicorn
    os.makedirs(settings.workspace_root, exist_ok=True)
    uvicorn.run(app, host=settings.host, port=settings.port)
