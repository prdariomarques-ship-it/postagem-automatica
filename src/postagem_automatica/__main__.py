"""CLI / daemon entrypoint.

Uso:
    python -m postagem_automatica                  # roda o agendador (loop infinito)
    POSTAR_AGORA=1 python -m postagem_automatica    # gera e publica uma vez, sai

Composition root do ponto de vista de execução: monta as dependências
concretas (Settings, EventBus, use case) e delega a orquestração para
ExecutarPostagemUseCase — nenhuma lógica de negócio mora aqui.
"""
from __future__ import annotations

import logging
import os
import random

from dotenv import load_dotenv

from .application.event_bus import EventBus
from .domain.events import GeracaoFalhou, PostPublicado, PublicacaoFalhou
from .domain.exceptions import ConfiguracaoInvalidaError
from .infrastructure.composition import montar_use_case
from .infrastructure.config import Settings
from .infrastructure.logging_config import configurar_logging
from .infrastructure.scheduler import Scheduler

logger = logging.getLogger(__name__)


def _registrar_logs_de_eventos(event_bus: EventBus) -> None:
    """Handler de logging desacoplado do caso de uso — outros handlers (ex:
    notificar o store_agent do ship-it quando uma publicação falha) podem ser
    adicionados aqui sem tocar em application/use_cases.py."""
    event_bus.subscribe(
        PostPublicado,
        lambda e: logger.info("✅ %s: %s", e.resultado.canal.value, e.resultado.identificador_externo),
    )
    event_bus.subscribe(
        PublicacaoFalhou,
        lambda e: logger.error("❌ %s: %s", e.resultado.canal.value, e.resultado.erro),
    )
    event_bus.subscribe(
        GeracaoFalhou,
        lambda e: logger.error("❌ geração de conteúdo falhou (tema=%s): %s", e.tema, e.erro),
    )


def main() -> None:
    load_dotenv()

    try:
        settings = Settings.from_env()
    except ConfiguracaoInvalidaError as exc:
        raise SystemExit(f"Configuração inválida: {exc}") from exc

    configurar_logging(settings.log_level)
    event_bus = EventBus()
    _registrar_logs_de_eventos(event_bus)
    use_case = montar_use_case(settings, event_bus=event_bus)

    def executar_postagem() -> None:
        tema = random.choice(settings.temas)
        logger.info("Gerando conteúdo para tema=%r", tema)
        try:
            use_case.executar(tema)
        except Exception:
            # Já logado e emitido via EventBus dentro do use case (GeracaoFalhou).
            # Este catch garante que uma falha de geração NUNCA derruba o
            # processo do agendador — era o bug mais sério da versão anterior,
            # em que `gerar_post()` ficava fora de qualquer try/except em main().
            logger.exception("Execução da postagem falhou por completo (tema=%r)", tema)

    if os.environ.get("POSTAR_AGORA") == "1":
        executar_postagem()
        return

    scheduler = Scheduler(horarios=settings.horarios_postagem, fuso=settings.timezone)
    scheduler.executar_para_sempre(executar_postagem)


if __name__ == "__main__":
    main()
