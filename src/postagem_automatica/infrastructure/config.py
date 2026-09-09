"""Configuração da aplicação: parse e validação de variáveis de ambiente em um
único lugar.

Falha rápido e com mensagem clara na inicialização (`Settings.from_env()`),
em vez de um `KeyError` genérico levantado no meio de uma publicação agendada
— era assim que a versão anterior se comportava quando faltava alguma variável.
"""
from __future__ import annotations

import os
from dataclasses import dataclass

from ..domain.exceptions import ConfiguracaoInvalidaError

_OBRIGATORIAS = (
    "ANTHROPIC_API_KEY",
    "META_ACCESS_TOKEN",
    "META_PAGE_ID",
    "TWILIO_ACCOUNT_SID",
    "TWILIO_AUTH_TOKEN",
    "TWILIO_WHATSAPP_FROM",
    "WHATSAPP_DESTINOS",
)


@dataclass(frozen=True, slots=True)
class Settings:
    anthropic_api_key: str
    anthropic_model: str
    meta_access_token: str
    meta_page_id: str
    meta_ig_user_id: str | None
    twilio_account_sid: str
    twilio_auth_token: str
    twilio_whatsapp_from: str
    whatsapp_destinos: tuple[str, ...]
    temas: tuple[str, ...]
    horarios_postagem: tuple[str, ...]
    timezone: str
    db_path: str
    log_level: str

    @classmethod
    def from_env(cls) -> "Settings":
        faltando = [nome for nome in _OBRIGATORIAS if not os.environ.get(nome)]
        if faltando:
            raise ConfiguracaoInvalidaError(
                "Variáveis de ambiente obrigatórias ausentes: " + ", ".join(faltando)
            )

        return cls(
            anthropic_api_key=os.environ["ANTHROPIC_API_KEY"],
            anthropic_model=os.environ.get("ANTHROPIC_MODEL", "claude-opus-4-8"),
            meta_access_token=os.environ["META_ACCESS_TOKEN"],
            meta_page_id=os.environ["META_PAGE_ID"],
            meta_ig_user_id=os.environ.get("META_IG_USER_ID") or None,
            twilio_account_sid=os.environ["TWILIO_ACCOUNT_SID"],
            twilio_auth_token=os.environ["TWILIO_AUTH_TOKEN"],
            twilio_whatsapp_from=os.environ["TWILIO_WHATSAPP_FROM"],
            whatsapp_destinos=tuple(
                d.strip() for d in os.environ["WHATSAPP_DESTINOS"].split(",") if d.strip()
            ),
            temas=tuple(
                t.strip() for t in os.environ.get("TEMAS", "reflexão do dia").split(";") if t.strip()
            ),
            horarios_postagem=tuple(
                h.strip() for h in os.environ.get("HORARIOS_POSTAGEM", "08:00").split(",") if h.strip()
            ),
            timezone=os.environ.get("TZ_POSTAGEM", "America/Sao_Paulo"),
            db_path=os.environ.get("DB_PATH", "data/posts.db"),
            log_level=os.environ.get("LOG_LEVEL", "INFO"),
        )
