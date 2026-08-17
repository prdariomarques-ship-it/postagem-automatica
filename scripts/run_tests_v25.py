# -*- coding: utf-8 -*-
# run_tests_v25.py — executa os 3 testes V2.5 em sequencia no Windows
# Alvo: http://127.0.0.1:11434 (exclusivo) · PowerShell 5.1 · sem cloud
#
# Uso:
#   python run_tests_v25.py
#   python run_tests_v25.py --skip-cancel   (pula a bateria de cancelamento)
#
# Dependencias: nenhuma externa (apenas stdlib: subprocess, json, datetime, sys)
# O script detecta os .ps1 na mesma pasta e tambem na pasta
# Default Project\Ollama-Local-Portatil se nao encontrar localmente.
#
# Saida: resumo em tela + relatorio JSON em relatorio_v25_<timestamp>.json
#        e log texto em run_tests_v25.log

from __future__ import print_function
import datetime
import json
import os
import subprocess
import sys

PS_EXE = "powershell.exe"
BASE_FLAGS = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File"]

TESTES = [
    ("teste_v25_api.ps1", "Teste de API e metricas (versao, vision, tok/s, bloqueio :cloud)"),
    ("teste_cancelamento.ps1", "Bateria de cancelamento Abort() em 4 cenarios"),
    ("teste_troca_modelo.ps1", "Benchmark troca de modelo (Sleep vs /api/ps)"),
]


def localizar_scripts():
    """Procura os .ps1 na pasta do script e na pasta padrao do usuario."""
    pasta_script = os.path.dirname(os.path.abspath(__file__))
    pastas = [pasta_script]
    user = os.environ.get("USERPROFILE", "")
    if user:
        pastas.append(os.path.join(user, "OneDrive", "Documents", "Default Project", "Ollama-Local-Portatil"))
        pastas.append(os.path.join(user, "Documents", "Default Project", "Ollama-Local-Portatil"))
    encontrados = {}
    for nome, _ in TESTES:
        achou = None
        for p in pastas:
            caminho = os.path.join(p, nome)
            if os.path.isfile(caminho):
                achou = caminho
                break
        if not achou:
            achou = os.path.join(pasta_script, nome)
        encontrados[nome] = achou
    return encontrados


def rodar(nome, caminho):
    """Executa um teste e retorna (ok, retorno, duracao_seg, resumo)."""
    inicio = datetime.datetime.now()
    try:
        proc = subprocess.Popen(
            [PS_EXE] + BASE_FLAGS + [caminho],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            encoding="utf-8",
            errors="replace",
        )
        saida, _ = proc.communicate(timeout=900)
        dur = (datetime.datetime.now() - inicio).total_seconds()
        retorno = proc.returncode
    except subprocess.TimeoutExpired:
        proc.kill()
        saida = "TIMEOUT: teste excedeu 15 minutos"
        dur = (datetime.datetime.now() - inicio).total_seconds()
        retorno = -1
    except OSError as e:
        saida = "ERRO AO EXECUTAR: %s" % e
        dur = (datetime.datetime.now() - inicio).total_seconds()
        retorno = -1
    # Conta os PASS/FAIL reportados pelo proprio teste
    n_pass = saida.upper().count("PASS")
    n_fail = saida.upper().count("FAIL")
    ok = (retorno == 0) and (n_fail == 0)
    return ok, retorno, round(dur, 1), saida


def checar_ollama():
    """Confere se o servico Ollama responde antes de comecar."""
    try:
        import urllib.request
        req = urllib.request.Request("http://127.0.0.1:11434/api/version", method="GET")
        with urllib.request.urlopen(req, timeout=5) as r:
            versao = r.read().decode("utf-8").strip()
        return True, versao
    except Exception as e:
        return False, str(e)


def main():
    pular_cancelamento = "--skip-cancel" in sys.argv

    print("=" * 70)
    print("run_tests_v25.py — execucao automatica dos testes V2.5")
    print("=" * 70)

    ok, versao = checar_ollama()
    print("[prereq] Ollama em 127.0.0.1:11434: ", "OK (%s)" % versao if ok else "FORA DO AR — %s" % versao)
    if not ok:
        print("Aviso: rode 'ollama serve' ou abra o Ollama Desktop antes de continuar.")
        resp = input("Continuar mesmo assim? (s/n): ").strip().lower()
        if resp != "s":
            sys.exit(1)

    testes = [t for t in TESTES if not (pular_cancelamento and t[0] == "teste_cancelamento.ps1")]
    scripts = localizar_scripts()

    resultados = []
    print()
    for nome, titulo in testes:
        print("-" * 70)
        print("[exec] %s — %s" % (nome, titulo))
        caminho = scripts[nome]
        existe = os.path.isfile(caminho)
        print("[exec] arquivo: %s (%s)" % (caminho, "encontrado" if existe else "NAO ENCONTRADO"))
        if not existe:
            resultados.append({
                "script": nome,
                "titulo": titulo,
                "status": "NAO ENCONTRADO",
                "retorno": -1,
                "duracao_seg": 0,
                "saida": "Arquivo nao encontrado. Baixe do GitHub:\n"
                         "https://raw.githubusercontent.com/prdariomarques-ship-it/"
                         "postagem-automatica/claude/ollama-local-cloud-setup-fpahf0/scripts/" + nome,
            })
            continue
        ok_r, retorno, dur, saida = rodar(nome, caminho)
        status = "PASS" if ok_r else "FAIL"
        print("[exec] resultado: %s (returncode %s, %.1f s)" % (status, retorno, dur))
        # mostra as ultimas 12 linhas do teste na tela
        linhas = [l for l in saida.splitlines() if l.strip()]
        for l in linhas[-12:]:
            print("       | %s" % l[:160])
        resultados.append({
            "script": nome,
            "titulo": titulo,
            "status": status,
            "retorno": retorno,
            "duracao_seg": dur,
            "saida": saida,
        })

    # resumo
    n_pass = sum(1 for r in resultados if r["status"] == "PASS")
    total = len(resultados)
    print()
    print("=" * 70)
    print("RESUMO: %d/%d PASS — %s" % (n_pass, total, "TUDO OK" if n_pass == total else "HOUVE FALHAS"))
    for r in resultados:
        print("  [%s] %s (%.1f s)" % (r["status"], r["script"], r["duracao_seg"]))
    print("=" * 70)

    # relatorio em arquivo (saida completa preservada, sem o rodape repetido)
    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    base_rel = os.path.join(os.path.dirname(os.path.abspath(__file__)), "relatorio_v25_%s.json" % ts)
    with open(base_rel, "w", encoding="utf-8") as f:
        json.dump(resultados, f, ensure_ascii=False, indent=2)
    print("[rel] relatorio JSON: %s" % base_rel)

    log = os.path.join(os.path.dirname(os.path.abspath(__file__)), "run_tests_v25.log")
    with open(log, "a", encoding="utf-8") as f:
        f.write("%s RESUMO %d/%d PASS\n" % (datetime.datetime.now().isoformat(), n_pass, total))
    print("[rel] log: %s" % log)

    sys.exit(0 if n_pass == total else 2)


if __name__ == "__main__":
    main()
