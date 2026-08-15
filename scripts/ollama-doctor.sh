#!/usr/bin/env bash
# ollama-doctor.sh — Diagnóstico seguro do ambiente Ollama
# Executa somente testes de leitura. Teste de inferência é opt-in.
# Uso: ./scripts/ollama-doctor.sh [<modelo>]
#   <modelo>  (opcional) executa inferência de teste com esse modelo

set -euo pipefail

OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
TEST_MODEL="${1:-}"  # argumento posicional: ./ollama-doctor.sh qwen3:4b

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✔${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
err()  { echo -e "${RED}✖${NC} $*"; }
info() { echo -e "${CYAN}→${NC} $*"; }
sep()  { echo -e "${CYAN}────────────────────────────────────────${NC}"; }

sep
info "Ollama Doctor — diagnóstico do ambiente local"
sep

# 1. Verificar instalação
if ! command -v ollama &>/dev/null; then
  err "Ollama não encontrado no PATH."
  err "Instale em: https://ollama.com/download"
  exit 1
fi
VERSION=$(ollama --version 2>/dev/null || echo "desconhecida")
ok "Ollama instalado: ${VERSION}"

# 2. Verificar serviço
info "Testando serviço em ${OLLAMA_HOST}..."
if curl -sf --max-time 5 "${OLLAMA_HOST}/api/version" &>/dev/null; then
  API_VER=$(curl -sf --max-time 5 "${OLLAMA_HOST}/api/version" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('version','?'))" 2>/dev/null || echo "?")
  ok "Serviço respondendo. API versão: ${API_VER}"
else
  warn "Serviço offline em ${OLLAMA_HOST}."
  warn "Inicie com: ollama serve   (ou abra o app Ollama)"
  SKIP_MODELS=1
fi

# 2b. Verificar bind de rede
sep
info "Verificação de bind de rede (porta 11434):"
if command -v ss &>/dev/null; then
  BIND_OUTPUT=$(ss -ltnp 2>/dev/null | grep ':11434' || echo "")
  if [[ -z "$BIND_OUTPUT" ]]; then
    warn "Porta 11434 não detectada em uso. Verifique se o serviço está ativo."
  elif echo "$BIND_OUTPUT" | grep -q '0\.0\.0\.0:11434'; then
    warn "Ollama está escutando em 0.0.0.0:11434 — acessível em interfaces externas."
    warn "Defina OLLAMA_HOST=127.0.0.1:11434 no override systemd e reinicie o serviço."
    warn "Documentação: scripts/systemd/ollama-override.conf.example"
    echo "$BIND_OUTPUT" | sed 's/^/  /'
  elif echo "$BIND_OUTPUT" | grep -qE '127\.0\.0\.1:11434|\[::1\].*:11434'; then
    ok "Ollama vinculado apenas ao loopback (127.0.0.1 ou ::1)."
    echo "$BIND_OUTPUT" | sed 's/^/  /'
  else
    info "Resultado de ss para porta 11434:"
    echo "$BIND_OUTPUT" | sed 's/^/  /'
  fi
elif command -v netstat &>/dev/null; then
  BIND_OUTPUT=$(netstat -ltnp 2>/dev/null | grep ':11434' || echo "")
  if echo "$BIND_OUTPUT" | grep -q '0\.0\.0\.0:11434'; then
    warn "Ollama está escutando em 0.0.0.0:11434 — acessível em interfaces externas."
    echo "$BIND_OUTPUT" | sed 's/^/  /'
  elif [[ -n "$BIND_OUTPUT" ]]; then
    ok "Porta 11434 detectada (netstat):"
    echo "$BIND_OUTPUT" | sed 's/^/  /'
  else
    warn "Porta 11434 não detectada. Verifique se o serviço está ativo."
  fi
else
  info "ss e netstat não disponíveis. Verifique manualmente: netstat -ltnp | grep 11434"
fi

# 3. Modelos instalados
if [[ -z "${SKIP_MODELS:-}" ]]; then
  sep
  info "Modelos instalados localmente:"
  ollama list 2>/dev/null || warn "Não foi possível listar modelos."

  CLOUD_COUNT=$(ollama list 2>/dev/null | grep -c ':cloud' || true)
  if [[ "$CLOUD_COUNT" -gt 0 ]]; then
    warn "${CLOUD_COUNT} modelo(s) com sufixo ':cloud' detectado(s). Use modelos locais para evitar erro 403."
  fi
fi

# 4. Modelos na memória
sep
info "Modelos atualmente na memória (ollama ps):"
ollama ps 2>/dev/null || warn "Não foi possível executar ollama ps."

# 5. Variáveis de ambiente do projeto
sep
info "Variáveis de ambiente relevantes:"
for VAR in AI_BACKEND OLLAMA_HOST OLLAMA_MODEL OLLAMA_NO_CLOUD OLLAMA_CONTEXT_LENGTH; do
  VAL="${!VAR:-<não definida>}"
  echo "  ${VAR}=${VAL}"
done

# 6. GPU — detectar sem presumir Nvidia
sep
info "Detecção de GPU:"

if command -v nvidia-smi &>/dev/null; then
  ok "nvidia-smi encontrado — GPU NVIDIA disponível."
  nvidia-smi --query-gpu=name,memory.total,memory.free,memory.used \
    --format=csv,noheader,nounits 2>/dev/null \
    | awk -F', ' '{printf "  Modelo: %s | Total: %s MB | Livre: %s MB | Usada: %s MB\n",$1,$2,$3,$4}'
elif command -v rocm-smi &>/dev/null; then
  ok "rocm-smi encontrado — GPU AMD disponível."
  rocm-smi --showmeminfo vram 2>/dev/null | head -10 || true
elif [[ "$(uname)" == "Darwin" ]]; then
  ok "macOS — Metal (Apple Silicon/AMD) disponível se Ollama detectar."
  system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Chipset|VRAM|Vendor" | head -6 || true
else
  warn "Nenhuma ferramenta de GPU encontrada (nvidia-smi, rocm-smi)."
  warn "Ollama usará CPU. Instale drivers e o toolkit CUDA/ROCm para usar GPU."
fi

# 7. CPU e RAM
sep
info "CPU e memória:"
CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo "?")
echo "  CPU cores: ${CPU_CORES}"
if command -v free &>/dev/null; then
  free -h | awk '/^Mem:/{printf "  RAM total: %s | usada: %s | disponível: %s\n",$2,$3,$7}'
elif [[ "$(uname)" == "Darwin" ]]; then
  MEM=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
  echo "  RAM total: $((MEM / 1073741824)) GB"
fi

# 8. Teste de inferência (opt-in)
sep
if [[ -n "$TEST_MODEL" ]]; then
  info "Teste de inferência com modelo: ${TEST_MODEL}"
  if ollama list 2>/dev/null | grep -q "^${TEST_MODEL}"; then
    RESP=$(ollama run "$TEST_MODEL" "Responda somente: teste local confirmado." 2>/dev/null || echo "")
    if [[ -n "$RESP" ]]; then
      ok "Resposta recebida: ${RESP}"
    else
      warn "Resposta vazia ou erro durante a inferência."
    fi
    echo ""
    info "ollama ps após inferência:"
    ollama ps 2>/dev/null || true
  else
    warn "Modelo '${TEST_MODEL}' não está instalado. Liste modelos com: ollama list"
    warn "Para baixar: ollama pull ${TEST_MODEL}  (verifique espaço disponível antes)"
  fi
else
  info "Teste de inferência ignorado (passe o nome do modelo como argumento para ativar)."
  info "Exemplo: $0 qwen3:4b"
fi

sep
ok "Diagnóstico concluído."
