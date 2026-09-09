"""Adapter do Publisher para Instagram via Graph API.

Não está registrado por padrão em infrastructure/registry.py: o pipeline atual
(gerador.py -> AnthropicContentGenerator) só produz texto, e a publicação no
Instagram exige uma imagem hospedada em URL pública (`image_url`) — publicar
sem isso simplesmente não é possível na API da Meta. `publicar()` levanta
NotImplementedError de propósito para deixar isso explícito caso alguém
registre esta classe sem perceber a limitação.

Fica pronto para ligar (via PublisherRegistry.registrar) assim que existir um
passo de geração/hospedagem de imagem no pipeline: nesse momento, use
`publicar_com_imagem()`.
"""
from __future__ import annotations

import requests

from ...domain.entities import Canal, Post
from ..retry import retry_http_meta
from .facebook_publisher import GRAPH_BASE


class InstagramPublisher:
    canal = Canal.INSTAGRAM

    def __init__(self, ig_user_id: str, access_token: str, graph_base: str = GRAPH_BASE) -> None:
        self._ig_user_id = ig_user_id
        self._access_token = access_token
        self._graph_base = graph_base

    def publicar(self, post: Post) -> str:
        raise NotImplementedError(
            "InstagramPublisher exige uma imagem — use publicar_com_imagem(post, imagem_url) "
            "quando o pipeline tiver um passo de geração/hospedagem de imagem."
        )

    @retry_http_meta
    def publicar_com_imagem(self, post: Post, imagem_url: str) -> str:
        criacao = requests.post(
            f"{self._graph_base}/{self._ig_user_id}/media",
            data={"image_url": imagem_url, "caption": post.texto, "access_token": self._access_token},
            timeout=30,
        )
        criacao.raise_for_status()
        creation_id = criacao.json()["id"]

        publicacao = requests.post(
            f"{self._graph_base}/{self._ig_user_id}/media_publish",
            data={"creation_id": creation_id, "access_token": self._access_token},
            timeout=30,
        )
        publicacao.raise_for_status()
        return publicacao.json()["id"]
