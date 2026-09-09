"""Exceções de domínio."""


class PostagemAutomaticaError(Exception):
    """Raiz das exceções do domínio."""


class GeracaoConteudoError(PostagemAutomaticaError):
    """Falha ao gerar o texto de um post via IA."""


class ConfiguracaoInvalidaError(PostagemAutomaticaError):
    """Configuração obrigatória ausente ou inválida — levantada na inicialização,
    nunca no meio de uma publicação agendada."""
