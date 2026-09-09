"""Fixtures compartilhadas entre os testes."""
from __future__ import annotations

import pytest

from postagem_automatica.application.event_bus import EventBus
from postagem_automatica.infrastructure.persistence.sqlite_post_repository import SqlitePostRepository


@pytest.fixture
def event_bus() -> EventBus:
    return EventBus()


@pytest.fixture
def repositorio_memoria():
    repo = SqlitePostRepository(":memory:")
    yield repo
    repo.fechar()
