import asyncio
import subprocess
from fastapi import APIRouter, WebSocket

router = APIRouter()

@router.websocket("/ws/terminal")
async def terminal_ws(websocket: WebSocket):
    await websocket.accept()
    try:
        while True:
            data = await websocket.receive_text()
            if data.strip() == 'exit':
                await websocket.send_text('Session closed')
                break
            try:
                result = subprocess.run(
                    data, shell=True, capture_output=True, text=True, timeout=30
                )
                output = result.stdout + result.stderr
                if not output.strip():
                    output = 'Command executed (no output)'
                await websocket.send_text(output)
            except subprocess.TimeoutExpired:
                await websocket.send_text('Command timed out (30s)')
            except Exception as e:
                await websocket.send_text(f'Error: {e}')
    except Exception:
        pass
