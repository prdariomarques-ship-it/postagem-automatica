"""Agendador timezone-aware.

Substitui a lib `schedule` (que agenda no horário LOCAL DO PROCESSO) por um
laço que compara o horário atual, já convertido para o fuso configurado
(`TZ_POSTAGEM`), contra os horários definidos em `HORARIOS_POSTAGEM`. Isso
fecha um bug real da versão anterior: se o servidor (ex: um VPS Oracle) roda
em UTC e o fuso pretendido é America/Sao_Paulo, `schedule` postava nos
horários errados.
"""
from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from typing import Callable
from zoneinfo import ZoneInfo

logger = logging.getLogger(__name__)


@dataclass
class Scheduler:
    """Verifica periodicamente se algum horário configurado já passou hoje (no
    fuso `fuso`) e ainda não disparou, executando `tarefa` nesse caso.

    `agora_fn` é injetável (Dependency Inversion) para testar o agendamento
    sem depender do relógio real do sistema nem de `time.sleep` de verdade.
    """

    horarios: tuple[str, ...]
    fuso: str
    intervalo_verificacao_segundos: int = 30
    agora_fn: Callable[[], datetime] | None = field(default=None, repr=False)

    def __post_init__(self) -> None:
        self._zona = ZoneInfo(self.fuso)
        self._horas_minutos = [self._parse_horario(h) for h in self.horarios]
        self._ultima_execucao: dict[tuple[int, int], date] = {}
        if self.agora_fn is None:
            self.agora_fn = lambda: datetime.now(self._zona)

    @staticmethod
    def _parse_horario(horario: str) -> tuple[int, int]:
        hora, minuto = horario.split(":")
        return int(hora), int(minuto)

    def executar_para_sempre(self, tarefa: Callable[[], None]) -> None:
        logger.info("Agendador ativo (fuso=%s, horários=%s)", self.fuso, ", ".join(self.horarios))
        while True:
            self.verificar_e_disparar(tarefa)
            time.sleep(self.intervalo_verificacao_segundos)

    def verificar_e_disparar(self, tarefa: Callable[[], None]) -> bool:
        """Executa `tarefa` uma vez para cada horário configurado que já passou
        hoje e ainda não rodou. Retorna True se disparou ao menos uma vez."""
        agora = self.agora_fn()
        disparou = False
        for alvo in self._horas_minutos:
            ja_rodou_hoje = self._ultima_execucao.get(alvo) == agora.date()
            ja_passou = (agora.hour, agora.minute) >= alvo
            if ja_passou and not ja_rodou_hoje:
                self._ultima_execucao[alvo] = agora.date()
                tarefa()
                disparou = True
        return disparou

    def proxima_execucao(self) -> datetime:
        agora = self.agora_fn()
        candidatos = []
        for hora, minuto in self._horas_minutos:
            candidato = agora.replace(hour=hora, minute=minuto, second=0, microsecond=0)
            if candidato <= agora:
                candidato += timedelta(days=1)
            candidatos.append(candidato)
        return min(candidatos)
