"""Testes do Settings — a validação precisa falhar rápido e com mensagem clara,
em vez de um KeyError perdido no meio de uma publicação agendada."""
from __future__ import annotations

import pytest

from postagem_automatica.domain.exceptions import ConfiguracaoInvalidaError
from postagem_automatica.infrastructure.config import Settings

_ENV_MINIMO = {
    "ANTHROPIC_API_KEY": "sk-ant-teste",
    "META_ACCESS_TOKEN": "meta-token",
    "META_PAGE_ID": "pagina-1",
    "TWILIO_ACCOUNT_SID": "AC1",
    "TWILIO_AUTH_TOKEN": "tok",
    "TWILIO_WHATSAPP_FROM": "whatsapp:+140000",
    "WHATSAPP_DESTINOS": "whatsapp:+551190001,whatsapp:+551190002",
}


def test_carrega_configuracao_valida_com_defaults(monkeypatch):
    for chave, valor in _ENV_MINIMO.items():
        monkeypatch.setenv(chave, valor)
    monkeypatch.delenv("TZ_POSTAGEM", raising=False)

    settings = Settings.from_env()

    assert settings.timezone == "America/Sao_Paulo"
    assert settings.whatsapp_destinos == ("whatsapp:+551190001", "whatsapp:+551190002")
    assert settings.anthropic_model == "claude-opus-4-8"


def test_falha_com_mensagem_clara_quando_faltam_variaveis(monkeypatch):
    for chave in _ENV_MINIMO:
        monkeypatch.delenv(chave, raising=False)
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-teste")

    with pytest.raises(ConfiguracaoInvalidaError) as exc_info:
        Settings.from_env()

    mensagem = str(exc_info.value)
    assert "META_ACCESS_TOKEN" in mensagem
    assert "ANTHROPIC_API_KEY" not in mensagem
