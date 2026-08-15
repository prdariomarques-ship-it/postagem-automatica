"""Gera conteúdo dos posts usando o backend configurado em AI_BACKEND.

Delega a seleção de backend para work/deepseek_ai.py, que suporta:
  ollama (local), deepseek, openai e auto.
"""
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "work"))
import deepseek_ai  # noqa: E402

SYSTEM = (
    "Você é um criador de conteúdo cristão para redes sociais. "
    "Escreva em português do Brasil, com tom acolhedor e inspirador. "
    "O texto deve ser curto (até 500 caracteres), pronto para publicar, "
    "sem hashtags excessivas (no máximo 3) e sem preâmbulos como 'Aqui está'."
)


def gerar_post() -> str:
    temas = os.environ.get("TEMAS", "reflexão do dia").split(";")
    tema = random.choice(temas).strip()
    return deepseek_ai.generate(
        prompt=f"Crie um post sobre: {tema}",
        system=SYSTEM,
    )
