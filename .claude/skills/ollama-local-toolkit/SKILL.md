---
name: ollama-local-toolkit
description: >
  Configuração e diagnóstico do Ollama local neste projeto: troca de backend (Claude ↔ Ollama),
  seleção de modelo para programação ou chat, validação de GPU/VRAM, investigação do erro
  403 causado por modelos cloud, e monitoramento de desempenho. Use sempre que o usuário
  relatar lentidão, erro 403/subscription, ou quiser mudar o backend de IA do projeto.
triggers:
  - ollama
  - backend local
  - erro 403
  - subscription
  - modelo cloud
  - GPU
  - VRAM
  - local-ai
  - qwen
  - deepseek
  - gemma
---

# Ollama Local Toolkit

Habilidade de projeto para o `postagem-automatica`. Segue a sequência abaixo em ordem; não pule etapas.

## 1. Inspecionar antes de alterar

Execute e mostre a saída completa:

```bash
ollama --version
ollama ls
ollama ps
```

Se `ollama` não for encontrado:
- macOS/Linux: `brew install ollama` ou baixar em https://ollama.com/download
- Windows: instalar via https://ollama.com/download (instalador `.exe`)

Se o serviço não estiver rodando:
```bash
ollama serve          # macOS/Linux (terminal separado)
# Windows: abrir o app Ollama na bandeja do sistema
```

## 2. Verificar variáveis de ambiente do projeto

Leia apenas as variáveis de IA — **nunca imprima o conteúdo completo do `.env`**:

```bash
# Mostra somente as variáveis relevantes
grep -E "^(AI_BACKEND|OLLAMA_|ANTHROPIC)" .env 2>/dev/null \
  | sed 's/ANTHROPIC_API_KEY=.*/ANTHROPIC_API_KEY=<ocultado>/'
```

Variáveis esperadas para modo local:

```
AI_BACKEND=ollama
OLLAMA_HOST=http://localhost:11434
OLLAMA_MODEL=qwen3:4b        # ou qwen2.5-coder:7b para código
OLLAMA_NO_CLOUD=1
OLLAMA_CONTEXT_LENGTH=4096   # 2048–4096 para GPUs com menos de 8 GB VRAM
```

## 3. Bloquear modelos cloud

Se `OLLAMA_MODEL` contiver `:cloud` ou `-cloud`, substitua **antes** de qualquer teste:

```bash
# Troque por um modelo local instalado
export OLLAMA_MODEL=qwen3:4b
```

O `src/gerador.py` rejeita automaticamente modelos cloud quando `AI_BACKEND=ollama`.
Confirme com: `python -c "from gerador import _assert_not_cloud; _assert_not_cloud('qwen3:4b'); print('OK')"`

## 4. Confirmar GPU após inferência

Faça uma inferência curta e **imediatamente** execute `ollama ps`:

```bash
ollama run qwen3:4b "Responda somente: teste local confirmado." && ollama ps
```

Interprete a coluna `PROCESSOR`:

| Valor | Significado | Ação |
|-------|-------------|------|
| `100% GPU` | Modelo inteiramente na VRAM | Ótimo — continue |
| `100% CPU` | Sem GPU ou VRAM insuficiente | Veja referência VRAM |
| `X% GPU / Y% CPU` | Carregamento híbrido | Modelo parcialmente na VRAM; pode ser lento |

## 5. Selecionar modelo conforme VRAM disponível

Consulte `references/vram-guide.md` desta habilidade antes de sugerir modelos maiores.

Para GPUs com menos de 8 GB VRAM, use a sequência:
1. `qwen2.5-coder:3b` — menor consumo
2. `qwen3:4b` — fallback geral já disponível
3. `qwen2.5-coder:7b` — melhor equilíbrio (requer ~5–6 GB VRAM)

Consulte `references/model-selection.md` para a matriz completa.

## 6. Verificar testes antes de sugerir commit

Execute os testes isolados (não fazem chamadas externas):

```bash
python -m pytest tests/test_gerador_local.py -v
# ou: python tests/test_gerador_local.py
```

Mostre o `git diff` antes de qualquer sugestão de commit:

```bash
git diff
git diff --stat
```

**Nunca faça `git push` sem confirmação explícita do usuário.**

## 7. Investigar erro 403 Forbidden

O erro `403 Forbidden: this model requires a subscription` ocorre quando:

1. `OLLAMA_MODEL` aponta para um modelo cloud (ex: `glm-5.2:cloud`)
2. `OLLAMA_HOST` está apontando para `api.ollama.com` em vez de `localhost`
3. O aplicativo Ollama tem um modelo cloud selecionado como padrão na interface

Diagnóstico rápido:

```bash
echo "HOST: $OLLAMA_HOST"
echo "MODEL: $OLLAMA_MODEL"
curl -s http://localhost:11434/api/version   # deve retornar JSON com versão
ollama ls | grep -v ':cloud'               # modelos locais disponíveis
```

## Referências desta habilidade

- `references/model-selection.md` — matriz de modelos por cenário de uso
- `references/vram-guide.md` — guia de VRAM para GPUs com menos de 8 GB
- `OLLAMA_LOCAL_SETUP.md` (raiz do projeto) — setup completo para macOS/Linux/Windows
- `cloud/README.md` — diferença local vs cloud e como usar cloud com confirmação

## Fontes oficiais

- Ollama FAQ: https://github.com/ollama/ollama/blob/main/docs/faq.md
- Ollama GPU: https://github.com/ollama/ollama/blob/main/docs/gpu.md
- Ollama Context: https://github.com/ollama/ollama/blob/main/docs/modelfile.md#parameter
- Claude Code Skills: https://code.claude.com/docs/en/claude-code-on-the-web
