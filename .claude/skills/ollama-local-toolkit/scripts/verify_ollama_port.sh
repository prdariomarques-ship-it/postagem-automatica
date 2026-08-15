#!/usr/bin/env bash
# verify_ollama_port.sh — Verifica segurança do bind da porta Ollama.
#
# Falha (RC=1) se encontrar 0.0.0.0 ou [::] escutando na porta.
# Retorna RC=2 se houver avisos a revisar (mas sem falha de segurança).
# Retorna RC=0 se aprovado sem ressalvas.
#
# Uso: bash verify_ollama_port.sh [porta]
#   porta  padrão: 11434

set -uo pipefail

PORT="${1:-11434}"
HOST_LOOPBACK="http://127.0.0.1:${PORT}"
WARNINGS=0
FAILURES=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✔${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; WARNINGS=$((WARNINGS + 1)); }
fail() { echo -e "${RED}✖${NC} $*"; FAILURES=$((FAILURES + 1)); }
info() { echo -e "${CYAN}→${NC} $*"; }
sep()  { echo -e "${CYAN}────────────────────────────────────────────────${NC}"; }

sep
info "verify_ollama_port — verificação de segurança da porta ${PORT}"
sep

# 1. Verificar bind da porta
echo ""
info "[1] Bind de rede (porta ${PORT}):"
BIND_OUTPUT=""
if command -v ss &>/dev/null; then
  BIND_OUTPUT=$(ss -ltnp 2>/dev/null | grep ":${PORT}" || echo "")
elif command -v netstat &>/dev/null; then
  BIND_OUTPUT=$(netstat -ltnp 2>/dev/null | grep ":${PORT}" || echo "")
fi

if [[ -z "$BIND_OUTPUT" ]]; then
  warn "Porta ${PORT} não encontrada em uso — serviço pode estar inativo."
else
  if echo "$BIND_OUTPUT" | grep -qE "0\.0\.0\.0:${PORT}|\[::\]:${PORT}|0\.0\.0\.0:\*"; then
    fail "Porta ${PORT} exposta em 0.0.0.0 ou [::] — acessível em interfaces externas."
    fail "Corrija: defina OLLAMA_HOST=127.0.0.1:${PORT} no override systemd e reinicie."
    echo "$BIND_OUTPUT" | sed 's/^/  /'
  elif echo "$BIND_OUTPUT" | grep -qE "127\.0\.0\.1:${PORT}|\[::1\]:${PORT}"; then
    ok "Porta ${PORT} vinculada apenas ao loopback."
    echo "$BIND_OUTPUT" | sed 's/^/  /'
  else
    warn "Estado de bind indeterminado — revise manualmente:"
    echo "$BIND_OUTPUT" | sed 's/^/  /'
  fi
fi

# 2. Testar endpoint de loopback
echo ""
info "[2] Endpoint de loopback (${HOST_LOOPBACK}/api/version):"
if command -v curl &>/dev/null; then
  HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 \
    "${HOST_LOOPBACK}/api/version" 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" == "200" ]]; then
    ok "API respondeu com HTTP 200 em ${HOST_LOOPBACK}."
  elif [[ "$HTTP_CODE" == "000" ]]; then
    warn "API não respondeu em ${HOST_LOOPBACK} — serviço pode estar inativo."
  else
    warn "API respondeu HTTP ${HTTP_CODE} (esperado 200)."
  fi
else
  warn "curl não disponível; teste de loopback ignorado."
fi

# 3. Inspecionar regras UFW
echo ""
info "[3] Regras UFW (se disponível):"
if command -v ufw &>/dev/null; then
  UFW_STATUS=$(sudo ufw status numbered 2>/dev/null || true)
  if echo "$UFW_STATUS" | grep -q "Status: active"; then
    ok "UFW ativo."
    UFW_RULES=$(echo "$UFW_STATUS" | grep "${PORT}" || echo "")
    if [[ -n "$UFW_RULES" ]]; then
      info "Regras UFW para porta ${PORT}:"
      echo "$UFW_RULES" | sed 's/^/  /'
      if echo "$UFW_RULES" | grep -qiE "ALLOW IN.*${PORT}|${PORT}.*ALLOW"; then
        warn "UFW possui regra ALLOW para ${PORT} — verifique se restringe à interface loopback."
      fi
    else
      ok "Nenhuma regra UFW explícita para porta ${PORT} (bloqueio padrão se UFW ativo)."
    fi
  else
    warn "UFW inativo ou não configurado."
  fi
else
  info "UFW não disponível neste sistema."
fi

# 4. Inspecionar publicações Docker
echo ""
info "[4] Publicações Docker (se disponível):"
if command -v docker &>/dev/null; then
  DOCKER_PORTS=$(docker ps --format "{{.Ports}}" 2>/dev/null | grep "${PORT}" || echo "")
  if [[ -n "$DOCKER_PORTS" ]]; then
    warn "Docker expõe porta ${PORT}:"
    echo "$DOCKER_PORTS" | sed 's/^/  /'
    warn "Garanta que o mapeamento seja 127.0.0.1:${PORT}:${PORT}, não 0.0.0.0:${PORT}:${PORT}."
  else
    ok "Nenhum container Docker expõe a porta ${PORT}."
  fi
else
  info "Docker não disponível neste sistema."
fi

# 5. Resultado final
sep
echo ""
if [[ "$FAILURES" -gt 0 ]]; then
  fail "Resultado: REPROVADO — ${FAILURES} problema(s) de segurança/saúde detectado(s)."
  echo ""
  echo "Ações recomendadas:"
  echo "  1. Defina OLLAMA_HOST=127.0.0.1:${PORT} no override systemd."
  echo "  2. Reinicie: sudo systemctl restart ollama"
  echo "  3. Verifique: ss -ltnp | grep ':${PORT}'"
  echo "  4. Reexecute este script."
  exit 1
elif [[ "$WARNINGS" -gt 0 ]]; then
  warn "Resultado: APROVADO COM AVISOS — ${WARNINGS} item(ns) a revisar."
  exit 2
else
  ok "Resultado: APROVADO — porta ${PORT} segura e API respondendo."
  exit 0
fi
