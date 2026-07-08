"""Gera o conteúdo dos posts usando a API do Claude."""
import os
import random

import anthropic

client = anthropic.Anthropic()  # usa ANTHROPIC_API_KEY do .env

SYSTEM = (
    "Você é um criador de conteúdo cristão para redes sociais. "
    "Escreva em português do Brasil, com tom acolhedor e inspirador. "
    "O texto deve ser curto (até 500 caracteres), pronto para publicar, "
    "sem hashtags excessivas (no máximo 3) e sem preâmbulos como 'Aqui está'."
)


def gerar_post() -> str:
    temas = os.environ.get("TEMAS", "reflexão do dia").split(";")
    tema = random.choice(temas).strip()

    response = client.messages.create(
        model="claude-opus-4-8",
        max_tokens=1024,
        system=SYSTEM,
        messages=[{"role": "user", "content": f"Crie um post sobre: {tema}"}],
    )
    return next(b.text for b in response.content if b.type == "text")
