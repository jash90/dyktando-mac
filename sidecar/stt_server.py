"""Serwer MLX dla Dyktando — modele, których nie ma w Swifcie (FluidAudio).

  python stt_server.py [--port 7863]

GET  /health                         -> {"ready": true, "loaded": [...], "pid": N}
POST /prepare    {"model": "canary"} -> pobiera i ładuje model (pierwszy raz: kilka minut)
POST /transcribe {"model": "...", "language": "pl" | null, "samples_b64": "<float32 LE, 16 kHz mono>"}
                                     -> {"text": "...", "ms": N, "language": "pl"}

Słucha tylko na 127.0.0.1 i wymaga nagłówka `X-Dyktando-Token` (token z env DYKTANDO_SIDECAR_TOKEN,
losowany przez aplikację przy każdym starcie) — inaczej dowolna strona w przeglądarce mogłaby wysłać
„prosty” POST na localhost. Własny nagłówek wymusza preflight CORS, którego serwer nie obsługuje. Całe MLX (ładowanie i inferencja) idzie przez jeden wątek —
MLX wiąże strumienie GPU z wątkiem, w którym załadowano model.
"""

from __future__ import annotations

import argparse
import base64
import gc
import json
import os
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np

SR = 16_000
MODELS = {
    "canary": "qfuxa/canary-mlx",
    "whisper-turbo": "mlx-community/whisper-large-v3-turbo",
    "whisper-large": "mlx-community/whisper-large-v3-mlx",
}
CANARY_MAX_S = 30.0  # dłuższe wejście Canary ucina (limit tokenów dekodera)

MLX = ThreadPoolExecutor(max_workers=1, thread_name_prefix="mlx")
_loaded: dict[str, object] = {}
TOKEN = os.environ.get("DYKTANDO_SIDECAR_TOKEN", "")


def _load(key: str):
    if key in _loaded:
        return _loaded[key]
    # Jeden model naraz: trzy załadowane modele to ~10 GB pamięci (realny przypadek).
    if _loaded:
        import mlx.core as mx

        _loaded.clear()
        gc.collect()
        mx.clear_cache()
    repo = MODELS[key]
    if key == "canary":
        from mlx_audio.stt import load

        model = load(repo)
        model.generate(np.zeros(SR, np.float32), source_lang="pl", target_lang="pl")  # rozgrzewka
    else:
        import mlx_whisper
        from huggingface_hub import snapshot_download

        snapshot_download(repo)
        mlx_whisper.transcribe(np.zeros(SR, np.float32), path_or_hf_repo=repo, language="pl")
        model = repo  # mlx_whisper trzyma model w swoim cache — wystarczy repo
    _loaded[key] = model
    return model


def _split_on_silence(samples: np.ndarray, max_s: float) -> list[tuple[int, int]]:
    """Kawałki <= max_s, cięte w najcichszym miejscu ostatnich 5 s każdego okna."""
    max_n, search_n, win = int(max_s * SR), int(5 * SR), int(0.1 * SR)
    spans, start = [], 0
    while len(samples) - start > max_n:
        lo, hi = max(start + 1, start + max_n - search_n), start + max_n
        frames = samples[lo:hi][: (hi - lo) // win * win].reshape(-1, win)
        cut = lo + int(np.argmin((frames**2).mean(axis=1))) * win + win // 2
        spans.append((start, cut))
        start = cut
    spans.append((start, len(samples)))
    return spans


def _transcribe(key: str, samples: np.ndarray, language: str | None) -> tuple[str, str | None]:
    model = _load(key)
    if key == "canary":
        lang = language or "pl"  # Canary nie wykrywa języka sam
        parts = [
            model.generate(samples[a:b], source_lang=lang, target_lang=lang).text.strip()
            for a, b in _split_on_silence(samples, CANARY_MAX_S)
        ]
        return " ".join(p for p in parts if p), lang

    import mlx_whisper

    r = mlx_whisper.transcribe(
        samples, path_or_hf_repo=model, language=language, condition_on_previous_text=False
    )
    return r["text"].strip(), r.get("language") or language


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _reply(self, code: int, body: dict) -> None:
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _authorized(self) -> bool:
        if TOKEN and self.headers.get("X-Dyktando-Token") == TOKEN:
            return True
        self._reply(403, {"error": "forbidden"})
        return False

    def do_GET(self):
        if not self._authorized():
            return
        if self.path == "/health":
            return self._reply(200, {"service": "dyktando-sidecar", "ready": True, "loaded": sorted(_loaded), "pid": os.getpid()})
        self._reply(404, {"error": "not found"})

    def do_POST(self):
        if not self._authorized():
            return
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
            key = body.get("model")
            if key not in MODELS:
                return self._reply(400, {"error": f"nieznany model: {key}"})
            if self.path == "/prepare":
                t = time.time()
                MLX.submit(_load, key).result()
                return self._reply(200, {"ok": True, "seconds": round(time.time() - t, 1)})
            if self.path == "/transcribe":
                samples = np.frombuffer(base64.b64decode(body["samples_b64"]), dtype="<f4").astype(np.float32)
                t = time.time()
                text, lang = MLX.submit(_transcribe, key, samples, body.get("language")).result()
                return self._reply(200, {"text": text, "ms": int((time.time() - t) * 1000), "language": lang})
            self._reply(404, {"error": "not found"})
        except Exception as e:  # noqa: BLE001 — błąd wraca do aplikacji zamiast zrywać połączenie
            self._reply(500, {"error": f"{type(e).__name__}: {e}"})


def _watch_parent(pid: int) -> None:
    while True:
        time.sleep(2)
        if os.getppid() != pid:  # rodzic zniknął — proces przejęty przez launchd
            os._exit(0)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=7863)
    ap.add_argument("--parent-pid", type=int, default=0, help="zakończ, gdy ten proces zniknie")
    args = ap.parse_args()
    if not TOKEN:
        raise SystemExit("brak DYKTANDO_SIDECAR_TOKEN — serwer startuje tylko z aplikacji Dyktando")
    if args.parent_pid:
        threading.Thread(target=_watch_parent, args=(args.parent_pid,), daemon=True).start()
    # Po restarcie aplikacji poprzedni serwer kończy się dopiero ~2 s później (watchdog) — poczekaj na port.
    for attempt in range(20):
        try:
            server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
            break
        except OSError:
            if attempt == 19:
                raise
            time.sleep(0.5)
    print(f"dyktando-sidecar pid={os.getpid()} port={args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
