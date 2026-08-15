# Matriz de seleção de modelos — Ollama local

Use esta tabela para escolher o modelo adequado ao hardware disponível.
Sempre verifique com `ollama ls` se a tag está instalada antes de sugerir download.

## Para programação (código)

| Cenário | Modelo | VRAM estimada | Observação |
|---------|--------|---------------|------------|
| GPU limitada / teste rápido | `qwen2.5-coder:3b` | ~2–3 GB | Menor consumo; bom para edições simples |
| Melhor equilíbrio | `qwen2.5-coder:7b` | ~5–6 GB | **Opção principal** para programação local |
| Alternativa de código | `deepseek-coder:6.7b` | ~5 GB | Útil para comparar estilo e qualidade |
| Alta qualidade (com folga) | `qwen2.5-coder:14b` | ~10–12 GB | Só sugerir após confirmar que a máquina aguenta |

## Para chat geral (texto, conteúdo)

| Cenário | Modelo | VRAM estimada | Observação |
|---------|--------|---------------|------------|
| Leve | `qwen3:4b` | ~3 GB | Fallback geral; já instalado neste projeto |
| Leve com suporte multimodal | `gemma3:4b` | ~3 GB | Bom em português |
| Intermediário | `qwen3:8b` | ~6 GB | Mais qualidade; requer GPU adequada |
| Raciocínio | `deepseek-r1:8b` | ~6–7 GB | Mais lento; usa chain-of-thought |
| Maior qualidade (com folga) | `qwen3.5:9b` | ~7–8 GB | Somente se não travar |

## Verificar tag antes de baixar

```bash
# Ver tags disponíveis para um modelo:
# Acesse: https://ollama.com/library/<nome-do-modelo>

# Ver tamanho do modelo antes de baixar (sem baixar):
# A página do modelo em ollama.com mostra o tamanho por tag.

# Verificar espaço livre antes de baixar:
df -h ~/.ollama/models    # macOS/Linux
# Windows: Get-PSDrive C | Select-Object Used,Free

# Baixar apenas com confirmação do usuário:
ollama pull qwen2.5-coder:7b
```

## Verificar se o modelo está na GPU após carregar

```bash
ollama run qwen3:4b "Responda em uma palavra: ok" && ollama ps
```

Coluna `PROCESSOR` em `ollama ps`:
- `100% GPU` → modelo inteiro na VRAM ✔
- `100% CPU` → sem GPU / VRAM insuficiente
- `X% GPU / Y% CPU` → carregamento híbrido (mais lento)
