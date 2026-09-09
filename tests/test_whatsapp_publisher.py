"""Testes do WhatsAppPublisher — cobre o caso de sucesso parcial (alguns
destinos recebem a mensagem, outros falham) que a versão anterior perdia
silenciosamente ao deixar a exceção do primeiro destino abortar o restante."""
from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from postagem_automatica.domain.entities import Post
from postagem_automatica.infrastructure.publishers.whatsapp_publisher import WhatsAppPublisher


def _post() -> Post:
    return Post.novo(tema="teste", texto="mensagem de teste")


@patch("postagem_automatica.infrastructure.publishers.whatsapp_publisher.Client")
def test_envia_para_todos_os_destinos(mock_client_cls):
    mock_client = MagicMock()
    mock_client.messages.create.side_effect = [MagicMock(sid="SID1"), MagicMock(sid="SID2")]
    mock_client_cls.return_value = mock_client

    publisher = WhatsAppPublisher(
        account_sid="AC1",
        auth_token="tok",
        remetente="whatsapp:+140000",
        destinos=("whatsapp:+551190001", "whatsapp:+551190002"),
    )

    resultado = publisher.publicar(_post())
    assert resultado == "SID1,SID2"
    assert mock_client.messages.create.call_count == 2


@patch("postagem_automatica.infrastructure.publishers.whatsapp_publisher.Client")
def test_falha_parcial_reporta_sucessos_e_falhas(mock_client_cls):
    mock_client = MagicMock()
    mock_client.messages.create.side_effect = [MagicMock(sid="SID1"), RuntimeError("número inválido")]
    mock_client_cls.return_value = mock_client

    publisher = WhatsAppPublisher(
        account_sid="AC1",
        auth_token="tok",
        remetente="whatsapp:+140000",
        destinos=("whatsapp:+551190001", "whatsapp:+551190002"),
    )

    resultado = publisher.publicar(_post())
    assert "1/2 enviados" in resultado
    assert "número inválido" in resultado


@patch("postagem_automatica.infrastructure.publishers.whatsapp_publisher.Client")
def test_falha_total_levanta_excecao(mock_client_cls):
    mock_client = MagicMock()
    mock_client.messages.create.side_effect = RuntimeError("conta suspensa")
    mock_client_cls.return_value = mock_client

    publisher = WhatsAppPublisher(
        account_sid="AC1",
        auth_token="tok",
        remetente="whatsapp:+140000",
        destinos=("whatsapp:+551190001",),
    )

    with pytest.raises(RuntimeError, match="conta suspensa"):
        publisher.publicar(_post())
