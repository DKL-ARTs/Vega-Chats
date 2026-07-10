import os
from pathlib import Path
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()

class FileRead(BaseModel):
    path: str

class FileWrite(BaseModel):
    path: str
    content: str

def safe_path(path: str, root: str = "/root/workspace") -> Path:
    p = Path(path)
    if p.is_absolute():
        p = Path(root) / p.relative_to("/") if str(p).startswith("/") else p
    else:
        p = Path(root) / p
    p = p.resolve()
    if not str(p).startswith(str(Path(root).resolve())):
        raise HTTPException(403, "Path traversal detected")
    return p

@router.post("/files/read")
async def read_file(req: FileRead):
    p = safe_path(req.path)
    if not p.exists():
        raise HTTPException(404, "File not found")
    return {"content": p.read_text(), "path": str(p)}

@router.post("/files/write")
async def write_file(req: FileWrite):
    p = safe_path(req.path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(req.content)
    return {"ok": True, "path": str(p)}

@router.post("/files/list")
async def list_files(req: FileRead):
    p = safe_path(req.path)
    if not p.is_dir():
        raise HTTPException(400, "Not a directory")
    items = []
    for child in sorted(p.iterdir()):
        items.append({
            "name": child.name,
            "is_dir": child.is_dir(),
            "size": child.stat().st_size if child.is_file() else 0,
        })
    return {"items": items, "path": str(p)}

from fastapi.responses import FileResponse

@router.get("/files/download")
async def download_file(path: str):
    p = safe_path(path)
    if not p.exists() or not p.is_file():
        raise HTTPException(404, "File not found")
    return FileResponse(
        path=p,
        filename=p.name,
        media_type="application/octet-stream"
    )

