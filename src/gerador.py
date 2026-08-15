"""Gera conteúdo dos posts usando Claude API (padrão) ou Ollama local."""
import os
import random
import urllib.error
import urllib.request
import json

SYSTEM = (
    "Você é um criador de conteúdo cristão para redes sociais. "
    "Escreva em português do Brasil, com tom acolhedor e inspirador. "
    "O texto deve ser curto (até 500 caracteres), pronto para publicar, "
    "sem hashtags excessivas (no máximo 3) e sem preâmbulos como 'Aqui está'."
)


def _tema() -> str:
    temas = os.environ.get("TEMAS", "reflexão do dia").split(";")
    return random.choice(temas).strip()


def _gerar_com_claude(tema: str) -> str:
    import anthropic
    client = anthropic.Anthropic()
    response = client.messages.create(
        model="claude-opus-4-8",
        max_tokens=1024,
        system=SYSTEM,
        messages=[{"role": "user", "content": f"Crie um post sobre: {tema}"}],
    )
    return next(b.text for b in response.content if b.type == "text")


def _gerar_com_ollama(tema: str) -> str:
    host = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
    model = os.environ.get("OLLAMA_MODEL", "qwen3:4b")

    # Verifica modelo sem sufixo cloud para evitar uso involuntário da nuvem
    if ":cloud" in model or "-cloud" in model:
        raise ValueError(
            f"Modelo '{model}' parece ser um modelo cloud. "
            "Defina OLLAMA_MODEL com um modelo local (ex: qwen3:4b)."
        )

    payload = json.dumps({
        "model": model,
        "system": SYSTEM,
        "prompt": f"Crie um post sobre: {tema}",
        "stream": False,
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
            f"Ollama não respondeu em {host}. "
            "Verifique se o serviço está rodando: ollama serve"
        ) from exc

    if "error" in data:
        raise RuntimeError(f"Erro do Ollama: {data['error']}")

    return data.get("response", "").strip()


def gerar_post() -> str:
    backend = os.environ.get("AI_BACKEND", "claude").lower()
    tema = _tema()

    if backend == "ollama":
        return _gerar_com_ollama(tema)
    return _gerar_com_claude(tema)
