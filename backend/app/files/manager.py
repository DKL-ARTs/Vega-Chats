import os
import shutil
import subprocess
from pathlib import Path
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from fastapi.responses import FileResponse
from app.config import settings

router = APIRouter()

class FileRead(BaseModel):
    path: str

class FileWrite(BaseModel):
    path: str
    content: str

class FileDelete(BaseModel):
    path: str

class FileRename(BaseModel):
    old_path: str
    new_path: str

class GitCommitReq(BaseModel):
    message: str
    cwd: str = None

def safe_path(path: str) -> Path:
    # Resolve the path to absolute
    p = Path(path)
    
    # If the client specifies an absolute path that is inside allowed directories, allow it directly
    allowed_prefixes = ('/root', '/sdcard', '/storage', '/var', '/tmp')
    if p.is_absolute():
        resolved = p.resolve()
        if any(str(resolved).startswith(prefix) for prefix in allowed_prefixes):
            return resolved
    
    # Otherwise resolve it relative to settings.workspace_root
    root = Path(settings.workspace_root).resolve()
    if p.is_absolute():
        try:
            # try to strip root slash if any
            relative = p.relative_to("/")
            resolved = (root / relative).resolve()
        except ValueError:
            resolved = (root / str(p).lstrip("/")).resolve()
    else:
        resolved = (root / p).resolve()
        
    return resolved

@router.post("/files/read")
async def read_file(req: FileRead):
    p = safe_path(req.path)
    if not p.exists():
        raise HTTPException(404, "File not found")
    if p.is_dir():
        raise HTTPException(400, "Path is a directory")
    return {"content": p.read_text(encoding='utf-8', errors='replace'), "path": str(p)}

@router.post("/files/write")
async def write_file(req: FileWrite):
    p = safe_path(req.path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(req.content, encoding='utf-8')
    return {"ok": True, "path": str(p)}

@router.post("/files/list")
async def list_files(req: FileRead):
    p = safe_path(req.path)
    if not p.exists():
        raise HTTPException(404, "Directory not found")
    if not p.is_dir():
        raise HTTPException(400, "Not a directory")
    items = []
    try:
        for child in sorted(p.iterdir()):
            try:
                is_dir = child.is_dir()
                size = child.stat().st_size if child.is_file() else 0
                items.append({
                    "name": child.name,
                    "is_dir": is_dir,
                    "size": size,
                })
            except Exception:
                # Skip files with permission errors
                pass
    except Exception as e:
        raise HTTPException(500, f"Error listing directory: {str(e)}")
    return {"items": items, "path": str(p)}

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

@router.post("/files/delete")
async def delete_file(req: FileDelete):
    p = safe_path(req.path)
    if not p.exists():
        raise HTTPException(404, "File/directory not found")
    try:
        if p.is_dir():
            shutil.rmtree(p)
        else:
            p.unlink()
        return {"ok": True}
    except Exception as e:
        raise HTTPException(500, f"Error deleting file/directory: {str(e)}")

@router.post("/files/rename")
async def rename_file(req: FileRename):
    old_p = safe_path(req.old_path)
    new_p = safe_path(req.new_path)
    if not old_p.exists():
        raise HTTPException(404, "Source path not found")
    try:
        old_p.rename(new_p)
        return {"ok": True}
    except Exception as e:
        raise HTTPException(500, f"Error renaming file/directory: {str(e)}")

@router.get("/git/status")
async def git_status(cwd: str = Query(None)):
    git_root = safe_path(cwd) if cwd else Path(settings.workspace_root)
    if not (git_root / ".git").exists():
        return {"ok": False, "error": "Not a git repository"}
    try:
        res = subprocess.run(
            ["git", "status", "-s"],
            cwd=str(git_root),
            capture_output=True,
            text=True,
            check=True
        )
        lines = res.stdout.strip().split("\n")
        files = []
        for line in lines:
            if not line.strip():
                continue
            parts = line.split(maxsplit=1)
            if len(parts) == 2:
                status, path = parts
                files.append({"status": status.strip(), "path": path.strip()})
        return {"ok": True, "files": files}
    except Exception as e:
        return {"ok": False, "error": str(e)}

@router.post("/git/init")
async def git_init(req: FileRead):
    git_root = safe_path(req.path)
    try:
        subprocess.run(["git", "init"], cwd=str(git_root), check=True)
        return {"ok": True}
    except Exception as e:
        return {"ok": False, "error": str(e)}

@router.post("/git/commit-push")
async def git_commit_push(req: GitCommitReq):
    git_root = safe_path(req.cwd) if req.cwd else Path(settings.workspace_root)
    if not (git_root / ".git").exists():
        return {"ok": False, "error": "Not a git repository"}
    try:
        # 1. git add .
        subprocess.run(["git", "add", "."], cwd=str(git_root), check=True)
        # 2. git commit -m message
        subprocess.run(["git", "commit", "-m", req.message], cwd=str(git_root), check=True)
        # 3. Get current branch
        branch_res = subprocess.run(["git", "branch", "--show-current"], cwd=str(git_root), capture_output=True, text=True, check=True)
        branch = branch_res.stdout.strip() or "main"
        
        # 4. Try pushing to "new", then "origin", then default
        push_res = subprocess.run(["git", "push", "new", branch], cwd=str(git_root), capture_output=True, text=True)
        if push_res.returncode != 0:
            push_res = subprocess.run(["git", "push", "origin", branch], cwd=str(git_root), capture_output=True, text=True)
            if push_res.returncode != 0:
                push_res = subprocess.run(["git", "push"], cwd=str(git_root), capture_output=True, text=True)
        
        if push_res.returncode != 0:
            return {"ok": False, "error": f"Push failed: {push_res.stderr.strip() or push_res.stdout.strip()}"}
            
        return {"ok": True, "stdout": push_res.stdout.strip(), "stderr": push_res.stderr.strip()}
    except Exception as e:
        return {"ok": False, "error": str(e)}
