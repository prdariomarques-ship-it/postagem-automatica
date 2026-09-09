"""Eventos de domínio publicados no EventBus durante o ciclo de vida de um post.

Desacoplam a orquestração (application/use_cases.py) de quem reage aos eventos —
hoje só há um handler de logging (postagem_automatica/__main__.py), mas o mesmo
EventBus é o ponto de extensão natural para, por exemplo, notificar o store_agent
do ship-it quando uma publicação falha, sem tocar no caso de uso.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime

from .entities import Post, ResultadoPublicacao


@dataclass(frozen=True, slots=True)
class PostGerado:
    """Emitido depois que o conteúdo de um post é gerado e persistido com sucesso."""

    post: Post
    ocorrido_em: datetime = field(default_factory=datetime.now)


@dataclass(frozen=True, slots=True)
class PostPublicado:
    """Emitido para cada canal em que a publicação teve sucesso."""

    resultado: ResultadoPublicacao
    ocorrido_em: datetime = field(default_factory=datetime.now)


@dataclass(frozen=True, slots=True)
class PublicacaoFalhou:
    """Emitido para cada canal em que a publicação falhou (após esgotar os retries)."""

    resultado: ResultadoPublicacao
    ocorrido_em: datetime = field(default_factory=datetime.now)


@dataclass(frozen=True, slots=True)
class GeracaoFalhou:
    """Emitido quando a geração de conteúdo falha — nenhum canal chega a ser tentado."""

    tema: str
    erro: str
    ocorrido_em: datetime = field(default_factory=datetime.now)
