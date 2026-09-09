"""postagem_automatica — geração de conteúdo com IA (Claude) e publicação
automática em Facebook e WhatsApp.

Reaproveitável por outros sistemas (ex: o store_agent do ship-it):

    from postagem_automatica.infrastructure.composition import montar_use_case
    from postagem_automatica.infrastructure.config import Settings

    settings = Settings.from_env()
    use_case = montar_use_case(settings)
    resultados = use_case.executar(tema="reflexão do dia")

Arquitetura (ports & adapters / Clean Architecture):
    domain/          — entidades, eventos e exceções. Não depende de nada externo.
    application/     — casos de uso e ports (interfaces). Depende só do domain.
    infrastructure/  — adapters concretos (Anthropic, Graph API, Twilio, SQLite,
                       agendador) + composition root que os conecta às ports.
"""

__version__ = "2.0.0"
