"""Entidades de domínio do sistema de postagem automática."""
from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum


class Canal(str, Enum):
    """Canais de publicação suportados pelo domínio.

    INSTAGRAM existe como conceito de domínio, mas não há Publisher registrado
    para ele em infrastructure/registry.py hoje — ver publishers/instagram_publisher.py.
    """

    FACEBOOK = "facebook"
    WHATSAPP = "whatsapp"
    INSTAGRAM = "instagram"


class StatusPublicacao(str, Enum):
    SUCESSO = "sucesso"
    FALHA = "falha"


@dataclass(frozen=True, slots=True)
class Post:
    """Um post gerado, pronto para ser publicado nos canais registrados."""

    id: str
    tema: str
    texto: str
    criado_em: datetime

    @staticmethod
    def novo(tema: str, texto: str) -> "Post":
        return Post(id=str(uuid.uuid4()), tema=tema, texto=texto, criado_em=datetime.now())


@dataclass(frozen=True, slots=True)
class ResultadoPublicacao:
    """Resultado de uma tentativa de publicar um Post em um Canal específico."""

    post_id: str
    canal: Canal
    status: StatusPublicacao
    identificador_externo: str | None = None
    erro: str | None = None
    publicado_em: datetime = field(default_factory=datetime.now)

    @staticmethod
    def sucesso(post_id: str, canal: Canal, identificador_externo: str) -> "ResultadoPublicacao":
        return ResultadoPublicacao(
            post_id=post_id,
            canal=canal,
            status=StatusPublicacao.SUCESSO,
            identificador_externo=identificador_externo,
        )

    @staticmethod
    def falha(post_id: str, canal: Canal, erro: str) -> "ResultadoPublicacao":
        return ResultadoPublicacao(post_id=post_id, canal=canal, status=StatusPublicacao.FALHA, erro=erro)
