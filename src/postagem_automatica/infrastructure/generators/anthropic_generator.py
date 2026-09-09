"""Adapter do ContentGenerator (application/ports.py) usando a API do Claude."""
from __future__ import annotations

import anthropic

from ..retry import retry_anthropic

SYSTEM = (
    "Você é um criador de conteúdo cristão para redes sociais. "
    "Escreva em português do Brasil, com tom acolhedor e inspirador. "
    "O texto deve ser curto (até 500 caracteres), pronto para publicar, "
    "sem hashtags excessivas (no máximo 3) e sem preâmbulos como 'Aqui está'."
)


class AnthropicContentGenerator:
    """Gera o texto de posts usando um modelo Claude.

    O client é injetado com a api_key explícita (em vez do SDK ler
    ANTHROPIC_API_KEY do ambiente por conta própria) para manter a classe
    testável e a leitura de configuração centralizada em Settings.from_env().
    """

    def __init__(self, api_key: str, model: str, system_prompt: str = SYSTEM) -> None:
        self._client = anthropic.Anthropic(api_key=api_key)
        self._model = model
        self._system_prompt = system_prompt

    @retry_anthropic
    def gerar(self, tema: str) -> str:
        response = self._client.messages.create(
            model=self._model,
            max_tokens=1024,
            system=self._system_prompt,
            messages=[{"role": "user", "content": f"Crie um post sobre: {tema}"}],
        )
        return next(bloco.text for bloco in response.content if bloco.type == "text")
