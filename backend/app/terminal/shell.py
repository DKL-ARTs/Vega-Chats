import asyncio
import os
from fastapi import APIRouter, WebSocket

router = APIRouter()

@router.websocket("/ws/terminal")
async def terminal_ws(websocket: WebSocket):
    await websocket.accept()
    
    # Spawn a persistent interactive shell (bash or sh)
    shell = 'bash' if os.path.exists('/bin/bash') else 'sh'
    
    # Set default directory to workspace if exists
    default_cwd = '/root/workspace' if os.path.exists('/root/workspace') else None
    
    process = await asyncio.create_subprocess_exec(
        shell,
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        cwd=default_cwd,
        env=os.environ.copy()
    )

    async def read_stream(stream, ws):
        try:
            while True:
                # Read chunks of output and stream them immediately to the client
                data = await stream.read(4096)
                if not data:
                    break
                await ws.send_text(data.decode('utf-8', errors='replace'))
        except Exception:
            pass

    # Start background tasks to read stdout and stderr from process
    stdout_task = asyncio.create_task(read_stream(process.stdout, websocket))
    stderr_task = asyncio.create_task(read_stream(process.stderr, websocket))

    try:
        while True:
            cmd = await websocket.receive_text()
            if cmd.strip() == 'exit':
                break
            
            # Send the command to the persistent shell session
            if not cmd.endswith('\n'):
                cmd += '\n'
            
            if process.stdin:
                process.stdin.write(cmd.encode('utf-8'))
                await process.stdin.drain()
    except Exception:
        pass
    finally:
        # Cancel streaming tasks
        stdout_task.cancel()
        stderr_task.cancel()
        
        # Clean up the shell process
        if process.returncode is None:
            try:
                process.terminate()
                await process.wait()
            except Exception:
                pass
