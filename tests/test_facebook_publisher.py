"""Testes do FacebookPublisher — cobre o bug corrigido de erro da Graph API
sendo engolido por raise_for_status() sem expor o corpo JSON do erro."""
from __future__ import annotations

from unittest.mock import Mock, patch

import pytest
import requests

from postagem_automatica.domain.entities import Post
from postagem_automatica.infrastructure.publishers.facebook_publisher import FacebookPublisher


def _post() -> Post:
    return Post.novo(tema="teste", texto="conteúdo do post")


@patch("postagem_automatica.infrastructure.publishers.facebook_publisher.requests.post")
def test_publicar_retorna_id_do_post(mock_post):
    resposta = Mock(ok=True, status_code=200)
    resposta.json.return_value = {"id": "1234_5678"}
    mock_post.return_value = resposta

    publisher = FacebookPublisher(page_id="pagina-1", access_token="token-abc")
    assert publisher.publicar(_post()) == "1234_5678"


@patch("postagem_automatica.infrastructure.publishers.facebook_publisher.requests.post")
def test_erro_da_graph_api_expoe_mensagem_e_code(mock_post):
    resposta = Mock(ok=False, status_code=400, text="raw body")
    resposta.json.return_value = {
        "error": {"message": "Token de acesso expirado", "code": 190, "error_subcode": 463}
    }
    mock_post.return_value = resposta

    publisher = FacebookPublisher(page_id="pagina-1", access_token="token-vencido")

    with pytest.raises(requests.exceptions.HTTPError) as exc_info:
        publisher.publicar(_post())

    mensagem = str(exc_info.value)
    assert "Token de acesso expirado" in mensagem
    assert "code=190" in mensagem


@patch("postagem_automatica.infrastructure.publishers.facebook_publisher.requests.post")
def test_erro_5xx_e_tentado_novamente(mock_post):
    resposta_erro = Mock(ok=False, status_code=503, text="")
    resposta_erro.json.return_value = {"error": {"message": "temporariamente indisponível"}}
    resposta_ok = Mock(ok=True, status_code=200)
    resposta_ok.json.return_value = {"id": "999"}
    mock_post.side_effect = [resposta_erro, resposta_ok]

    publisher = FacebookPublisher(page_id="pagina-1", access_token="token-abc")
    assert publisher.publicar(_post()) == "999"
    assert mock_post.call_count == 2
