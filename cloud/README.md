# Ollama Cloud — Guia de uso consciente

Este documento explica a diferença entre modelos **locais** e **cloud** no Ollama,  
e como usar a nuvem apenas de forma deliberada, sem surpresas de custo ou privacidade.

---

## Local vs. Cloud — diferença fundamental

| Aspecto | Local | Cloud |
|---------|-------|-------|
| Onde roda | No seu computador | Nos servidores da Ollama |
| Dados enviados | Nenhum | Seu prompt vai para a nuvem |
| Custo | Zero (depois de baixar) | Depende do plano/créditos |
| Velocidade | Depende do hardware | Geralmente mais rápido |
| Privacidade | Total | Sujeita à política da Ollama |
| Identificação | `qwen3:4b`, `gemma3:4b`… | `glm-5.2:cloud`, `modelo:cloud`… |

**Regra simples:** se o nome do modelo termina em `:cloud` ou contém `-cloud`, ele executa na nuvem.

---

## Como identificar se o app está usando cloud

O erro abaixo indica que o aplicativo tentou um modelo cloud sem autenticação ou plano ativo:

```
403 Forbidden: this model requires a subscription, upgrade for access
```

**Causas comuns:**
1. O modelo padrão do app foi definido como um modelo cloud (ex: `glm-5.2:cloud`)
2. O Ollama foi instalado com uma conta cloud logada que seleciona modelos remotos automaticamente
3. Um arquivo de configuração local aponta para a API remota em vez de `localhost:11434`

**Solução imediata:**
```bash
# Verifique qual host o Ollama está usando
echo $OLLAMA_HOST        # deve estar vazio ou ser http://localhost:11434

# Liste seus modelos locais e escolha um sem :cloud
ollama list

# Teste se o modelo local responde
ollama run qwen3:4b "Responda somente: teste local confirmado."
```

---

## Antes de usar o Ollama Cloud

Faça estas verificações na ordem:

1. **Consulte seu plano:** https://ollama.com/settings/billing  
   Saiba quantos créditos você tem e o custo por token.

2. **Entenda a política de privacidade:** https://ollama.com/privacy  
   Seus prompts são enviados para os servidores da Ollama.

3. **Faça login de forma explícita:**
   ```bash
   ollama login
   # ou via script:
   ./scripts/local-ai.sh cloud-login    # macOS/Linux
   .\scripts\local-ai.ps1 cloud-login   # Windows
   ```

4. **Execute com confirmação:**
   ```bash
   # O script pede confirmação antes de enviar qualquer prompt
   ./scripts/local-ai.sh cloud-run glm-5.2:cloud "Seu prompt aqui"
   ```

---

## Comandos cloud no script local-ai

| Comando | O que faz |
|---------|-----------|
| `cloud-check` | Lista modelos locais e lembra sobre custos cloud |
| `cloud-login` | Faz login na conta Ollama (pede confirmação) |
| `cloud-run <modelo> [prompt]` | Envia um prompt para um modelo cloud (pede confirmação) |

---

## Nenhuma chave de API é armazenada neste repositório

- O script **não salva** credenciais em arquivos.
- O login é gerenciado pelo próprio Ollama CLI (armazenado no keychain do sistema).
- Este repositório **nunca** deve conter tokens, senhas ou chaves em texto claro.
- Verifique o `.gitignore` antes de commitar: arquivos `.env` estão excluídos.

---

## Logout do Ollama Cloud

Para desconectar sua conta do terminal atual:

```bash
ollama logout
```

Depois disso, qualquer tentativa de usar um modelo `:cloud` retornará erro 403,  
garantindo que apenas modelos locais sejam usados até um próximo login explícito.

---

## Padrão deste projeto: sempre local

O projeto **postagem-automatica** usa a variável `AI_BACKEND` no `.env` para escolher o backend.  
O padrão é `claude` (API Anthropic), mas pode ser trocado para `ollama` para uso local:

```env
AI_BACKEND=ollama
OLLAMA_MODEL=qwen3:4b
OLLAMA_HOST=http://localhost:11434
```

Com `AI_BACKEND=ollama`, **nenhum dado é enviado para servidores externos** — nem para a Anthropic, nem para a Ollama Cloud.
