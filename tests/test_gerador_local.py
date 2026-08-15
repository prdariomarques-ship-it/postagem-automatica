"""Testes isolados do backend local (work/deepseek_ai.py + src/gerador.py).

Não fazem chamadas externas, não baixam modelos e não exigem Ollama rodando.
Execute com: python tests/test_gerador_local.py
        ou: python -m pytest tests/test_gerador_local.py -v
"""
import os
import sys
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "work"))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import deepseek_ai


class TestCloudModelRejeicao(unittest.TestCase):
    def test_rejeita_sufixo_cloud(self):
        with self.assertRaises(ValueError) as ctx:
            deepseek_ai._reject_cloud_model("glm-5.2:cloud")
        self.assertIn("cloud", str(ctx.exception).lower())

    def test_rejeita_traco_cloud(self):
        with self.assertRaises(ValueError):
            deepseek_ai._reject_cloud_model("algum-modelo-cloud")

    def test_rejeita_cloud_em_maiusculo(self):
        with self.assertRaises(ValueError):
            deepseek_ai._reject_cloud_model("MODELO:CLOUD")

    def test_aceita_modelos_locais(self):
        for m in ("qwen3:4b", "qwen2.5-coder:7b", "deepseek-coder:6.7b", "gemma3:4b"):
            deepseek_ai._reject_cloud_model(m)  # não deve lançar

    def test_is_cloud_model(self):
        self.assertTrue(deepseek_ai._is_cloud_model("glm-5.2:cloud"))
        self.assertTrue(deepseek_ai._is_cloud_model("modelo-cloud"))
        self.assertFalse(deepseek_ai._is_cloud_model("qwen3:4b"))
        self.assertFalse(deepseek_ai._is_cloud_model("qwen2.5-coder:7b"))


class TestHostLocal(unittest.TestCase):
    def test_host_padrao_localhost(self):
        env = {k: v for k, v in os.environ.items() if k != "OLLAMA_HOST"}
        with patch.dict(os.environ, env, clear=True):
            # sem lançar exceção
            host = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
        self.assertIn("localhost", host)

    def test_rejeita_api_ollama_com(self):
        with patch.dict(os.environ, {
            "OLLAMA_HOST": "https://api.ollama.com",
            "OLLAMA_MODEL": "qwen3:4b",
        }):
            with self.assertRaises(ValueError) as ctx:
                deepseek_ai._ollama_generate("teste")
        self.assertIn("api.ollama.com", str(ctx.exception))


class TestOllamaOffline(unittest.TestCase):
    def test_erro_conexao_refusada(self):
        import urllib.error
        with patch.dict(os.environ, {
            "OLLAMA_HOST": "http://localhost:11434",
            "OLLAMA_MODEL": "qwen3:4b",
        }):
            with patch("urllib.request.urlopen",
                       side_effect=urllib.error.URLError("Connection refused")):
                with self.assertRaises(RuntimeError) as ctx:
                    deepseek_ai._ollama_generate("teste")
        self.assertIn("ollama serve", str(ctx.exception).lower())

    def test_modelo_cloud_bloqueado(self):
        with patch.dict(os.environ, {"OLLAMA_MODEL": "glm-5.2:cloud"}):
            with self.assertRaises(ValueError):
                deepseek_ai._ollama_generate("teste")


class TestNoCloudFlag(unittest.TestCase):
    def test_no_cloud_com_backend_deepseek_falha(self):
        with patch.dict(os.environ, {
            "AI_BACKEND": "deepseek",
            "OLLAMA_NO_CLOUD": "1",
            "TEMAS": "teste",
        }):
            with self.assertRaises(RuntimeError) as ctx:
                deepseek_ai.generate("prompt")
        self.assertIn("OLLAMA_NO_CLOUD", str(ctx.exception))

    def test_no_cloud_com_ollama_passa(self):
        mock_resp = MagicMock()
        mock_resp.read.return_value = b'{"response": "texto gerado"}'
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)

        with patch.dict(os.environ, {
            "AI_BACKEND": "ollama",
            "OLLAMA_NO_CLOUD": "1",
            "OLLAMA_MODEL": "qwen3:4b",
        }):
            with patch("urllib.request.urlopen", return_value=mock_resp):
                result = deepseek_ai.generate("prompt")
        self.assertEqual(result, "texto gerado")


class TestBackendAuto(unittest.TestCase):
    def test_auto_sem_chaves_falha(self):
        env = {k: v for k, v in os.environ.items()
               if k not in ("DEEPSEEK_API_KEY", "OPENAI_API_KEY")}
        env["AI_BACKEND"] = "auto"
        with patch.dict(os.environ, env, clear=True):
            with self.assertRaises(RuntimeError) as ctx:
                deepseek_ai.generate("prompt")
        self.assertIn("AI_BACKEND=ollama", str(ctx.exception))

    def test_backend_invalido_falha(self):
        with patch.dict(os.environ, {"AI_BACKEND": "gemini"}):
            with self.assertRaises(ValueError) as ctx:
                deepseek_ai.generate("prompt")
        self.assertIn("gemini", str(ctx.exception))


if __name__ == "__main__":
    unittest.main(verbosity=2)
