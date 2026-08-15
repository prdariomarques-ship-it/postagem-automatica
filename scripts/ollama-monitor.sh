#!/usr/bin/env bash
# ollama-monitor.sh — Monitoramento local de desempenho do Ollama
# Sem serviços em nuvem, sem dependências Python externas.
#
# Modos:
#   padrão  → monitora em intervalos até Ctrl+C
#   --log   → grava CSV em logs/ollama-monitor-AAAAmmdd-HHMMSS.csv
#
# Uso:
#   ./scripts/ollama-monitor.sh [opções]
#   --intervalo <seg>   intervalo de coleta (padrão: 2)
#   --log               grava CSV
#   --modelo <tag>      identifica a sessão no log
#   --duracao <seg>     encerra automaticamente após N segundos

set -euo pipefail

# ── Padrões ──────────────────────────────────────────────────────────────────
INTERVALO=2
LOG_MODE=0
MODELO_TAG=""
DURACAO=0
OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"

# ── Argumentos ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --intervalo) INTERVALO="${2:?'--intervalo requer valor'}"; shift 2 ;;
    --log)       LOG_MODE=1; shift ;;
    --modelo)    MODELO_TAG="${2:?'--modelo requer valor'}"; shift 2 ;;
    --duracao)   DURACAO="${2:?'--duracao requer valor'}"; shift 2 ;;
    -h|--help)
      cat <<HELP
Uso: $0 [--intervalo <seg>] [--log] [--modelo <tag>] [--duracao <seg>]

  --intervalo <seg>   Segundos entre coletas (padrão: 2)
  --log               Grava CSV em logs/ollama-monitor-AAAAmmdd-HHMMSS.csv
  --modelo <tag>      Tag de modelo para identificar a sessão (opcional)
  --duracao <seg>     Encerra após N segundos (0 = até Ctrl+C)

Exemplos:
  $0                              # Monitor ao vivo, 2s de intervalo
  $0 --intervalo 5 --log          # Loga a cada 5 segundos
  $0 --modelo qwen3:4b --duracao 60 --log
HELP
      exit 0 ;;
    *) echo "Argumento desconhecido: $1" >&2; exit 1 ;;
  esac
done

# ── Verificar Ollama ──────────────────────────────────────────────────────────
if ! command -v ollama &>/dev/null; then
  echo "ERRO: ollama não encontrado no PATH." >&2
  echo "Instale em: https://ollama.com/download" >&2
  exit 1
fi

# ── Detectar GPU ──────────────────────────────────────────────────────────────
GPU_TYPE="none"
if command -v nvidia-smi &>/dev/null; then
  GPU_TYPE="nvidia"
elif command -v rocm-smi &>/dev/null; then
  GPU_TYPE="amd"
elif [[ "$(uname)" == "Darwin" ]]; then
  GPU_TYPE="apple"
fi

# ── Arquivo de log ────────────────────────────────────────────────────────────
LOG_FILE=""
if [[ "$LOG_MODE" -eq 1 ]]; then
  mkdir -p logs
  TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
  LOG_FILE="logs/ollama-monitor-${TIMESTAMP}.csv"
  CSV_HEADER="datetime,ollama_model,processor,gpu_util_pct,vram_used_mb,vram_total_mb,cpu_pct,ram_avail_mb,session_model"
  echo "$CSV_HEADER" > "$LOG_FILE"
  echo "Log CSV: ${LOG_FILE}"
fi

# ── Coletar linha de dados ────────────────────────────────────────────────────
collect() {
  local DT MODEL_COL PROC_COL GPU_UTIL VRAM_USED VRAM_TOTAL CPU_PCT RAM_AVAIL

  DT=$(date +"%Y-%m-%dT%H:%M:%S")
  MODEL_COL=""; PROC_COL=""; GPU_UTIL=""; VRAM_USED=""; VRAM_TOTAL=""

  # ollama ps (model + processor)
  local PS_LINE
  PS_LINE=$(ollama ps 2>/dev/null | tail -n +2 | head -1 || true)
  if [[ -n "$PS_LINE" ]]; then
    MODEL_COL=$(echo "$PS_LINE" | awk '{print $1}')
    PROC_COL=$(echo "$PS_LINE" | awk '{
      for(i=1;i<=NF;i++) if($i ~ /[0-9]+%/) {
        printf $i; i++; while(i<=NF && $i ~ /[A-Za-z%\/]/) { printf " "$i; i++ }; break
      }
    }')
  fi

  # GPU
  case "$GPU_TYPE" in
    nvidia)
      local NV_LINE
      NV_LINE=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total \
        --format=csv,noheader,nounits 2>/dev/null | head -1 || true)
      if [[ -n "$NV_LINE" ]]; then
        GPU_UTIL=$(echo "$NV_LINE" | cut -d',' -f1 | tr -d ' ')
        VRAM_USED=$(echo "$NV_LINE" | cut -d',' -f2 | tr -d ' ')
        VRAM_TOTAL=$(echo "$NV_LINE" | cut -d',' -f3 | tr -d ' ')
      fi ;;
    amd)
      local AMD_LINE
      AMD_LINE=$(rocm-smi --showuse --showmeminfo vram 2>/dev/null | grep -i "gpu use\|vram" | head -2 || true)
      GPU_UTIL=$(echo "$AMD_LINE" | grep -i "gpu use" | grep -oP '\d+(?=%)' | head -1 || echo "")
      VRAM_USED=$(echo "$AMD_LINE" | grep -i "used" | grep -oP '\d+' | head -1 || echo "")
      VRAM_TOTAL=$(echo "$AMD_LINE" | grep -i "total" | grep -oP '\d+' | head -1 || echo "") ;;
    apple)
      # powermetrics requer sudo — coleta apenas se já disponível sem senha
      GPU_UTIL="indisponivel"
      VRAM_USED="indisponivel"
      VRAM_TOTAL="indisponivel" ;;
    *)
      GPU_UTIL="indisponivel"
      VRAM_USED="indisponivel"
      VRAM_TOTAL="indisponivel" ;;
  esac

  # CPU (load avg 1m, normalizado por cores)
  if [[ -f /proc/loadavg ]]; then
    LOAD=$(awk '{print $1}' /proc/loadavg)
    CORES=$(nproc 2>/dev/null || echo 1)
    CPU_PCT=$(awk "BEGIN {printf \"%.0f\", ($LOAD/$CORES)*100}")
  else
    CPU_PCT=""
  fi

  # RAM disponível (MB)
  if command -v free &>/dev/null; then
    RAM_AVAIL=$(free -m 2>/dev/null | awk '/^Mem:/{print $7}')
  else
    RAM_AVAIL=""
  fi

  # Linha de saída
  printf "%s | modelo: %-20s proc: %-20s gpu_util: %-4s vram: %s/%s MB cpu: %s%% ram_avail: %s MB\n" \
    "$DT" "${MODEL_COL:-<idle>}" "${PROC_COL:-}" \
    "${GPU_UTIL:-?}" "${VRAM_USED:-?}" "${VRAM_TOTAL:-?}" \
    "${CPU_PCT:-?}" "${RAM_AVAIL:-?}"

  if [[ -n "$LOG_FILE" ]]; then
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$DT" "$MODEL_COL" "$PROC_COL" "$GPU_UTIL" "$VRAM_USED" "$VRAM_TOTAL" \
      "$CPU_PCT" "$RAM_AVAIL" "$MODELO_TAG" >> "$LOG_FILE"
  fi
}

# ── Cabeçalho interativo ──────────────────────────────────────────────────────
echo "━━━ Ollama Monitor ━━━  intervalo: ${INTERVALO}s  GPU: ${GPU_TYPE}  Ctrl+C para parar"
if [[ -n "$MODELO_TAG" ]]; then echo "  Sessão: ${MODELO_TAG}"; fi
if [[ "$DURACAO" -gt 0 ]]; then echo "  Duração: ${DURACAO}s"; fi
echo ""

# ── Loop principal ────────────────────────────────────────────────────────────
START=$(date +%s)
while true; do
  collect

  if [[ "$DURACAO" -gt 0 ]]; then
    NOW=$(date +%s)
    if (( NOW - START >= DURACAO )); then
      echo ""
      echo "Duração atingida (${DURACAO}s). Encerrando."
      break
    fi
  fi

  sleep "$INTERVALO"
done

if [[ -n "$LOG_FILE" ]]; then
  echo "CSV salvo em: ${LOG_FILE}"
fi
