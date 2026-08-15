#!/usr/bin/env bash
# probe_ollama_from_external_host.sh — Sonda externa da porta Ollama.
#
# Execute em uma MÁQUINA DIFERENTE da VM do Ollama — nunca dentro da própria VM.
# Testa se TCP/<porta> aceita conexão do exterior.
#
# Saída:
#   "OK: TCP/<porta> não aceitou conexão"    → RC=0  (esperado)
#   "FALHA: porta <porta> aberta externamente" → RC=1  (problema de segurança)
#
# Uso: bash probe_ollama_from_external_host.sh <host-ou-ip> [porta]
#   <host-ou-ip>  IP público ou DNS da VM do Ollama
#   [porta]       padrão: 11434

set -uo pipefail

TARGET="${1:-}"
PORT="${2:-11434}"
TIMEOUT=5

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✔${NC} $*"; }
fail() { echo -e "${RED}✖${NC} $*"; }
info() { echo -e "${CYAN}→${NC} $*"; }
sep()  { echo -e "${CYAN}────────────────────────────────────────────────${NC}"; }

if [[ -z "$TARGET" ]]; then
  echo "Uso: $0 <host-ou-ip-da-vm> [porta]" >&2
  echo "Exemplo: $0 203.0.113.42 11434" >&2
  echo "" >&2
  echo "ATENÇÃO: Execute esta sonda em uma máquina EXTERNA à VM do Ollama." >&2
  exit 1
fi

# Rejeitar alvos de loopback — a sonda não tem sentido a partir do próprio host
if [[ "$TARGET" =~ ^(127\.|localhost$|::1$) ]]; then
  echo "ERRO: '$TARGET' é um endereço de loopback." >&2
  echo "Execute esta sonda a partir de outra máquina ou rede." >&2
  exit 1
fi

sep
info "probe_ollama_from_external_host"
info "Alvo : ${TARGET}:${PORT}"
info "Timeout: ${TIMEOUT}s"
sep
echo ""

# Tentativa 1: nc (netcat) — preferido por ser leve
if command -v nc &>/dev/null; then
  info "Método: nc (netcat)"
  if nc -z -w "${TIMEOUT}" "${TARGET}" "${PORT}" 2>/dev/null; then
    fail "FALHA: porta ${PORT} aberta externamente em ${TARGET}."
    echo ""
    echo "A API do Ollama está acessível pela rede pública."
    echo "Ações imediatas:"
    echo "  1. Na VM: defina OLLAMA_HOST=127.0.0.1:${PORT} no override systemd."
    echo "  2. Na VM: sudo systemctl restart ollama"
    echo "  3. No provedor cloud: remova a regra de entrada para TCP/${PORT}."
    echo "  4. Se UFW ativo: sudo ufw deny ${PORT}"
    echo "  5. Reexecute esta sonda para confirmar o fechamento."
    exit 1
  else
    ok "OK: TCP/${PORT} não aceitou conexão em ${TARGET}."
    echo ""
    info "Verifique também no painel do provedor cloud que TCP/${PORT} está"
    info "ausente das regras de entrada do security group / firewall."
    exit 0
  fi
fi

# Tentativa 2: curl (fallback — HTTP GET para detectar se porta responde)
if command -v curl &>/dev/null; then
  info "Método: curl (nc não disponível)"
  HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" \
    --connect-timeout "${TIMEOUT}" --max-time "${TIMEOUT}" \
    "http://${TARGET}:${PORT}/api/version" 2>/dev/null || echo "000")

  if [[ "$HTTP_CODE" == "000" ]]; then
    ok "OK: TCP/${PORT} não aceitou conexão em ${TARGET} (curl: sem resposta)."
    echo ""
    info "Verifique também no painel do provedor cloud que TCP/${PORT} está"
    info "ausente das regras de entrada do security group / firewall."
    exit 0
  else
    fail "FALHA: porta ${PORT} aberta externamente em ${TARGET} (HTTP ${HTTP_CODE})."
    echo ""
    echo "A API do Ollama está acessível pela rede pública."
    echo "Ações imediatas (na VM):"
    echo "  1. OLLAMA_HOST=127.0.0.1:${PORT} no override systemd e reiniciar."
    echo "  2. Remover regra de entrada TCP/${PORT} no painel do provedor cloud."
    exit 1
  fi
fi

# Tentativa 3: Python (último recurso)
if command -v python3 &>/dev/null; then
  info "Método: python3 socket (nc e curl não disponíveis)"
  RESULT=$(python3 - <<EOF 2>/dev/null
import socket, sys
s = socket.socket()
s.settimeout(${TIMEOUT})
try:
    s.connect(("${TARGET}", ${PORT}))
    s.close()
    print("open")
except (ConnectionRefusedError, TimeoutError, OSError):
    print("closed")
EOF
)
  if [[ "$RESULT" == "open" ]]; then
    fail "FALHA: porta ${PORT} aberta externamente em ${TARGET}."
    exit 1
  else
    ok "OK: TCP/${PORT} não aceitou conexão em ${TARGET}."
    exit 0
  fi
fi

echo "ERRO: nc, curl e python3 não estão disponíveis. Instale um deles para executar a sonda." >&2
exit 1
