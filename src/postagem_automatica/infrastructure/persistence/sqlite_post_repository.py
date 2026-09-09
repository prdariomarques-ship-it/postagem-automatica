"""Implementação SQLite do PostRepository (application/ports.py).

Histórico de posts gerados e resultados de publicação — a versão anterior não
guardava nada disso, o que tornava qualquer falha silenciosa e impossível de
auditar depois. Serve também de base para dedup/analytics quando isso for
integrado ao store_agent do ship-it.
"""
from __future__ import annotations

import sqlite3
from datetime import datetime
from pathlib import Path

from ...domain.entities import Post, ResultadoPublicacao

_SCHEMA = """
CREATE TABLE IF NOT EXISTS posts (
    id TEXT PRIMARY KEY,
    tema TEXT NOT NULL,
    texto TEXT NOT NULL,
    criado_em TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS resultados_publicacao (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    post_id TEXT NOT NULL REFERENCES posts(id),
    canal TEXT NOT NULL,
    status TEXT NOT NULL,
    identificador_externo TEXT,
    erro TEXT,
    publicado_em TEXT NOT NULL
);
"""


class SqlitePostRepository:
    """Mantém uma única conexão para o tempo de vida do objeto — necessário para
    que `db_path=":memory:"` funcione em testes (cada `sqlite3.connect(":memory:")`
    novo cria um banco isolado e vazio) e evita reabrir o arquivo a cada chamada
    em produção."""

    def __init__(self, db_path: str) -> None:
        if db_path != ":memory:":
            Path(db_path).parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(db_path)
        self._conn.row_factory = sqlite3.Row
        self._conn.executescript(_SCHEMA)
        self._conn.commit()

    def salvar_post(self, post: Post) -> None:
        self._conn.execute(
            "INSERT INTO posts (id, tema, texto, criado_em) VALUES (?, ?, ?, ?)",
            (post.id, post.tema, post.texto, post.criado_em.isoformat()),
        )
        self._conn.commit()

    def salvar_resultado(self, resultado: ResultadoPublicacao) -> None:
        self._conn.execute(
            """INSERT INTO resultados_publicacao
               (post_id, canal, status, identificador_externo, erro, publicado_em)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (
                resultado.post_id,
                resultado.canal.value,
                resultado.status.value,
                resultado.identificador_externo,
                resultado.erro,
                resultado.publicado_em.isoformat(),
            ),
        )
        self._conn.commit()

    def historico(self, limite: int = 50) -> list[Post]:
        linhas = self._conn.execute(
            "SELECT id, tema, texto, criado_em FROM posts ORDER BY criado_em DESC LIMIT ?",
            (limite,),
        ).fetchall()
        return [
            Post(id=linha["id"], tema=linha["tema"], texto=linha["texto"], criado_em=datetime.fromisoformat(linha["criado_em"]))
            for linha in linhas
        ]

    def fechar(self) -> None:
        self._conn.close()
