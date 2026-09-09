"""Shim de compatibilidade: mantém `python src/main.py` funcionando após a
migração para o pacote `postagem_automatica`. A lógica real está em
postagem_automatica/__main__.py — este arquivo existe só para não quebrar
scripts de deploy/systemd que já apontam para este caminho."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from postagem_automatica.__main__ import main  # noqa: E402

if __name__ == "__main__":
    main()
