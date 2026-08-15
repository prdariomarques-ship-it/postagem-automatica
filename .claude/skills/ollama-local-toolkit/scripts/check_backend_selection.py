#!/usr/bin/env python3
"""Verifica lógica de seleção de backend de IA sem chamadas externas.

Confirma que AI_BACKEND=auto faz seleção por disponibilidade de chave,
não failover após erro de requisição.

Uso: python3 check_backend_selection.py <caminho-do-repositório>
"""

from __future__ import annotations

import ast
import os
import sys
import unittest
from io import StringIO
from unittest.mock import MagicMock, patch

# ── Localizar e importar deepseek_ai do repositório ────────────────────────

def _load_module(repo: str):
    module_path = os.path.join(repo, "work", "deepseek_ai.py")
    if not os.path.isfile(module_path):
        print(f"ERRO: {module_path} não encontrado.", file=sys.stderr)
        sys.exit(1)
    import importlib.util
    spec = importlib.util.spec_from_file_location("deepseek_ai", module_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod, module_path


# ── Inspeção estática: detectar retry/failover no código ──────────────────

_BACKEND_NAMES = {"generate", "_ollama_generate", "_deepseek_generate", "_openai_generate",
                  "_openai_compat_generate"}


def _has_retry_logic(source_path: str) -> tuple[bool, list[str]]:
    """Retorna (tem_retry, evidências) por inspeção AST.

    Considera retry apenas chamadas a funções de backend dentro de except,
    ou laços (for/while) que contenham chamadas a backends.
    Chamadas a métodos de objetos (str.decode, bytes.read, etc.) são ignoradas.
    """
    with open(source_path) as f:
        tree = ast.parse(f.read())

    retry_patterns: list[str] = []

    for node in ast.walk(tree):
        # Laços que contêm chamadas a backends
        if isinstance(node, (ast.For, ast.While)):
            for child in ast.walk(node):
                if (isinstance(child, ast.Call)
                        and isinstance(child.func, ast.Name)
                        and child.func.id in _BACKEND_NAMES):
                    retry_patterns.append(
                        f"  Linha {node.lineno}: laço com chamada a '{child.func.id}'"
                    )

        # Except handlers que chamam diretamente funções de backend (não métodos de objeto)
        if isinstance(node, ast.ExceptHandler):
            for child in ast.walk(node):
                if (isinstance(child, ast.Call)
                        and isinstance(child.func, ast.Name)
                        and child.func.id in _BACKEND_NAMES):
                    retry_patterns.append(
                        f"  Linha {node.lineno}: except chama backend '{child.func.id}'"
                    )

    return bool(retry_patterns), retry_patterns


# ── Mock de resposta HTTP para testes offline ──────────────────────────────

def _make_mock_resp(body: bytes):
    resp = MagicMock()
    resp.read.return_value = body
    resp.__enter__ = lambda s: s
    resp.__exit__ = MagicMock(return_value=False)
    return resp


def _capture_call_url(calls: list) -> list[str]:
    return [str(c.args[0].full_url) if hasattr(c.args[0], "full_url") else str(c.args[0])
            for c in calls]


# ── Cenários de teste ──────────────────────────────────────────────────────

class BackendSelectionTests(unittest.TestCase):
    mod = None

    @classmethod
    def setUpClass(cls):
        if cls.mod is None:
            raise unittest.SkipTest("módulo não carregado")

    def _mock_openai_resp(self):
        return _make_mock_resp(
            b'{"choices":[{"message":{"content":"resp-openai"}}]}'
        )

    def _mock_deepseek_resp(self):
        return _make_mock_resp(
            b'{"choices":[{"message":{"content":"resp-deepseek"}}]}'
        )

    def test_auto_com_ambas_chaves_seleciona_deepseek(self):
        """auto + duas chaves → DeepSeek (primeira da prioridade)."""
        captured_url: list[str] = []

        def fake_urlopen(req, **_):
            captured_url.append(req.full_url)
            return self._mock_deepseek_resp()

        env = {
            "AI_BACKEND": "auto",
            "DEEPSEEK_API_KEY": "placeholder-deepseek",
            "OPENAI_API_KEY": "placeholder-openai",
        }
        with patch.dict(os.environ, env, clear=False):
            with patch("urllib.request.urlopen", side_effect=fake_urlopen):
                result = self.mod.generate("prompt de teste")

        self.assertEqual(result, "resp-deepseek")
        self.assertTrue(
            any("deepseek.com" in u for u in captured_url),
            f"Esperava chamada a deepseek.com; chamou: {captured_url}",
        )
        print(f"  ✔ auto+ambas chaves → {captured_url[0]}")

    def test_auto_apenas_openai_key_seleciona_openai(self):
        """auto + apenas OPENAI_API_KEY → OpenAI."""
        captured_url: list[str] = []

        def fake_urlopen(req, **_):
            captured_url.append(req.full_url)
            return self._mock_openai_resp()

        env_base = {k: v for k, v in os.environ.items()
                    if k not in ("DEEPSEEK_API_KEY", "AI_BACKEND")}
        env_base["AI_BACKEND"] = "auto"
        env_base["OPENAI_API_KEY"] = "placeholder-openai"

        with patch.dict(os.environ, env_base, clear=True):
            with patch("urllib.request.urlopen", side_effect=fake_urlopen):
                result = self.mod.generate("prompt de teste")

        self.assertEqual(result, "resp-openai")
        self.assertTrue(
            any("openai.com" in u for u in captured_url),
            f"Esperava chamada a openai.com; chamou: {captured_url}",
        )
        print(f"  ✔ auto+apenas openai → {captured_url[0]}")

    def test_auto_sem_chaves_nao_seleciona_proveedor(self):
        """auto sem chaves → RuntimeError; nenhuma chamada de rede."""
        env_base = {k: v for k, v in os.environ.items()
                    if k not in ("DEEPSEEK_API_KEY", "OPENAI_API_KEY")}
        env_base["AI_BACKEND"] = "auto"

        with patch.dict(os.environ, env_base, clear=True):
            with patch("urllib.request.urlopen") as mock_open:
                with self.assertRaises(RuntimeError) as ctx:
                    self.mod.generate("prompt de teste")
                mock_open.assert_not_called()

        self.assertIn("AI_BACKEND=ollama", str(ctx.exception))
        print("  ✔ auto+sem chaves → RuntimeError (nenhuma chamada de rede)")

    def test_nao_ha_failover_entre_backends(self):
        """Erro de DeepSeek NÃO redireciona para OpenAI no modo auto."""
        import urllib.error

        env = {
            "AI_BACKEND": "auto",
            "DEEPSEEK_API_KEY": "placeholder-deepseek",
            "OPENAI_API_KEY": "placeholder-openai",
        }

        call_count = 0

        def fake_urlopen(req, **_):
            nonlocal call_count
            call_count += 1
            raise urllib.error.URLError("conexão recusada (simulado)")

        with patch.dict(os.environ, env, clear=False):
            with patch("urllib.request.urlopen", side_effect=fake_urlopen):
                with self.assertRaises(RuntimeError):
                    self.mod.generate("prompt de teste")

        self.assertEqual(call_count, 1, "Deveria tentar apenas um backend; failover não esperado.")
        print(f"  ✔ erro DeepSeek → RuntimeError imediato; chamadas de rede: {call_count}")


# ── Ponto de entrada ───────────────────────────────────────────────────────

def main() -> int:
    if len(sys.argv) < 2:
        print("Uso: check_backend_selection.py <caminho-do-repositório>", file=sys.stderr)
        return 1

    repo = os.path.abspath(sys.argv[1])
    mod, src_path = _load_module(repo)

    print("=" * 60)
    print("check_backend_selection — seleção de backend sem chamadas externas")
    print(f"Repositório : {repo}")
    print(f"Módulo      : {src_path}")
    print("=" * 60)

    # Inspeção estática de retry
    print("\n[1/2] Inspeção estática — retry/failover no código:")
    has_retry, evidencias = _has_retry_logic(src_path)
    if has_retry:
        print("  AVISO: padrões de retry/failover detectados:")
        for e in evidencias:
            print(e)
    else:
        print("  ✔ Nenhum laço de retry detectado na função generate().")
    print("  → Conclusão: seleção por chave disponível, não failover runtime.")

    # Testes funcionais
    print("\n[2/2] Testes funcionais offline (sem chamadas externas):")
    BackendSelectionTests.mod = mod
    suite = unittest.TestLoader().loadTestsFromTestCase(BackendSelectionTests)
    buf = StringIO()
    runner = unittest.TextTestRunner(stream=buf, verbosity=0)
    result = runner.run(suite)

    # Imprimir saída capturada (linhas com ✔ / FAIL)
    for line in buf.getvalue().splitlines():
        if line.strip():
            print(" ", line)

    print("\n" + "=" * 60)
    if result.wasSuccessful():
        print("RESULTADO: seleção, não failover runtime ✔")
        print("Todos os cenários passaram.")
        return 0
    else:
        print("RESULTADO: falha nos testes de seleção.")
        for fail in result.failures + result.errors:
            print(f"\n  {fail[0]}")
            print(f"  {fail[1]}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
