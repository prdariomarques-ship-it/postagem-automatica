"""Event Bus síncrono e em processo (Registry Pattern aplicado a handlers de evento)."""
from __future__ import annotations

import logging
from collections import defaultdict
from typing import Any, Callable, TypeVar

logger = logging.getLogger(__name__)

EventoT = TypeVar("EventoT")
Handler = Callable[[Any], None]


class EventBus:
    """Pub/sub simples por tipo de evento.

    Handlers rodam de forma síncrona, na ordem em que foram inscritos. Uma
    exceção em um handler é logada e isolada — nunca interrompe os demais
    handlers nem propaga para quem publicou o evento (o fluxo principal de
    postagem não pode falhar por causa de um efeito colateral de logging).
    """

    def __init__(self) -> None:
        self._handlers: dict[type, list[Handler]] = defaultdict(list)

    def subscribe(self, tipo_evento: type[EventoT], handler: Callable[[EventoT], None]) -> None:
        self._handlers[tipo_evento].append(handler)

    def publish(self, evento: Any) -> None:
        for handler in self._handlers.get(type(evento), []):
            try:
                handler(evento)
            except Exception:
                logger.exception("Handler %r falhou ao processar %r", handler, evento)
