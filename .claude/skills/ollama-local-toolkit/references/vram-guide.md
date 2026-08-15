# Guia de VRAM — GPUs com menos de 8 GB

## Por que o contexto importa

Além do tamanho do modelo, o tamanho do contexto (`num_ctx`) consome VRAM adicional.
Um modelo de 7B com contexto de 64K usa muito mais VRAM do que o mesmo modelo com 4K.

**Regra prática:** comece com `OLLAMA_CONTEXT_LENGTH=4096`.
Aumente apenas se precisar de respostas muito longas e confirmar que a GPU aguenta.

## Consumo estimado por modelo e contexto

| Modelo | Contexto 2K | Contexto 4K | Contexto 8K |
|--------|-------------|-------------|-------------|
| `qwen2.5-coder:3b` | ~2.5 GB | ~2.7 GB | ~3.1 GB |
| `qwen3:4b` | ~2.8 GB | ~3.0 GB | ~3.5 GB |
| `qwen2.5-coder:7b` | ~4.8 GB | ~5.2 GB | ~6.0 GB |
| `deepseek-coder:6.7b` | ~4.5 GB | ~5.0 GB | ~5.8 GB |
| `qwen3:8b` | ~5.5 GB | ~6.0 GB | ~7.0 GB |

*Valores aproximados; variam conforme quantização e versão do Ollama.*

## GPUs com menos de 8 GB VRAM — configuração recomendada

```env
OLLAMA_CONTEXT_LENGTH=4096
OLLAMA_MODEL=qwen2.5-coder:7b   # ou qwen3:4b se 7b não couber
OLLAMA_NO_CLOUD=1
```

## Liberar VRAM após uso

O Ollama mantém o modelo na VRAM por 5 minutos após a última inferência.
Para liberar imediatamente:

```bash
# Via CLI:
ollama stop qwen3:4b

# Via API (keep_alive=0):
curl -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3:4b","keep_alive":0}'
```

## Quando o modelo vai para CPU

Se `ollama ps` mostrar `100% CPU` ou carregamento híbrido:

1. O modelo não cabe inteiro na VRAM → use uma versão menor (ex: `:3b` em vez de `:7b`)
2. Outro processo está consumindo a VRAM → feche aplicativos gráficos pesados
3. O Ollama não detectou a GPU → verifique drivers e execute `scripts/ollama-doctor.sh`

## Verificar VRAM disponível antes de carregar

```bash
# NVIDIA:
nvidia-smi --query-gpu=memory.free,memory.total --format=csv,noheader

# AMD (Linux com ROCm):
rocm-smi --showmeminfo vram

# macOS (Activity Monitor → GPU History)
# ou: sudo powermetrics --samplers gpu_power -n 1 2>/dev/null | grep -i "gpu"
```
