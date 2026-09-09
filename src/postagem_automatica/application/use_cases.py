"""Caso de uso principal: gerar um post e publicá-lo em todos os canais registrados."""
from __future__ import annotations

import logging

from ..domain.entities import Post, ResultadoPublicacao
from ..domain.events import GeracaoFalhou, PostGerado, PostPublicado, PublicacaoFalhou
from ..domain.exceptions import GeracaoConteudoError
from .event_bus import EventBus
from .ports import ContentGenerator, PostRepository, Publisher

logger = logging.getLogger(__name__)


class ExecutarPostagemUseCase:
    """Orquestra: gerar conteúdo -> publicar em cada canal registrado -> persistir resultado.

    Depende apenas de ports (ContentGenerator, Publisher, PostRepository) e do
    EventBus — nunca de SDKs concretos. É isso que permite trocar o provedor de
    geração, ou adicionar/remover canais via PublisherRegistry (Open/Closed),
    sem tocar nesta classe.

    A falha de um canal nunca impede a tentativa nos demais: cada Publisher é
    isolado, e o resultado (sucesso ou falha) é sempre registrado e devolvido.
    """

    def __init__(
        self,
        gerador: ContentGenerator,
        publishers: list[Publisher],
        repositorio: PostRepository,
        event_bus: EventBus,
    ) -> None:
        self._gerador = gerador
        self._publishers = publishers
        self._repositorio = repositorio
        self._event_bus = event_bus

    def executar(self, tema: str) -> list[ResultadoPublicacao]:
        post = self._gerar_post(tema)

        resultados: list[ResultadoPublicacao] = []
        for publisher in self._publishers:
            resultado = self._publicar_em_um_canal(post, publisher)
            resultados.append(resultado)
            self._repositorio.salvar_resultado(resultado)

        return resultados

    def _gerar_post(self, tema: str) -> Post:
        try:
            texto = self._gerador.gerar(tema)
        except Exception as exc:
            logger.error("Falha ao gerar conteúdo para tema %r: %s", tema, exc)
            self._event_bus.publish(GeracaoFalhou(tema=tema, erro=str(exc)))
            raise GeracaoConteudoError(f"Falha ao gerar conteúdo para tema {tema!r}: {exc}") from exc

        post = Post.novo(tema=tema, texto=texto)
        self._repositorio.salvar_post(post)
        self._event_bus.publish(PostGerado(post=post))
        logger.info("Post %s gerado (tema=%r, %d caracteres)", post.id, tema, len(texto))
        return post

    def _publicar_em_um_canal(self, post: Post, publisher: Publisher) -> ResultadoPublicacao:
        try:
            identificador = publisher.publicar(post)
        except Exception as exc:
            resultado = ResultadoPublicacao.falha(post.id, publisher.canal, str(exc))
            logger.error("Falha ao publicar post %s em %s: %s", post.id, publisher.canal.value, exc)
            self._event_bus.publish(PublicacaoFalhou(resultado=resultado))
            return resultado

        resultado = ResultadoPublicacao.sucesso(post.id, publisher.canal, identificador)
        logger.info("Post %s publicado em %s (id externo=%s)", post.id, publisher.canal.value, identificador)
        self._event_bus.publish(PostPublicado(resultado=resultado))
        return resultado
