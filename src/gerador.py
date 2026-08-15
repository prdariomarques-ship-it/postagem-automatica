"""Gera conteúdo dos posts usando Claude API (padrão) ou Ollama local.

Variáveis de ambiente relevantes:
  AI_BACKEND          "claude" (padrão) | "ollama"
  OLLAMA_HOST         http://localhost:11434  (padrão)
  OLLAMA_MODEL        qwen2.5-coder:7b | qwen3:4b  (padrão: qwen3:4b)
  OLLAMA_NO_CLOUD     1 → rejeita qualquer modelo com :cloud/-cloud
  OLLAMA_CONTEXT_LENGTH  tamanho do contexto em tokens (padrão: 4096)
"""
import json
import os
import random
import urllib.error
import urllib.request

SYSTEM = (
    "Você é um criador de conteúdo cristão para redes sociais. "
    "Escreva em português do Brasil, com tom acolhedor e inspirador. "
    "O texto deve ser curto (até 500 caracteres), pronto para publicar, "
    "sem hashtags excessivas (no máximo 3) e sem preâmbulos como 'Aqui está'."
)

_CLOUD_MARKERS = (":cloud", "-cloud")


def _is_cloud_model(model: str) -> bool:
    low = model.lower()
    return any(low.endswith(m) or m in low for m in _CLOUD_MARKERS)


def _assert_not_cloud(model: str) -> None:
    if _is_cloud_model(model):
        raise ValueError(
            f"Modelo '{model}' identificado como cloud.\n"
            "Configure OLLAMA_MODEL com um modelo local (ex: qwen3:4b ou qwen2.5-coder:7b).\n"
            "Modelos com ':cloud' ou '-cloud' não são permitidos quando OLLAMA_NO_CLOUD=1 "
            "ou AI_BACKEND=ollama."
        )


def _tema() -> str:
    temas = os.environ.get("TEMAS", "reflexão do dia").split(";")
    return random.choice(temas).strip()


# ── Backend Claude ────────────────────────────────────────────────────────────

def _gerar_com_claude(tema: str) -> str:
    import anthropic  # importação tardia: não exigida quando AI_BACKEND=ollama
    client = anthropic.Anthropic()
    response = client.messages.create(
        model="claude-opus-4-8",
        max_tokens=1024,
        system=SYSTEM,
        messages=[{"role": "user", "content": f"Crie um post sobre: {tema}"}],
    )
    return next(b.text for b in response.content if b.type == "text")


# ── Backend Ollama ────────────────────────────────────────────────────────────

def _ollama_host() -> str:
    host = os.environ.get("OLLAMA_HOST", "http://localhost:11434").rstrip("/")
    # Garante que o host é local por padrão; nunca redireciona para api.ollama.com
    if "api.ollama.com" in host:
        raise ValueError(
            f"OLLAMA_HOST aponta para '{host}', que é o Ollama Cloud.\n"
            "Para uso local, mantenha OLLAMA_HOST=http://localhost:11434 ou remova a variável."
        )
    return host


def _gerar_com_ollama(tema: str) -> str:
    host = _ollama_host()
    model = os.environ.get("OLLAMA_MODEL", "qwen3:4b")
    ctx_len = int(os.environ.get("OLLAMA_CONTEXT_LENGTH", "4096"))

    _assert_not_cloud(model)

    payload = json.dumps({
        "model": model,
        "system": SYSTEM,
        "prompt": f"Crie um post sobre: {tema}",
        "stream": False,
        "options": {"num_ctx": ctx_len},
    }).encode()

    req = urllib.request.Request(
        f"{host}/api/generate",
        data=payload,
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
            f"Ollama retornou erro para modelo '{model}': {data['error']}\n"
            "Verifique se o modelo está instalado com: ollama list"
        )

    text = data.get("response", "").strip()
    if not text:
        raise RuntimeError(
            f"Ollama retornou resposta vazia para modelo '{model}'.\n"
            "O modelo pode estar sobrecarregado ou incompatível."
        )
    return text


# ── Ponto de entrada ──────────────────────────────────────────────────────────

def gerar_post() -> str:
    backend = os.environ.get("AI_BACKEND", "claude").lower()
    no_cloud = os.environ.get("OLLAMA_NO_CLOUD", "0") == "1"
    tema = _tema()

    if backend == "ollama":
        return _gerar_com_ollama(tema)

    if no_cloud and backend != "ollama":
        raise RuntimeError(
            "OLLAMA_NO_CLOUD=1 está ativo, mas AI_BACKEND não é 'ollama'.\n"
            "Defina AI_BACKEND=ollama para usar apenas o backend local."
        )

    return _gerar_com_claude(tema)
