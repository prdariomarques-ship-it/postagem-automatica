"""Ports (interfaces) das quais a camada de aplicação depende.

São implementadas na camada de infraestrutura (adapters). O caso de uso em
use_cases.py conhece apenas estes Protocols — nunca o SDK da Anthropic, o
`requests`, o SDK do Twilio ou `sqlite3` diretamente.
"""
from __future__ import annotations

from typing import Protocol

from ..domain.entities import Canal, Post, ResultadoPublicacao


class ContentGenerator(Protocol):
    """Gera o texto de um post a partir de um tema."""

    def gerar(self, tema: str) -> str: ...


class Publisher(Protocol):
    """Publica um Post em um canal específico."""

    canal: Canal

    def publicar(self, post: Post) -> str:
        """Publica o post e retorna o identificador externo (ex: id do post na Meta,
        ou os SIDs de mensagem no Twilio)."""
        ...


class PostRepository(Protocol):
    """Persiste posts gerados e o resultado de cada tentativa de publicação."""

    def salvar_post(self, post: Post) -> None: ...

    def salvar_resultado(self, resultado: ResultadoPublicacao) -> None: ...

    def historico(self, limite: int = 50) -> list[Post]: ...
