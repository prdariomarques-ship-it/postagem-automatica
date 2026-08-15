# Configuração local do Ollama — guia completo

Este guia cobre macOS/Linux/WSL e Windows PowerShell. Inclui diagnóstico de GPU,
perfil para GPUs com menos de 8 GB VRAM, e como usar a habilidade do Claude Code.

## Fontes oficiais

- Ollama FAQ: https://github.com/ollama/ollama/blob/main/docs/faq.md
- Ollama GPU: https://github.com/ollama/ollama/blob/main/docs/gpu.md
- Ollama Context/Modelfile: https://github.com/ollama/ollama/blob/main/docs/modelfile.md#parameter
- Ollama API: https://github.com/ollama/ollama/blob/main/docs/api.md

---

## 1. Verificação inicial (execute agora)

### macOS / Linux / WSL

```bash
ollama --version
ollama ls
ollama ps
```

### Windows PowerShell

```powershell
ollama --version
ollama list
ollama ps
```

**O que esperar:**

| Comando | Resultado esperado | Se falhar |
|---------|-------------------|-----------|
| `ollama --version` | `ollama version 0.x.x` | Não instalado — baixar em ollama.com/download |
| `ollama ls` / `ollama list` | Tabela com modelos | Serviço offline — abra o app ou rode `ollama serve` |
| `ollama ps` | Linha de modelo ou vazio (normal se inativo) | Serviço offline |

---

## 2. Diagnóstico completo com os scripts do projeto

```bash
# macOS/Linux — dar permissão uma vez:
chmod +x scripts/ollama-doctor.sh scripts/ollama-monitor.sh scripts/local-ai.sh

# Diagnóstico completo (só leitura):
./scripts/ollama-doctor.sh

# Com teste de inferência (opt-in; consome recursos):
./scripts/ollama-doctor.sh --test-model qwen3:4b
```

```powershell
# Windows:
.\scripts\ollama-doctor.ps1
.\scripts\ollama-doctor.ps1 -TestModel qwen3:4b
```

---

## 3. Perfil para GPUs com menos de 8 GB VRAM

### Por que o contexto importa

O Ollama usa contexto padrão de 2048 tokens, mas configurações padrão de algumas
versões chegam a 64K — isso multiplica o consumo de VRAM sem necessidade para a
maioria dos casos de uso.

**Configure no `.env` do projeto:**

```env
AI_BACKEND=ollama
OLLAMA_HOST=http://localhost:11434
OLLAMA_MODEL=qwen2.5-coder:7b
OLLAMA_NO_CLOUD=1
OLLAMA_CONTEXT_LENGTH=4096
```

### Princípios de baixo consumo de VRAM

| Objetivo | Configuração | Motivo |
|----------|-------------|--------|
| Caber na VRAM | Contexto 2K–4K | Contextos maiores consomem mais memória |
| Evitar competição | 1 modelo ativo de cada vez | Reduz risco de descarregamento para CPU |
| Liberar VRAM após testes | `ollama stop <modelo>` | Remove o modelo da memória imediatamente |
| Ficar local | `OLLAMA_NO_CLOUD=1` + sem sufixo `:cloud` | Evita chamadas e bloqueios de assinatura |

### Consumo estimado por modelo (contexto 4K)

| Modelo | VRAM estimada | Uso |
|--------|--------------|-----|
| `qwen2.5-coder:3b` | ~2.7 GB | Programação leve; menor consumo |
| `qwen3:4b` | ~3.0 GB | Chat geral; fallback já instalado |
| `qwen2.5-coder:7b` | ~5.2 GB | **Principal para programação local** |
| `deepseek-coder:6.7b` | ~5.0 GB | Alternativa de código |
| `qwen3:8b` | ~6.0 GB | Chat de maior qualidade |
| `deepseek-r1:8b` | ~6.5 GB | Raciocínio passo a passo (mais lento) |

> Atenção: `qwen3.5:9b` requer ~7–8 GB e pode transbordar para CPU em GPUs de 8 GB.

### Matriz de seleção por cenário

| Cenário | Modelo sugerido | Observação |
|---------|----------------|------------|
| GPU limitada / teste rápido | `qwen2.5-coder:3b` | Menor consumo; bom para edições simples |
| Melhor equilíbrio (programação) | `qwen2.5-coder:7b` | Opção principal |
| Alternativa de código | `deepseek-coder:6.7b` | Útil para comparar estilo e qualidade |
| Alta qualidade (com folga) | `qwen2.5-coder:14b` | Só sugerir após confirmar que aguenta |
| Fallback geral (já instalado) | `qwen3:4b` | Use se modelos Coder não estiverem disponíveis |

### Verificar se a tag existe antes de baixar

```bash
# Sempre verifique espaço disponível:
df -h ~/.ollama/models       # macOS/Linux
# Get-PSDrive C | Select-Object Used, Free    # Windows

# Baixar somente após confirmar espaço:
ollama pull qwen2.5-coder:7b
```

---

## 4. Verificar GPU durante inferência

### Interpretação de `ollama ps`

```
NAME            ID              SIZE      PROCESSOR    UNTIL
qwen3:4b        abc123def       3.0 GB    100% GPU     4 minutes from now
```

| Coluna `PROCESSOR` | Significado | Ação |
|-------------------|-------------|------|
| `100% GPU` | Modelo inteiro na VRAM | Desempenho ótimo |
| `100% CPU` | Sem GPU ou VRAM insuficiente | Use modelo menor |
| `X% GPU / Y% CPU` | Carregamento híbrido | Modelo não cabe todo na VRAM |

### nvidia-smi durante inferência

```bash
nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu \
  --format=csv,noheader
```

- `utilization.gpu > 0%` durante resposta = GPU trabalhando
- `memory.used` próximo ao tamanho do modelo = modelo na VRAM

### macOS (Apple Silicon)

```bash
# Instale e execute (não requer GPU Nvidia):
brew install asitop
sudo asitop
# Ou: Activity Monitor → Janela → GPU History
```

### AMD Linux

```bash
# Se ROCm estiver instalado:
rocm-smi
# Se não: relato de limitação — o monitor registra apenas ollama ps, CPU e RAM
```

---

## 5. Liberar VRAM após uso

```bash
# Via CLI (macOS/Linux):
ollama stop qwen3:4b

# Via API (keep_alive=0):
curl -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3:4b","keep_alive":0}'

# Via script do projeto:
./scripts/local-ai.sh stop qwen3:4b    # macOS/Linux
.\scripts\local-ai.ps1 stop qwen3:4b  # Windows
```

---

## 6. Monitoramento de desempenho

```bash
# Monitor ao vivo (Ctrl+C para parar):
./scripts/ollama-monitor.sh

# Com log CSV:
./scripts/ollama-monitor.sh --log --modelo qwen3:4b

# Intervalo personalizado e duração automática:
./scripts/ollama-monitor.sh --intervalo 5 --duracao 120 --log
```

```powershell
# Windows:
.\scripts\ollama-monitor.ps1
.\scripts\ollama-monitor.ps1 -Log -Modelo qwen3:4b -Duracao 60
```

Logs ficam em `logs/ollama-monitor-AAAAmmdd-HHMMSS.csv`.

---

## 7. Configurar o backend deste projeto

Copie `.env.example` para `.env` e edite:

```bash
cp .env.example .env
# Edite com seu editor preferido
```

Para usar Ollama local (sem custo de API):

```env
AI_BACKEND=ollama
OLLAMA_HOST=http://localhost:11434
OLLAMA_MODEL=qwen3:4b
OLLAMA_NO_CLOUD=1
OLLAMA_CONTEXT_LENGTH=4096
```

Para usar Claude API (padrão):

```env
AI_BACKEND=claude
ANTHROPIC_API_KEY=sk-ant-...
```

> O código em `src/gerador.py` rejeita automaticamente modelos com `:cloud` ou `-cloud`
> quando `AI_BACKEND=ollama`, emitindo um erro com instruções de correção.

---

## 8. Habilidade do Claude Code (para uso no projeto)

A habilidade `/ollama-local-toolkit` está em `.claude/skills/ollama-local-toolkit/SKILL.md`.

**Como usar no Claude Code:**

1. Abra o Claude Code na raiz do projeto.
2. A habilidade é carregada automaticamente por estar em `.claude/skills/`.
3. Invoque com `/ollama-local-toolkit` ou descreva o problema — o Claude Code
   ativa a habilidade automaticamente quando detecta palavras como "ollama",
   "erro 403", "GPU", "VRAM", "backend local".

**Não é necessário acesso à nuvem** para usar a habilidade — ela opera inteiramente
sobre o repositório local e o ambiente Ollama local.

---

## 9. Investigar erro 403 Forbidden

```
403 Forbidden: this model requires a subscription, upgrade for access
```

Diagnóstico rápido:

```bash
# 1. Confirmar host local:
echo $OLLAMA_HOST          # deve estar vazio ou ser http://localhost:11434
curl http://localhost:11434/api/version

# 2. Confirmar modelo local:
echo $OLLAMA_MODEL         # não deve conter :cloud
ollama list | grep -v ':cloud'

# 3. Testar modelo local:
ollama run qwen3:4b "Responda somente: local OK"
```

Se o app Ollama tiver um modelo cloud selecionado como padrão:
abra o app → clique no nome do modelo → escolha um modelo local da lista.

---

## 10. Não fazer

- Nunca defina `OLLAMA_HOST=https://api.ollama.com` sem querer usar cloud.
- Nunca commite o arquivo `.env` (está no `.gitignore`).
- Nunca use `--no-verify` para contornar hooks git.
- Nunca inicie o monitor com início automático no boot sem confirmação do usuário.
- Não faça `git push` sem revisar `git diff --stat` primeiro.
