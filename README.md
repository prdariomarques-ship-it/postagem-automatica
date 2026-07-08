# Postagem Automática de Conteúdo

Sistema que gera conteúdo com IA e publica automaticamente no Instagram, Facebook e WhatsApp.

## Como funciona

1. **Geração** — a IA (API do Claude) cria o texto do post a partir de temas configurados
2. **Agendamento** — um agendador dispara a publicação nos horários definidos
3. **Publicação** — o post é enviado via:
   - Instagram/Facebook: Graph API da Meta (exige conta business)
   - WhatsApp: Twilio WhatsApp API

## Configuração

1. Copie `.env.example` para `.env` e preencha as chaves
2. Instale as dependências: `pip install -r requirements.txt`
3. Rode: `python src/main.py`

## Requisitos externos

- **Meta (Instagram/Facebook):** conta business no Instagram vinculada a uma Página do Facebook + app criado em developers.facebook.com com permissões `instagram_content_publish` e `pages_manage_posts`
- **WhatsApp:** conta no Twilio com sender WhatsApp aprovado
- **Claude API:** chave em console.anthropic.com
