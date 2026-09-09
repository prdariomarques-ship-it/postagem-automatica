"""Logging estruturado — substitui os `print()` espalhados pela versão anterior,
que se perdiam sem timestamp, nível ou destino configurável assim que o processo
rodasse como daemon sem terminal interativo."""
from __future__ import annotations

import logging
import sys


def configurar_logging(nivel: str = "INFO") -> None:
    logging.basicConfig(
        level=getattr(logging, nivel.upper(), logging.INFO),
        format="%(asctime)s %(levelname)-8s %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        stream=sys.stdout,
    )
