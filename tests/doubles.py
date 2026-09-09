"""Test doubles (fakes) usados nos testes do caso de uso — evitam mockar SDKs
externos onde o que importa é testar a orquestração, não a integração real."""
from __future__ import annotations

from postagem_automatica.domain.entities import Canal, Post


class GeradorFalso:
    def __init__(self, texto: str = "post de teste", excecao: Exception | None = None) -> None:
        self._texto = texto
        self._excecao = excecao
        self.temas_recebidos: list[str] = []

    def gerar(self, tema: str) -> str:
        self.temas_recebidos.append(tema)
        if self._excecao:
            raise self._excecao
        return self._texto


class PublisherFalso:
    def __init__(self, canal: Canal, identificador: str = "id-externo", excecao: Exception | None = None) -> None:
        self.canal = canal
        self._identificador = identificador
        self._excecao = excecao
        self.posts_recebidos: list[Post] = []

    def publicar(self, post: Post) -> str:
        self.posts_recebidos.append(post)
        if self._excecao:
            raise self._excecao
        return self._identificador
