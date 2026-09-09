"""Política de retry/backoff para chamadas a APIs externas (Anthropic, Meta, Twilio).

Falhas transitórias (timeout, erro de conexão, 429, 5xx) merecem nova tentativa;
erros de configuração/permissão (401/403, payload inválido, 4xx em geral) não —
tentar de novo só atrasa a falha e mascara a causa real. Por isso os predicados
abaixo inspecionam o tipo/status de cada exceção em vez de tentar tudo às cegas.
"""
from __future__ import annotations

import anthropic
import requests
from tenacity import (
    retry,
    retry_if_exception,
    retry_if_exception_type,
    stop_after_attempt,
    wait_exponential_jitter,
)
from twilio.base.exceptions import TwilioRestException

_EXCECOES_REDE = (
    requests.exceptions.ConnectionError,
    requests.exceptions.Timeout,
)

_EXCECOES_ANTHROPIC_TRANSITORIAS = (
    anthropic.APIConnectionError,
    anthropic.RateLimitError,
    anthropic.InternalServerError,
)


def _http_status_e_transitorio(exc: BaseException) -> bool:
    if isinstance(exc, requests.exceptions.HTTPError) and exc.response is not None:
        status = exc.response.status_code
        return status == 429 or status >= 500
    return isinstance(exc, _EXCECOES_REDE)


def _twilio_erro_e_transitorio(exc: BaseException) -> bool:
    if isinstance(exc, TwilioRestException):
        return exc.status is None or exc.status == 429 or exc.status >= 500
    return isinstance(exc, _EXCECOES_REDE)


retry_anthropic = retry(
    retry=retry_if_exception_type(_EXCECOES_ANTHROPIC_TRANSITORIAS),
    stop=stop_after_attempt(3),
    wait=wait_exponential_jitter(initial=1, max=15),
    reraise=True,
)

retry_http_meta = retry(
    retry=retry_if_exception(_http_status_e_transitorio),
    stop=stop_after_attempt(3),
    wait=wait_exponential_jitter(initial=1, max=15),
    reraise=True,
)

retry_twilio = retry(
    retry=retry_if_exception(_twilio_erro_e_transitorio),
    stop=stop_after_attempt(3),
    wait=wait_exponential_jitter(initial=1, max=15),
    reraise=True,
)
