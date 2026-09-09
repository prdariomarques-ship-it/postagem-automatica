"""Testes do SqlitePostRepository."""
from __future__ import annotations

from postagem_automatica.domain.entities import Canal, Post, ResultadoPublicacao


def test_salva_e_recupera_historico(repositorio_memoria):
    post = Post.novo(tema="tema-1", texto="texto-1")
    repositorio_memoria.salvar_post(post)

    historico = repositorio_memoria.historico()
    assert len(historico) == 1
    assert historico[0].id == post.id
    assert historico[0].texto == "texto-1"


def test_salva_resultado_de_publicacao(repositorio_memoria):
    post = Post.novo(tema="tema-1", texto="texto-1")
    repositorio_memoria.salvar_post(post)

    resultado = ResultadoPublicacao.sucesso(post.id, Canal.FACEBOOK, "fb-123")
    repositorio_memoria.salvar_resultado(resultado)
