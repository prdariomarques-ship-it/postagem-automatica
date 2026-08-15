#!/usr/bin/env bash
# local-ai.sh — Gerenciador Ollama para macOS/Linux
# Uso: ./local-ai.sh <comando> [args]
# Comandos: doctor | list | run | ask | gpu | stop | remove | test | cloud-check | cloud-login | cloud-run

set -euo pipefail

OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
DEFAULT_MODEL="${OLLAMA_DEFAULT_MODEL:-qwen3:4b}"

# ── Cores ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✔${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
err()  { echo -e "${RED}✖${NC} $*" >&2; }
info() { echo -e "${CYAN}→${NC} $*"; }

# ── Helpers ──────────────────────────────────────────────────────────────────
require_ollama() {
  if ! command -v ollama &>/dev/null; then
    err "Ollama não encontrado. Instale em https://ollama.com/download"
    exit 1
  fi
}

ollama_running() {
  curl -sf "${OLLAMA_HOST}/api/version" &>/dev/null
}

ensure_running() {
  if ! ollama_running; then
    warn "Ollama não está respondendo em ${OLLAMA_HOST}."
    warn "Inicie com: ollama serve   (ou abra o app Ollama)"
    exit 1
  fi
}

# ── Comandos ─────────────────────────────────────────────────────────────────

cmd_doctor() {
  info "=== Diagnóstico do ambiente Ollama ==="

  require_ollama
  VERSION=$(ollama --version 2>/dev/null || echo "desconhecida")
  ok "Ollama instalado: ${VERSION}"

  if ollama_running; then
    ok "Serviço respondendo em ${OLLAMA_HOST}"
    API_VER=$(curl -sf "${OLLAMA_HOST}/api/version" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('version','?'))" 2>/dev/null || echo "?")
    info "Versão da API: ${API_VER}"
  else
    warn "Serviço offline. Rode: ollama serve"
  fi

  info "Modelos disponíveis localmente:"
  ollama list 2>/dev/null || warn "Nenhum modelo encontrado."

  # GPU
  if command -v nvidia-smi &>/dev/null; then
    ok "nvidia-smi encontrado. GPU NVIDIA disponível."
    nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader 2>/dev/null || true
  elif [[ "$(uname)" == "Darwin" ]]; then
    ok "macOS detectado — Metal (GPU Apple Silicon/AMD) será usado pelo Ollama se disponível."
  else
    warn "nvidia-smi não encontrado. Pode estar usando apenas CPU."
  fi
}

cmd_list() {
  require_ollama
  ensure_running
  echo ""
  info "Modelos locais instalados:"
  ollama list
}

cmd_run() {
  local model="${1:-$DEFAULT_MODEL}"
  require_ollama
  ensure_running
  info "Iniciando sessão interativa com: ${model}"
  info "Digite /bye ou Ctrl+D para sair."
  echo ""
  ollama run "$model"
}

cmd_ask() {
  local model="${1:-$DEFAULT_MODEL}"
  local prompt="${2:-Responda somente: teste local confirmado.}"
  require_ollama
  ensure_running
  info "Perguntando ao modelo ${model}..."
  echo ""
  ollama run "$model" "$prompt"
}

cmd_gpu() {
  info "=== Uso de GPU durante inferência ==="

  # Modelos carregados no momento
  if ollama_running; then
    info "Modelos atualmente na memória (ollama ps):"
    ollama ps 2>/dev/null || warn "Nenhum modelo carregado."
  fi

  echo ""
  if command -v nvidia-smi &>/dev/null; then
    info "Status da GPU NVIDIA (nvidia-smi):"
    nvidia-smi
  elif [[ "$(uname)" == "Darwin" ]]; then
    info "No macOS, verifique o uso de GPU com Activity Monitor → GPU History."
    info "Ou instale: brew install asitop  e rode: sudo asitop"
  else
    warn "nvidia-smi não encontrado. Para AMD: rocm-smi. Para Intel: intel_gpu_top."
  fi
}

cmd_stop() {
  local model="${1:-}"
  if [[ -z "$model" ]]; then
    err "Uso: $0 stop <nome-do-modelo>"
    err "Exemplo: $0 stop qwen3:4b"
    exit 1
  fi
  require_ollama
  ensure_running
  info "Descarregando modelo da memória: ${model}"
  # Ollama descarrega ao enviar keep_alive=0
  curl -sf -X POST "${OLLAMA_HOST}/api/generate" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${model}\",\"keep_alive\":0}" | python3 -c "import sys,json; d=json.load(sys.stdin); print('done' if not d.get('error') else d['error'])" 2>/dev/null \
    || warn "Resposta inesperada. Verifique com: ollama ps"
  ok "Solicitação de descarregamento enviada para ${model}."
}

cmd_remove() {
  local model="${1:-}"
  if [[ -z "$model" ]]; then
    err "Uso: $0 remove <nome-do-modelo>"
    exit 1
  fi
  warn "Isso apagará permanentemente o modelo '${model}' do disco."
  read -r -p "Confirmar remoção? [s/N] " resp
  if [[ "$resp" =~ ^[sS]$ ]]; then
    ollama rm "$model"
    ok "Modelo '${model}' removido."
  else
    info "Cancelado."
  fi
}

cmd_test() {
  local model="${1:-$DEFAULT_MODEL}"
  require_ollama
  ensure_running
  info "Teste rápido de resposta local — modelo: ${model}"
  local RESP
  RESP=$(ollama run "$model" "Responda somente: teste local confirmado." 2>/dev/null)
  if [[ -n "$RESP" ]]; then
    ok "Resposta recebida:"
    echo "  ${RESP}"
  else
    err "Sem resposta. Verifique se o modelo está instalado com: ollama list"
    exit 1
  fi
}

cmd_cloud_check() {
  info "=== Verificação de uso cloud ==="
  info "O Ollama Cloud permite usar modelos maiores sem baixar localmente."
  echo ""
  warn "ATENÇÃO: modelos cloud consomem créditos/assinatura Ollama."
  warn "Antes de usar, verifique seu plano e limites em: https://ollama.com/settings/billing"
  echo ""
  info "Modelos com sufixo ':cloud' ou prefixo 'glm-*:cloud' são cloud."
  info "Para usar APENAS locais, selecione modelos sem o sufixo ':cloud'."
  echo ""
  if ollama_running; then
    info "Modelos locais disponíveis (sem cloud):"
    ollama list | grep -v ':cloud' || true
  fi
}

cmd_cloud_login() {
  warn "=== Login no Ollama Cloud ==="
  warn "Isso vinculará este terminal à sua conta Ollama."
  warn "Certifique-se de que tem uma conta em https://ollama.com e conhece seu plano."
  echo ""
  read -r -p "Deseja continuar com o login? [s/N] " resp
  if [[ "$resp" =~ ^[sS]$ ]]; then
    info "Iniciando login..."
    ollama login
    ok "Login concluído. Use 'cloud-run' para enviar prompts a modelos cloud."
  else
    info "Cancelado. Nenhum dado de autenticação foi alterado."
  fi
}

cmd_cloud_run() {
  local model="${1:-}"
  local prompt="${2:-}"
  if [[ -z "$model" ]]; then
    err "Uso: $0 cloud-run <modelo-cloud> \"<prompt>\""
    err "Exemplo: $0 cloud-run glm-5.2:cloud \"Olá!\""
    exit 1
  fi
  warn "=== Execução de modelo CLOUD ==="
  warn "Modelo: ${model}"
  warn "Isso pode consumir créditos da sua conta Ollama."
  echo ""
  read -r -p "Confirmar envio do prompt para a nuvem? [s/N] " resp
  if [[ "$resp" =~ ^[sS]$ ]]; then
    require_ollama
    ensure_running
    info "Enviando para ${model}..."
    if [[ -n "$prompt" ]]; then
      ollama run "$model" "$prompt"
    else
      ollama run "$model"
    fi
  else
    info "Cancelado. Nenhum dado enviado para a nuvem."
  fi
}

# ── Roteador ─────────────────────────────────────────────────────────────────

CMD="${1:-help}"
shift 2>/dev/null || true

case "$CMD" in
  doctor)      cmd_doctor ;;
  list)        cmd_list ;;
  run)         cmd_run "$@" ;;
  ask)         cmd_ask "$@" ;;
  gpu)         cmd_gpu ;;
  stop)        cmd_stop "$@" ;;
  remove)      cmd_remove "$@" ;;
  test)        cmd_test "$@" ;;
  cloud-check) cmd_cloud_check ;;
  cloud-login) cmd_cloud_login ;;
  cloud-run)   cmd_cloud_run "$@" ;;
  *)
    echo ""
    echo "Uso: $0 <comando> [args]"
    echo ""
    echo "  doctor        Diagnóstico completo do ambiente"
    echo "  list          Lista modelos instalados localmente"
    echo "  run [modelo]  Sessão interativa (padrão: ${DEFAULT_MODEL})"
    echo "  ask [modelo] \"prompt\"   Pergunta rápida e sai"
    echo "  gpu           Mostra uso de GPU e modelos na memória"
    echo "  stop <modelo> Descarrega modelo da VRAM/RAM"
    echo "  remove <mod>  Remove modelo do disco (pede confirmação)"
    echo "  test [modelo] Teste rápido de resposta local"
    echo "  cloud-check   Informa sobre modelos cloud e plano"
    echo "  cloud-login   Login no Ollama Cloud (pede confirmação)"
    echo "  cloud-run <modelo-cloud> [prompt]  Envia prompt para cloud (pede confirmação)"
    echo ""
    echo "Variáveis de ambiente:"
    echo "  OLLAMA_HOST             (padrão: http://localhost:11434)"
    echo "  OLLAMA_DEFAULT_MODEL    (padrão: qwen3:4b)"
    echo ""
    ;;
esac
