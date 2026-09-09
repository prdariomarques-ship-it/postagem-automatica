"""Adapter do Publisher para a Página do Facebook via Graph API."""
from __future__ import annotations

import requests

from ...domain.entities import Canal, Post
from ..retry import retry_http_meta

GRAPH_BASE = "https://graph.facebook.com/v21.0"


class FacebookPublisher:
    canal = Canal.FACEBOOK

    def __init__(self, page_id: str, access_token: str, graph_base: str = GRAPH_BASE) -> None:
        self._page_id = page_id
        self._access_token = access_token
        self._graph_base = graph_base

    @retry_http_meta
    def publicar(self, post: Post) -> str:
        response = requests.post(
            f"{self._graph_base}/{self._page_id}/feed",
            data={"message": post.texto, "access_token": self._access_token},
            timeout=30,
        )
        self._levantar_erro_detalhado(response)
        return response.json()["id"]

    @staticmethod
    def _levantar_erro_detalhado(response: requests.Response) -> None:
        """`response.raise_for_status()` sozinho descarta o corpo JSON do erro.
        A Graph API devolve `error.message`/`code`/`error_subcode` bem específicos
        (token expirado, permissão faltando, etc.) — preservamos isso na mensagem
        para não perder a causa raiz num job rodando sem supervisão."""
        if response.ok:
            return
        try:
            detalhe = response.json().get("error", {})
            mensagem = (
                f"{detalhe.get('message', response.text)} "
                f"(code={detalhe.get('code')}, subcode={detalhe.get('error_subcode')})"
            )
        except ValueError:
            mensagem = response.text
        raise requests.exceptions.HTTPError(f"Graph API {response.status_code}: {mensagem}", response=response)
