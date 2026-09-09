"""Testes do caso de uso principal — a peça mais importante para revisar, porque
é aqui que a orquestração (gerar -> publicar em N canais -> registrar) mora."""
from __future__ import annotations

import pytest
from doubles import GeradorFalso, PublisherFalso

from postagem_automatica.application.use_cases import ExecutarPostagemUseCase
from postagem_automatica.domain.entities import Canal, StatusPublicacao
from postagem_automatica.domain.events import GeracaoFalhou, PostPublicado, PublicacaoFalhou
from postagem_automatica.domain.exceptions import GeracaoConteudoError


def test_publica_com_sucesso_em_todos_os_canais(event_bus, repositorio_memoria):
    gerador = GeradorFalso(texto="Deus é bom.")
    facebook = PublisherFalso(Canal.FACEBOOK, identificador="fb-123")
    whatsapp = PublisherFalso(Canal.WHATSAPP, identificador="wa-456")
    eventos_publicados = []
    event_bus.subscribe(PostPublicado, eventos_publicados.append)

    use_case = ExecutarPostagemUseCase(gerador, [facebook, whatsapp], repositorio_memoria, event_bus)
    resultados = use_case.executar("reflexão do dia")

    assert len(resultados) == 2
    assert all(r.status == StatusPublicacao.SUCESSO for r in resultados)
    assert facebook.posts_recebidos[0].texto == "Deus é bom."
    assert whatsapp.posts_recebidos[0].texto == "Deus é bom."
    assert len(eventos_publicados) == 2
    assert len(repositorio_memoria.historico()) == 1


def test_falha_de_geracao_nao_chama_publishers_e_nao_persiste_post(event_bus, repositorio_memoria):
    gerador = GeradorFalso(excecao=RuntimeError("rate limit"))
    facebook = PublisherFalso(Canal.FACEBOOK)
    eventos_falha = []
    event_bus.subscribe(GeracaoFalhou, eventos_falha.append)

    use_case = ExecutarPostagemUseCase(gerador, [facebook], repositorio_memoria, event_bus)

    with pytest.raises(GeracaoConteudoError):
        use_case.executar("tema qualquer")

    assert facebook.posts_recebidos == []
    assert repositorio_memoria.historico() == []
    assert len(eventos_falha) == 1


def test_falha_em_um_canal_nao_impede_publicacao_nos_demais(event_bus, repositorio_memoria):
    gerador = GeradorFalso(texto="post")
    facebook_com_falha = PublisherFalso(Canal.FACEBOOK, excecao=RuntimeError("token expirado"))
    whatsapp_ok = PublisherFalso(Canal.WHATSAPP, identificador="wa-789")
    eventos_falha = []
    event_bus.subscribe(PublicacaoFalhou, eventos_falha.append)

    use_case = ExecutarPostagemUseCase(gerador, [facebook_com_falha, whatsapp_ok], repositorio_memoria, event_bus)
    resultados = use_case.executar("tema")

    por_canal = {r.canal: r for r in resultados}
    assert por_canal[Canal.FACEBOOK].status == StatusPublicacao.FALHA
    assert "token expirado" in por_canal[Canal.FACEBOOK].erro
    assert por_canal[Canal.WHATSAPP].status == StatusPublicacao.SUCESSO
    assert len(eventos_falha) == 1
