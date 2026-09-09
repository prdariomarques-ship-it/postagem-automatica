"""Testes do Scheduler timezone-aware — o bug que ele corrige (a lib `schedule`
usava o horário local do processo em vez do fuso configurado) era real na
versão anterior quando implantado num servidor em UTC."""
from __future__ import annotations

from datetime import datetime
from zoneinfo import ZoneInfo

from postagem_automatica.infrastructure.scheduler import Scheduler


def _sp(ano, mes, dia, hora, minuto):
    return datetime(ano, mes, dia, hora, minuto, tzinfo=ZoneInfo("America/Sao_Paulo"))


def test_dispara_uma_vez_quando_horario_passa():
    relogio = {"agora": _sp(2026, 9, 9, 8, 0)}
    scheduler = Scheduler(horarios=("08:00",), fuso="America/Sao_Paulo", agora_fn=lambda: relogio["agora"])
    chamadas = []

    disparou = scheduler.verificar_e_disparar(lambda: chamadas.append(1))

    assert disparou is True
    assert len(chamadas) == 1


def test_nao_dispara_duas_vezes_no_mesmo_dia():
    relogio = {"agora": _sp(2026, 9, 9, 8, 0)}
    scheduler = Scheduler(horarios=("08:00",), fuso="America/Sao_Paulo", agora_fn=lambda: relogio["agora"])
    chamadas = []

    scheduler.verificar_e_disparar(lambda: chamadas.append(1))
    relogio["agora"] = _sp(2026, 9, 9, 8, 5)
    scheduler.verificar_e_disparar(lambda: chamadas.append(1))

    assert len(chamadas) == 1


def test_dispara_novamente_no_dia_seguinte():
    relogio = {"agora": _sp(2026, 9, 9, 8, 0)}
    scheduler = Scheduler(horarios=("08:00",), fuso="America/Sao_Paulo", agora_fn=lambda: relogio["agora"])
    chamadas = []

    scheduler.verificar_e_disparar(lambda: chamadas.append(1))
    relogio["agora"] = _sp(2026, 9, 10, 8, 0)
    scheduler.verificar_e_disparar(lambda: chamadas.append(1))

    assert len(chamadas) == 2


def test_nao_dispara_antes_do_horario():
    relogio = {"agora": _sp(2026, 9, 9, 7, 59)}
    scheduler = Scheduler(horarios=("08:00",), fuso="America/Sao_Paulo", agora_fn=lambda: relogio["agora"])

    disparou = scheduler.verificar_e_disparar(lambda: None)

    assert disparou is False
