# Guia de configuração — Ollama local

Verificação passo a passo do ambiente Ollama, com comandos reais e interpretação de saídas.

---

## 1. Verificação inicial — rode estes 4 comandos

Cole cada linha no terminal e envie a saída ao assistente para diagnóstico:

```bash
ollama --version
ollama ls
ollama run qwen3:4b "Responda somente: teste local confirmado."
ollama ps
```

**O que cada um faz:**

| Comando | Esperado | Se falhar |
|---------|----------|-----------|
| `ollama --version` | `ollama version 0.x.x` | Ollama não instalado — baixe em ollama.com/download |
| `ollama ls` | Tabela com modelos e tamanhos | Serviço offline — rode `ollama serve` |
| `ollama run qwen3:4b "..."` | Texto confirmando o teste | Modelo não encontrado — rode `ollama pull qwen3:4b` |
| `ollama ps` | Linha com `qwen3:4b` e uso de CPU/GPU | Vazio = modelo já descarregou (normal após resposta) |

---

## 2. Referência completa de comandos Ollama

### Listar modelos instalados
```bash
ollama list
# Mostra: nome, ID, tamanho em disco, data de modificação
```

### Executar modelo em modo interativo
```bash
ollama run qwen3:4b
# Abre um chat. Digite /bye ou pressione Ctrl+D para sair.
```

### Fazer uma pergunta e sair
```bash
ollama run qwen3:4b "Qual é a capital do Brasil?"
# Retorna a resposta e encerra. Útil para testes e automação.
```

### Verificar modelos na memória (CPU/GPU)
```bash
ollama ps
# Mostra: modelo, ID, tamanho na VRAM, processador (CPU/GPU), tempo restante
```

### Descarregar modelo da memória
```bash
# Ollama descarrega automaticamente após 5 minutos de inatividade.
# Para forçar imediatamente:
curl http://localhost:11434/api/generate -d '{"model":"qwen3:4b","keep_alive":0}'

# Ou use o script:
./scripts/local-ai.sh stop qwen3:4b
```

### Remover modelo do disco
```bash
ollama rm qwen3:4b
# ATENÇÃO: apaga o modelo permanentemente. Para reinstalar: ollama pull qwen3:4b
```

### Verificar uso de GPU durante inferência
```bash
# NVIDIA:
nvidia-smi
# Procure: GPU-Util > 0%, Memory-Usage aumentado

# macOS (Apple Silicon):
# Activity Monitor → janela GPU History
# Ou: brew install asitop && sudo asitop

# AMD Linux:
rocm-smi
```

---

## 3. Garantir que o app usa modelos locais

O erro `403 Forbidden: this model requires a subscription` ocorre quando o aplicativo
seleciona um modelo cloud (ex: `glm-5.2:cloud`) em vez de um local.

**Verifique e corrija:**

```bash
# 1. Confirme que o serviço local está ativo
curl http://localhost:11434/api/version
# Esperado: {"version":"0.x.x"}

# 2. Verifique a variável OLLAMA_HOST
echo $OLLAMA_HOST
# Deve estar vazia (usa localhost:11434 por padrão) ou ser http://localhost:11434
# NUNCA deve apontar para api.ollama.com

# 3. Liste modelos sem sufixo :cloud
ollama list | grep -v ':cloud'

# 4. Defina o modelo padrão no .env deste projeto
# AI_BACKEND=ollama
# OLLAMA_MODEL=qwen3:4b
# OLLAMA_HOST=http://localhost:11434
```

---

## 4. Rotina de seleção de modelo por capacidade do hardware

### Perfil leve — 4 a 6 GB de RAM livre
```bash
ollama run qwen3:4b      # Chat geral rápido
ollama run gemma3:4b     # Alternativa, bom em português
```
- Tempo de resposta esperado com CPU: 5–20 segundos por frase
- Com GPU (4 GB VRAM): 1–5 segundos

### Perfil intermediário — 8 a 12 GB de RAM livre
```bash
ollama run qwen3:8b          # Mais qualidade que o 4b
ollama run deepseek-r1:8b    # Raciocínio passo a passo; mais lento
```
- Recomendado ter GPU com ≥ 6 GB VRAM para boa velocidade

### Perfil pesado — 16 GB+ de RAM livre
```bash
ollama run qwen3.5:9b    # Somente se o hardware não travar
```
- Verifique `ollama ps` para confirmar que a GPU está sendo usada

### Verificando `gemma4` e `qwen3.6` antes de usar
```bash
# Pesquise tags disponíveis antes de baixar:
# https://ollama.com/library/gemma4
# https://ollama.com/library/qwen3

# Veja o tamanho antes do pull:
ollama show gemma4         # mostra detalhes se já baixado
ollama pull gemma4:4b      # especifique sempre a tag de tamanho
```

---

## 5. Interpretando saídas de diagnóstico

### `ollama ps` — o que cada coluna significa

```
NAME            ID              SIZE      PROCESSOR    UNTIL
qwen3:4b        abc123          5.2 GB    100% GPU     4 minutes from now
```

| Coluna | Significado |
|--------|-------------|
| `PROCESSOR = 100% GPU` | GPU usada integralmente — ótimo |
| `PROCESSOR = 100% CPU` | Sem GPU ou não coube na VRAM |
| `PROCESSOR = 50% GPU / 50% CPU` | Modelo dividido entre GPU e RAM |
| `UNTIL` | Quando o modelo será descarregado automaticamente |

### `nvidia-smi` — o que observar durante inferência

```
| GPU  Name        | Memory-Usage       | GPU-Util |
|  0   RTX 3060    | 5800MiB / 12288MiB |     85%  |
```

- **GPU-Util > 0%** durante a resposta = GPU está trabalhando
- **Memory-Usage** próximo ao tamanho do modelo = modelo está na VRAM
- Se GPU-Util ficar em 0% o tempo todo, o Ollama pode estar usando CPU

---

## 6. Scripts prontos neste repositório

```bash
# macOS / Linux — dar permissão de execução uma vez:
chmod +x scripts/local-ai.sh

# Diagnóstico completo:
./scripts/local-ai.sh doctor

# Teste rápido:
./scripts/local-ai.sh test qwen3:4b

# Verificar GPU durante uso:
./scripts/local-ai.sh gpu

# Windows (PowerShell):
.\scripts\local-ai.ps1 doctor
.\scripts\local-ai.ps1 test qwen3:4b
```

---

## 7. Usar Ollama Cloud somente de forma deliberada

Etapas obrigatórias antes de qualquer uso cloud:

1. Consulte seu plano: https://ollama.com/settings/billing
2. Leia o guia: `cloud/README.md` neste repositório
3. Faça login explícito: `./scripts/local-ai.sh cloud-login`
4. Envie com confirmação: `./scripts/local-ai.sh cloud-run glm-5.2:cloud "seu prompt"`

O script **sempre pede confirmação** antes de enviar qualquer prompt para a nuvem.  
Nenhuma chave ou senha é armazenada neste repositório.
