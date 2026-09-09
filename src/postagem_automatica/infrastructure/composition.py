"""Composition root: único lugar onde as implementações concretas são
instanciadas e conectadas às ports que a camada de aplicação espera
(Dependency Injection manual — sem framework, mesmo princípio usado no
restante do Dario OS)."""
from __future__ import annotations

from ..application.event_bus import EventBus
from ..application.use_cases import ExecutarPostagemUseCase
from .config import Settings
from .generators.anthropic_generator import AnthropicContentGenerator
from .persistence.sqlite_post_repository import SqlitePostRepository
from .registry import PublisherRegistry


def montar_use_case(settings: Settings, event_bus: EventBus | None = None) -> ExecutarPostagemUseCase:
    gerador = AnthropicContentGenerator(api_key=settings.anthropic_api_key, model=settings.anthropic_model)
    repositorio = SqlitePostRepository(db_path=settings.db_path)
    registry = PublisherRegistry.padrao(settings)

    return ExecutarPostagemUseCase(
        gerador=gerador,
        publishers=registry.todos(),
        repositorio=repositorio,
        event_bus=event_bus or EventBus(),
    )
