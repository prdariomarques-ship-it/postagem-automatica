"""Testes isolados do backend local do gerador.

Não fazem chamadas externas, não baixam modelos e não exigem Ollama rodando.
Execute com: python -m pytest tests/test_gerador_local.py -v
        ou: python tests/test_gerador_local.py
"""
import importlib
import os
import sys
import unittest
from unittest.mock import MagicMock, patch

# Garante que src/ está no path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import gerador


class TestCloudModelRejeicao(unittest.TestCase):
    """Modelos com sufixo cloud devem ser rejeitados."""

    def test_rejeita_sufixo_cloud(self):
        with self.assertRaises(ValueError) as ctx:
            gerador._assert_not_cloud("glm-5.2:cloud")
        self.assertIn("cloud", str(ctx.exception).lower())

    def test_rejeita_traco_cloud(self):
        with self.assertRaises(ValueError):
            gerador._assert_not_cloud("algum-modelo-cloud")

    def test_rejeita_cloud_em_maiusculo(self):
        with self.assertRaises(ValueError):
            gerador._assert_not_cloud("MODELO:CLOUD")

    def test_aceita_modelo_local_normal(self):
        # Não deve lançar exceção
        gerador._assert_not_cloud("qwen3:4b")
        gerador._assert_not_cloud("qwen2.5-coder:7b")
        gerador._assert_not_cloud("deepseek-coder:6.7b")
        gerador._assert_not_cloud("gemma3:4b")

    def test_is_cloud_model_positivo(self):
        self.assertTrue(gerador._is_cloud_model("glm-5.2:cloud"))
        self.assertTrue(gerador._is_cloud_model("modelo-cloud"))

    def test_is_cloud_model_negativo(self):
        self.assertFalse(gerador._is_cloud_model("qwen3:4b"))
        self.assertFalse(gerador._is_cloud_model("qwen2.5-coder:7b"))


class TestHostLocal(unittest.TestCase):
    """OLLAMA_HOST deve ser local por padrão e rejeitar api.ollama.com."""

    def test_host_padrao_localhost(self):
        env = os.environ.copy()
        env.pop("OLLAMA_HOST", None)
        with patch.dict(os.environ, env, clear=True):
            host = gerador._ollama_host()
        self.assertIn("localhost", host)

    def test_host_personalizado_aceito(self):
        with patch.dict(os.environ, {"OLLAMA_HOST": "http://192.168.1.100:11434"}):
            host = gerador._ollama_host()
        self.assertEqual(host, "http://192.168.1.100:11434")

    def test_rejeita_api_ollama_com(self):
        with patch.dict(os.environ, {"OLLAMA_HOST": "https://api.ollama.com"}):
            with self.assertRaises(ValueError) as ctx:
                gerador._ollama_host()
        self.assertIn("api.ollama.com", str(ctx.exception))


class TestOllamaOffline(unittest.TestCase):
    """Mensagem clara quando o servidor Ollama não responde."""

    def test_erro_conexao_recusada(self):
        with patch.dict(os.environ, {
            "AI_BACKEND": "ollama",
            "OLLAMA_HOST": "http://localhost:11434",
            "OLLAMA_MODEL": "qwen3:4b",
        }):
            import urllib.error
            with patch("urllib.request.urlopen", side_effect=urllib.error.URLError("Connection refused")):
                with self.assertRaises(RuntimeError) as ctx:
                    gerador._gerar_com_ollama("tema qualquer")
            msg = str(ctx.exception)
            self.assertIn("ollama serve", msg.lower())

    def test_modelo_cloud_bloqueado_no_ollama(self):
        with patch.dict(os.environ, {
            "AI_BACKEND": "ollama",
            "OLLAMA_MODEL": "glm-5.2:cloud",
        }):
            with self.assertRaises(ValueError) as ctx:
                gerador._gerar_com_ollama("tema qualquer")
            self.assertIn("cloud", str(ctx.exception).lower())


class TestNoCloudFlag(unittest.TestCase):
    """OLLAMA_NO_CLOUD=1 com backend cloud deve falhar explicitamente."""

    def test_no_cloud_com_backend_claude_falha(self):
        with patch.dict(os.environ, {
            "AI_BACKEND": "claude",
            "OLLAMA_NO_CLOUD": "1",
            "TEMAS": "teste",
        }):
            with self.assertRaises(RuntimeError) as ctx:
                gerador.gerar_post()
            self.assertIn("OLLAMA_NO_CLOUD", str(ctx.exception))

    def test_no_cloud_com_backend_ollama_passa_validacao(self):
        mock_response = MagicMock()
        mock_response.read.return_value = b'{"response": "texto gerado"}'
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)

        with patch.dict(os.environ, {
            "AI_BACKEND": "ollama",
            "OLLAMA_NO_CLOUD": "1",
            "OLLAMA_MODEL": "qwen3:4b",
            "TEMAS": "teste",
        }):
            with patch("urllib.request.urlopen", return_value=mock_response):
                result = gerador.gerar_post()
        self.assertEqual(result, "texto gerado")


if __name__ == "__main__":
    unittest.main(verbosity=2)
