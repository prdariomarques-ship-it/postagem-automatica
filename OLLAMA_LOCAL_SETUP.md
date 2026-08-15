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

---

## 11. Operação em VM Linux com systemd

> **Distinção essencial:** hospedar o Ollama em uma VM é diferente de usar modelos Ollama Cloud.
> Quando o bot e o Ollama residem na mesma VM e comunicam via `127.0.0.1`, a inferência
> permanece dentro dessa VM. `OLLAMA_NO_CLOUD=1` bloqueia recursos cloud do Ollama;
> não transforma a VM em infraestrutura gratuita nem adiciona GPU a ela.

### Perfil conservador para GPU limitada

Aplique como override do systemd — veja template em `scripts/systemd/ollama-override.conf.example`:

```ini
[Service]
Environment="OLLAMA_CONTEXT_LENGTH=4096"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_KEEP_ALIVE=0"
Environment="OLLAMA_NO_CLOUD=1"
Environment="OLLAMA_HOST=127.0.0.1:11434"
```

| Variável | Valor inicial | Efeito |
|----------|--------------|--------|
| `OLLAMA_CONTEXT_LENGTH` | `4096` | Limita tokens de contexto; contextos maiores consomem mais VRAM |
| `OLLAMA_NUM_PARALLEL` | `1` | Uma requisição por modelo; requisições paralelas multiplicam reserva de VRAM |
| `OLLAMA_MAX_LOADED_MODELS` | `1` | Um modelo na VRAM por vez |
| `OLLAMA_KEEP_ALIVE` | `0` | Libera VRAM imediatamente após resposta. Use `"30s"` ou `"2m"` para reduzir latência em uso frequente; evite `"-1"` em GPU limitada |
| `OLLAMA_NO_CLOUD` | `1` | Bloqueia recursos cloud do servidor |

Aplicar e verificar:

```bash
sudo mkdir -p /etc/systemd/system/ollama.service.d/
sudo cp scripts/systemd/ollama-override.conf.example \
       /etc/systemd/system/ollama.service.d/override.conf
# Edite conforme necessário, depois:
sudo systemctl daemon-reload
sudo systemctl restart ollama
systemctl status ollama --no-pager
```

**Não exponha a porta 11434 publicamente** sem TLS, autenticação e regras de firewall.

### Telemetria de GPU durante inferência (Nvidia)

Execute apenas enquanto uma inferência real estiver em curso; interrompa com `Ctrl+C`:

```bash
nvidia-smi \
  --query-gpu=timestamp,name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw \
  --format=csv -l 1
```

Para registrar uma sessão:

```bash
nvidia-smi \
  --query-gpu=timestamp,utilization.gpu,memory.used,memory.total,temperature.gpu \
  --format=csv -l 1 \
  | tee "logs/ollama-vram-$(date +%Y%m%d-%H%M%S).csv"
```

---

## 12. Sequência de validação em camadas

| Camada | Comando | O que confirma | O que não confirma |
|--------|---------|---------------|-------------------|
| 1. Testes isolados | `python3 tests/test_gerador_local.py` | Contrato de backend, bloqueios cloud | GPU, VRAM, modelo real |
| 2. Inferência curta | `ollama run qwen3:4b "teste local confirmado."` | Servidor responde com modelo local | Que está na GPU |
| 3. `ollama ps` | após a inferência acima | CPU/GPU/híbrido do modelo ativo | Temperatura, potência |
| 4. Telemetria GPU | `nvidia-smi -l 1` durante inferência | VRAM, utilização, temperatura | Lógica de backend |

Execute na ordem: 1 → 2 → 3 → 4. Uma falha na camada 1 invalida as camadas seguintes.

---

## 13. Checklist de aceite antes de implantar

```
[ ] VM possui recursos suficientes; VRAM confirmada para o modelo escolhido (ver §15).
[ ] GPU/driver validada antes de exigir aceleração (nvidia-smi ou rocm-smi disponível).
[ ] Bot e Ollama comunicam via localhost/127.0.0.1 na mesma VM.
[ ] AI_BACKEND=ollama e OLLAMA_NO_CLOUD=1 estão definidos.
[ ] Nenhuma chave DeepSeek/OpenAI inserida no perfil local-only.
[ ] Contexto 4K, 1 requisição paralela e 1 modelo carregado ativos inicialmente.
[ ] OLLAMA_KEEP_ALIVE=0 escolhido para liberar VRAM automaticamente.
[ ] python3 tests/test_gerador_local.py retornou 13/13 passando.
[ ] Inferência curta respondeu com modelo local sem :cloud.
[ ] ollama ps conferido durante a inferência — coluna PROCESSOR mostra "100% GPU".
[ ] ss -ltnp | grep 11434 confirma 127.0.0.1:11434 (não 0.0.0.0:11434).
[ ] Porta 11434 bloqueada para interfaces externas (UFW ou iptables — ver §14).
[ ] Nenhuma alteração commitada/enviada sem revisão e confirmação humana.
[ ] .env não está versionado (confirmar: git status | grep -v '\.env\.example').
```

---

## 14. Isolamento de rede (porta 11434)

Por padrão, o Ollama pode escutar em `0.0.0.0:11434`, expondo a API a qualquer
interface de rede da VM. Em ambiente de produção, restrinja a porta ao loopback.

### Verificação antes de aplicar regras

```bash
# Confirme o estado atual antes de modificar firewall:
ss -ltnp | grep ':11434'
```

| Resultado | Significado | Ação |
|-----------|-------------|------|
| `127.0.0.1:11434` | Seguro — loopback apenas | Nenhuma |
| `0.0.0.0:11434` | Exposto em todas as interfaces | Aplicar regras abaixo |
| Sem resultado | Serviço inativo | Inicie o Ollama antes |

### UFW (recomendado para Ubuntu/Debian)

```bash
# Bloquear acesso externo à porta 11434:
sudo ufw deny in on eth0 to any port 11434
sudo ufw allow in on lo to any port 11434

# Verificar regras aplicadas:
sudo ufw status numbered | grep 11434
```

> **Atenção:** Não combine regras UFW e `iptables` manuais no mesmo host.
> Use somente um dos métodos.

### iptables (alternativa, sem UFW)

```bash
# Permitir loopback; bloquear demais interfaces:
sudo iptables -A INPUT -i lo -p tcp --dport 11434 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 11434 -j DROP

# Persistir (Debian/Ubuntu):
sudo apt-get install -y iptables-persistent
sudo netfilter-persistent save

# Verificar:
sudo iptables -L INPUT -n --line-numbers | grep 11434
```

### Verificação final

```bash
# Deve mostrar apenas 127.0.0.1:11434 ou nenhum resultado externo:
ss -ltnp | grep ':11434'

# Testar que a API não responde externamente (substitua pelo IP da VM):
# curl --max-time 3 http://<ip-externo-da-vm>:11434/api/version
# deve retornar "Connection refused" ou timeout.
```

---

## 15. Dimensionamento de GPU/VRAM por modelo

### Requisitos mínimos de GPU

| Requisito | Valor mínimo | Observação |
|-----------|-------------|------------|
| Compute Capability (Nvidia) | 5.0 (Maxwell, 2014+) | Série 900 ou superior |
| Driver Nvidia | 550+ | `nvidia-smi` mostra a versão |
| ROCm (AMD) | 5.4+ | `rocm-smi --version` |
| Apple Silicon | M1 ou superior | Metal nativo; sem CUDA |

> Verifique compute capability em: https://developer.nvidia.com/cuda-gpus

### Perfil de VRAM por família de modelo (quantização Q4)

| Modelo | VRAM mínima | VRAM recomendada | Observações |
|--------|------------|-----------------|-------------|
| `qwen2.5-coder:3b` | 3 GB | 4 GB | Seguro em GPUs de 4–6 GB |
| `qwen3:4b` | 3 GB | 4 GB | Fallback geral; já instalado |
| `deepseek-coder:6.7b` | 5 GB | 6 GB | Alternativa de código |
| `qwen2.5-coder:7b` | 5 GB | 8 GB | **Principal para programação local** |
| `qwen3:8b` / `deepseek-r1:8b` | 6 GB | 8–10 GB | Qualidade superior; exige margem |
| `qwen2.5-coder:14b` | 10 GB | 12–16 GB | Modelos 14B; checar antes de baixar |
| `qwen3-coder:30b` | 20 GB | 24 GB | Requer GPU de alta capacidade |

**Regra prática:** VRAM disponível = VRAM da GPU − uso do sistema. Mantenha ≥ 1 GB de margem
para evitar que o modelo transborde para CPU durante a inferência.

### Recursos adicionais de VM (além da GPU)

| Recurso | Mínimo recomendado | Para 13B+ |
|---------|-------------------|-----------|
| RAM do sistema | 16 GB | 32 GB |
| vCPUs | 4 | 8 |
| Disco (`~/.ollama/models`) | 30 GB livres | 60 GB livres |

### Verificar VRAM disponível antes de baixar

```bash
# Nvidia:
nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader

# Espaço em disco:
df -h ~/.ollama/models 2>/dev/null || df -h ~

# Tamanho do modelo antes de baixar (apenas leitura, sem download):
ollama show qwen2.5-coder:7b --modelfile 2>/dev/null | head -5
```

> Se `ollama ps` mostrar `100% CPU` após carregamento, a VRAM não foi suficiente.
> Use um modelo menor ou feche outros processos que consomem GPU.

---

## Referências

- Ollama FAQ: https://docs.ollama.com/faq
- Ollama Context Length: https://docs.ollama.com/context-length
- Ollama GPU: https://docs.ollama.com/gpu
- Ollama API (keep_alive): https://github.com/ollama/ollama/blob/main/docs/api.md#generate-a-completion
