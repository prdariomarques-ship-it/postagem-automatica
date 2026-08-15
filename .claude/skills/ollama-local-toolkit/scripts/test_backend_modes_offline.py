#!/usr/bin/env python3
"""Testa os quatro backends de IA sem chamadas externas.

Cobre: auto (ambas chaves), auto (só OpenAI), auto (sem chaves),
deepseek explícito, openai explícito, ollama explícito, backend inválido,
OLLAMA_NO_CLOUD=1 com backend não-ollama, bloqueio de tag :cloud.

Total: 9 testes. Nenhuma chamada de rede. Nenhuma leitura de .env ativo.

Uso: python3 test_backend_modes_offline.py <caminho-do-repositório>
"""

from __future__ import annotations

import os
import sys
import unittest
from unittest.mock import MagicMock, patch


def _load_module(repo: str):
    path = os.path.join(repo, "work", "deepseek_ai.py")
    if not os.path.isfile(path):
        print(f"ERRO: {path} não encontrado.", file=sys.stderr)
        sys.exit(1)
    import importlib.util
    spec = importlib.util.spec_from_file_location("deepseek_ai", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _resp_cloud(content: str) -> MagicMock:
    """Resposta simulada para backends OpenAI-compat (DeepSeek/OpenAI)."""
    m = MagicMock()
    import json
    m.read.return_value = json.dumps(
        {"choices": [{"message": {"content": content}}]}
    ).encode()
    m.__enter__ = lambda s: s
    m.__exit__ = MagicMock(return_value=False)
    return m


def _resp_ollama(content: str) -> MagicMock:
    """Resposta simulada para backend Ollama."""
    m = MagicMock()
    import json
    m.read.return_value = json.dumps({"response": content}).encode()
    m.__enter__ = lambda s: s
    m.__exit__ = MagicMock(return_value=False)
    return m


class BackendModesTests(unittest.TestCase):
    mod = None

    @classmethod
    def setUpClass(cls):
        if cls.mod is None:
            raise unittest.SkipTest("módulo não carregado")

    # ── Modo auto ──────────────────────────────────────────────────────────

    def test_01_auto_ambas_chaves_seleciona_deepseek(self):
        """auto + ambas chaves → DeepSeek chamado."""
        captured: list[str] = []

        def fake_open(req, **_):
            captured.append(req.full_url)
            return _resp_cloud("ok-deepseek")

        env = {"AI_BACKEND": "auto", "DEEPSEEK_API_KEY": "ph-ds", "OPENAI_API_KEY": "ph-oa"}
        with patch.dict(os.environ, env):
            with patch("urllib.request.urlopen", side_effect=fake_open):
                result = self.mod.generate("p")
        self.assertEqual(result, "ok-deepseek")
        self.assertTrue(any("deepseek" in u for u in captured), captured)

    def test_02_auto_so_openai_seleciona_openai(self):
        """auto + só OPENAI_API_KEY → OpenAI chamado."""
        captured: list[str] = []

        def fake_open(req, **_):
            captured.append(req.full_url)
            return _resp_cloud("ok-openai")

        base = {k: v for k, v in os.environ.items()
                if k not in ("DEEPSEEK_API_KEY", "AI_BACKEND")}
        base.update({"AI_BACKEND": "auto", "OPENAI_API_KEY": "ph-oa"})
        with patch.dict(os.environ, base, clear=True):
            with patch("urllib.request.urlopen", side_effect=fake_open):
                result = self.mod.generate("p")
        self.assertEqual(result, "ok-openai")
        self.assertTrue(any("openai" in u for u in captured), captured)

    def test_03_auto_sem_chaves_falha_sem_rede(self):
        """auto sem chaves → RuntimeError; nenhuma chamada de rede."""
        base = {k: v for k, v in os.environ.items()
                if k not in ("DEEPSEEK_API_KEY", "OPENAI_API_KEY")}
        base["AI_BACKEND"] = "auto"
        with patch.dict(os.environ, base, clear=True):
            with patch("urllib.request.urlopen") as mock_open:
                with self.assertRaises(RuntimeError):
                    self.mod.generate("p")
                mock_open.assert_not_called()

    # ── Backends explícitos ────────────────────────────────────────────────

    def test_04_deepseek_explicito(self):
        """AI_BACKEND=deepseek → endpoint DeepSeek chamado."""
        captured: list[str] = []

        def fake_open(req, **_):
            captured.append(req.full_url)
            return _resp_cloud("ok")

        with patch.dict(os.environ, {"AI_BACKEND": "deepseek", "DEEPSEEK_API_KEY": "ph"}):
            with patch("urllib.request.urlopen", side_effect=fake_open):
                self.mod.generate("p")
        self.assertTrue(any("deepseek.com" in u for u in captured), captured)

    def test_05_openai_explicito(self):
        """AI_BACKEND=openai → endpoint OpenAI chamado."""
        captured: list[str] = []

        def fake_open(req, **_):
            captured.append(req.full_url)
            return _resp_cloud("ok")

        with patch.dict(os.environ, {"AI_BACKEND": "openai", "OPENAI_API_KEY": "ph"}):
            with patch("urllib.request.urlopen", side_effect=fake_open):
                self.mod.generate("p")
        self.assertTrue(any("openai.com" in u for u in captured), captured)

    def test_06_ollama_explicito(self):
        """AI_BACKEND=ollama → endpoint Ollama local chamado."""
        captured: list[str] = []

        def fake_open(req, **_):
            captured.append(req.full_url)
            return _resp_ollama("ok-local")

        with patch.dict(os.environ, {
            "AI_BACKEND": "ollama",
            "OLLAMA_HOST": "http://127.0.0.1:11434",
            "OLLAMA_MODEL": "qwen3:4b",
        }):
            with patch("urllib.request.urlopen", side_effect=fake_open):
                result = self.mod.generate("p")
        self.assertEqual(result, "ok-local")
        self.assertTrue(any("127.0.0.1:11434" in u for u in captured), captured)

    # ── Restrições de segurança ────────────────────────────────────────────

    def test_07_backend_invalido_levanta_valueerror(self):
        """AI_BACKEND desconhecido → ValueError imediato."""
        with patch.dict(os.environ, {"AI_BACKEND": "gemini"}):
            with self.assertRaises(ValueError) as ctx:
                self.mod.generate("p")
        self.assertIn("gemini", str(ctx.exception))

    def test_08_no_cloud_com_backend_nao_ollama_falha(self):
        """OLLAMA_NO_CLOUD=1 + AI_BACKEND≠ollama → RuntimeError."""
        with patch.dict(os.environ, {
            "AI_BACKEND": "deepseek",
            "OLLAMA_NO_CLOUD": "1",
            "DEEPSEEK_API_KEY": "ph",
        }):
            with patch("urllib.request.urlopen") as mock_open:
                with self.assertRaises(RuntimeError) as ctx:
                    self.mod.generate("p")
                mock_open.assert_not_called()
        self.assertIn("OLLAMA_NO_CLOUD", str(ctx.exception))

    def test_09_modelo_cloud_bloqueado_no_ollama(self):
        """OLLAMA_MODEL com :cloud → ValueError antes de qualquer chamada de rede."""
        with patch.dict(os.environ, {
            "AI_BACKEND": "ollama",
            "OLLAMA_MODEL": "glm-5.2:cloud",
        }):
            with patch("urllib.request.urlopen") as mock_open:
                with self.assertRaises(ValueError) as ctx:
                    self.mod.generate("p")
                mock_open.assert_not_called()
        self.assertIn("cloud", str(ctx.exception).lower())


# ── Ponto de entrada ───────────────────────────────────────────────────────

def main() -> int:
    if len(sys.argv) < 2:
        print("Uso: test_backend_modes_offline.py <caminho-do-repositório>", file=sys.stderr)
        return 1

    repo = os.path.abspath(sys.argv[1])
    mod = _load_module(repo)

    print("=" * 60)
    print("test_backend_modes_offline — 9 testes, zero chamadas externas")
    print(f"Repositório: {repo}")
    print("=" * 60)
    print()

    BackendModesTests.mod = mod
    suite = unittest.TestLoader().loadTestsFromTestCase(BackendModesTests)
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    print()
    print("=" * 60)
    if result.wasSuccessful():
        print("RESULTADO: OK — todos os 9 testes passaram.")
        print("Nota: seleção por chave disponível; sem failover runtime.")
        return 0
    else:
        print(f"RESULTADO: FALHA — {len(result.failures + result.errors)} teste(s) falharam.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
