# Postagem Automática de Conteúdo

Sistema que gera conteúdo com IA e publica automaticamente no Facebook e no
WhatsApp, em horários agendados.

## Como funciona

1. **Geração** — a IA (API do Claude) cria o texto do post a partir de temas configurados
2. **Agendamento** — um agendador timezone-aware dispara a publicação nos horários definidos
3. **Publicação** — o post é enviado via:
   - Facebook: Graph API da Meta (exige conta business)
   - WhatsApp: Twilio WhatsApp API

Instagram tem um adapter pronto (`infrastructure/publishers/instagram_publisher.py`)
mas **não está ligado ao fluxo hoje**: a API do Instagram exige uma imagem
hospedada em URL pública, e o pipeline atual só gera texto. Fica pronto para
religar assim que existir um passo de geração/hospedagem de imagem.

## Arquitetura

O código segue Clean Architecture (ports & adapters):

```
src/postagem_automatica/
├── domain/          entidades (Post, ResultadoPublicacao), eventos, exceções
│                    — não depende de nada externo
├── application/     caso de uso (ExecutarPostagemUseCase), ports (interfaces)
│                    e EventBus — depende só do domain
└── infrastructure/  adapters concretos:
    ├── generators/      AnthropicContentGenerator
    ├── publishers/      FacebookPublisher, WhatsAppPublisher, InstagramPublisher
    ├── persistence/      SqlitePostRepository (histórico de posts)
    ├── config.py         Settings — validação de env vars com falha rápida
    ├── retry.py          retry/backoff (tenacity) para chamadas externas
    ├── scheduler.py       agendador timezone-aware
    ├── registry.py        PublisherRegistry — quais canais estão ativos
    └── composition.py     composition root (monta tudo via injeção de dependência)
```

Novos canais de publicação se registram em `infrastructure/registry.py` sem
precisar tocar no caso de uso (Open/Closed). Handlers de evento (ex: notificar
outro sistema quando uma publicação falha) se inscrevem no `EventBus` sem
tocar na orquestração.

### Reaproveitando em outro projeto (ex: ship-it/store_agent)

```python
from postagem_automatica.infrastructure.composition import montar_use_case
from postagem_automatica.infrastructure.config import Settings

settings = Settings.from_env()
use_case = montar_use_case(settings)
resultados = use_case.executar(tema="reflexão do dia")
```

## Configuração

1. Copie `.env.example` para `.env` e preencha as chaves
2. Instale as dependências:
   - Runtime apenas: `pip install -r requirements.txt`
   - Desenvolvimento (com testes): `pip install -e ".[dev]"`
3. Rode:
   - `python -m postagem_automatica` (agendador, loop infinito)
   - `python src/main.py` (equivalente — mantido para compatibilidade com deploys existentes)
   - `POSTAR_AGORA=1 python -m postagem_automatica` (gera e publica uma vez, sai)

## Testes

```
pip install -e ".[dev]"
pytest
```

A suíte cobre o caso de uso (orquestração gerar→publicar→registrar, inclusive
falha parcial e falha de geração), o agendador timezone-aware, o parsing de
erro da Graph API, o comportamento de sucesso parcial do WhatsApp e a
validação de configuração — tudo com test doubles/mocks, sem chamar as APIs
externas de verdade.

## Requisitos externos

- **Meta (Facebook):** conta business no Facebook + app criado em developers.facebook.com com permissão `pages_manage_posts`
- **WhatsApp:** conta no Twilio com sender WhatsApp aprovado
- **Claude API:** chave em console.anthropic.com

## Histórico de posts

Cada post gerado e cada resultado de publicação (sucesso/falha, por canal) são
gravados em SQLite (`DB_PATH`, default `data/posts.db`) para auditoria — a
versão anterior não guardava nenhum histórico.
