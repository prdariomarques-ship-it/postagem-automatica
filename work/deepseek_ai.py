"""Backend de IA configurável por variável de ambiente.

Suporte a quatro modos via AI_BACKEND:
  ollama   — Ollama local em OLLAMA_HOST (padrão: http://localhost:11434)
  deepseek — DeepSeek cloud (requer DEEPSEEK_API_KEY)
  openai   — OpenAI cloud (requer OPENAI_API_KEY)
  auto     — DeepSeek quando DEEPSEEK_API_KEY existir; OpenAI como fallback

Modo local não requer chave de API. Nomes de modelo contendo ':cloud'
ou terminados em '-cloud' são bloqueados quando AI_BACKEND=ollama.

Variáveis de servidor Ollama (definidas no processo ollama serve / systemd):
  OLLAMA_NUM_PARALLEL      requisições paralelas por modelo (recomendado: 1 em GPU limitada)
  OLLAMA_MAX_LOADED_MODELS modelos simultâneos na VRAM    (recomendado: 1 em GPU limitada)
  OLLAMA_KEEP_ALIVE        tempo de retenção na VRAM      ("0" libera imediatamente)
  OLLAMA_NO_CLOUD          "1" bloqueia recursos cloud do servidor Ollama

Variáveis de cliente (usadas por este módulo):
  AI_BACKEND               ollama | deepseek | openai | auto
  OLLAMA_HOST              endpoint do servidor (padrão: http://localhost:11434)
  OLLAMA_MODEL             modelo local (padrão: qwen3:4b)
  OLLAMA_CONTEXT_LENGTH    tokens de contexto por requisição (padrão: 4096)
  OLLAMA_KEEP_ALIVE        também enviado por requisição quando definido
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request

# ── Constantes ────────────────────────────────────────────────────────────────

_CLOUD_MARKERS = (":cloud", "-cloud")


def _is_cloud_model(name: str) -> bool:
    low = name.lower()
    return any(low.endswith(m) or m in low for m in _CLOUD_MARKERS)


def _reject_cloud_model(name: str) -> None:
    if _is_cloud_model(name):
        raise ValueError(
            f"Modelo '{name}' identificado como cloud.\n"
            "Defina OLLAMA_MODEL com um modelo local, por exemplo:\n"
            "  OLLAMA_MODEL=qwen3:4b\n"
            "  OLLAMA_MODEL=qwen2.5-coder:7b"
        )


# ── Backend Ollama ────────────────────────────────────────────────────────────

def _ollama_generate(prompt: str, system: str = "") -> str:
    host = os.environ.get("OLLAMA_HOST", "http://localhost:11434").rstrip("/")
    model = os.environ.get("OLLAMA_MODEL", "qwen3:4b")
    ctx_len = int(os.environ.get("OLLAMA_CONTEXT_LENGTH", "4096"))

    if "api.ollama.com" in host:
        raise ValueError(
            f"OLLAMA_HOST aponta para '{host}' (Ollama Cloud).\n"
            "Para uso local, use OLLAMA_HOST=http://localhost:11434 ou remova a variável."
        )

    _reject_cloud_model(model)

    payload: dict = {
        "model": model,
        "prompt": prompt,
        "stream": False,
        "options": {"num_ctx": ctx_len},
    }
    if system:
        payload["system"] = system

    # Retenção de VRAM por requisição: "0" libera imediatamente, "-1" retém indefinidamente.
    # Apenas substitui o padrão do servidor quando definido explicitamente no cliente.
    keep_alive = os.environ.get("OLLAMA_KEEP_ALIVE")
    if keep_alive is not None:
        payload["keep_alive"] = keep_alive

    data_bytes = json.dumps(payload).encode()
    req = urllib.request.Request(
        f"{host}/api/generate",
        data=data_bytes,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = json.loads(resp.read())
    except urllib.error.URLError as exc:
        raise RuntimeError(
            f"Ollama não respondeu em {host}.\n"
            "Verifique se o serviço está rodando:\n"
            "  ollama serve              (macOS/Linux)\n"
            "  Abra o app Ollama        (Windows/macOS)\n"
            f"Erro original: {exc}"
        ) from exc

    if "error" in data:
        raise RuntimeError(
            f"Ollama retornou erro para '{model}': {data['error']}\n"
            "Verifique se o modelo está instalado: ollama list"
        )

    text = data.get("response", "").strip()
    if not text:
        raise RuntimeError(
            f"Ollama retornou resposta vazia para modelo '{model}'."
        )
    return text


# ── Backend DeepSeek ──────────────────────────────────────────────────────────

def _deepseek_generate(prompt: str, system: str = "") -> str:
    api_key = os.environ.get("DEEPSEEK_API_KEY", "")
    if not api_key:
        raise RuntimeError(
            "AI_BACKEND=deepseek mas DEEPSEEK_API_KEY não está definida.\n"
            "Obtenha uma chave em https://platform.deepseek.com/"
        )
    model = os.environ.get("DEEPSEEK_MODEL", "deepseek-chat")
    return _openai_compat_generate(
        prompt=prompt,
        system=system,
        api_key=api_key,
        model=model,
        base_url="https://api.deepseek.com/v1",
    )


# ── Backend OpenAI ────────────────────────────────────────────────────────────

def _openai_generate(prompt: str, system: str = "") -> str:
    api_key = os.environ.get("OPENAI_API_KEY", "")
    if not api_key:
        raise RuntimeError(
            "AI_BACKEND=openai mas OPENAI_API_KEY não está definida.\n"
            "Obtenha uma chave em https://platform.openai.com/"
        )
    model = os.environ.get("OPENAI_MODEL", "gpt-4o-mini")
    return _openai_compat_generate(
        prompt=prompt,
        system=system,
        api_key=api_key,
        model=model,
        base_url="https://api.openai.com/v1",
    )


def _openai_compat_generate(
    prompt: str, system: str, api_key: str, model: str, base_url: str
) -> str:
    messages: list[dict] = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})

    payload = json.dumps({
        "model": model,
        "messages": messages,
    }).encode()

    req = urllib.request.Request(
        f"{base_url}/chat/completions",
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        raise RuntimeError(
            f"Erro HTTP {exc.code} de {base_url}: {body[:400]}"
        ) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Falha de conexão com {base_url}: {exc}") from exc

    try:
        return data["choices"][0]["message"]["content"].strip()
    except (KeyError, IndexError) as exc:
        raise RuntimeError(f"Resposta inesperada da API: {data}") from exc


# ── Ponto de entrada público ──────────────────────────────────────────────────

def generate(prompt: str, system: str = "") -> str:
    """Gera texto pelo backend configurado em AI_BACKEND.

    Args:
        prompt: Mensagem do usuário.
        system: Instrução de sistema opcional.

    Returns:
        Texto gerado pelo modelo.

    Raises:
        ValueError: Configuração inválida (modelo cloud em modo local, host inválido).
        RuntimeError: Falha de comunicação com o backend ou resposta vazia.
    """
    backend = os.environ.get("AI_BACKEND", "auto").lower()
    no_cloud = os.environ.get("OLLAMA_NO_CLOUD", "0") == "1"

    if no_cloud and backend != "ollama":
        raise RuntimeError(
            "OLLAMA_NO_CLOUD=1 está ativo, mas AI_BACKEND não é 'ollama'.\n"
            "Defina AI_BACKEND=ollama para permanecer no modo local."
        )

    if backend == "ollama":
        return _ollama_generate(prompt, system)

    if backend == "deepseek":
        return _deepseek_generate(prompt, system)

    if backend == "openai":
        return _openai_generate(prompt, system)

    if backend == "auto":
        if os.environ.get("DEEPSEEK_API_KEY"):
            return _deepseek_generate(prompt, system)
        if os.environ.get("OPENAI_API_KEY"):
            return _openai_generate(prompt, system)
        raise RuntimeError(
            "AI_BACKEND=auto mas nenhuma chave de API encontrada.\n"
            "Defina DEEPSEEK_API_KEY, OPENAI_API_KEY ou use AI_BACKEND=ollama para uso local."
        )

    raise ValueError(
        f"AI_BACKEND='{backend}' não é um valor reconhecido.\n"
        "Valores aceitos: ollama, deepseek, openai, auto"
    )
