"""Agendador principal: gera conteúdo com IA e publica nos horários definidos."""
import os
import time

import schedule
from dotenv import load_dotenv

load_dotenv()

from gerador import gerar_post  # noqa: E402
from publicadores import enviar_whatsapp, publicar_facebook  # noqa: E402


def executar_postagem():
    print("Gerando conteúdo...")
    texto = gerar_post()
    print(f"Conteúdo gerado:\n{texto}\n")

    try:
        post_id = publicar_facebook(texto)
        print(f"✅ Facebook: {post_id}")
    except Exception as e:
        print(f"❌ Facebook falhou: {e}")

    try:
        sids = enviar_whatsapp(texto)
        print(f"✅ WhatsApp: {len(sids)} mensagem(ns) enviada(s)")
    except Exception as e:
        print(f"❌ WhatsApp falhou: {e}")


def main():
    horarios = os.environ.get("HORARIOS_POSTAGEM", "08:00").split(",")
    for h in horarios:
        schedule.every().day.at(h.strip()).do(executar_postagem)
        print(f"Postagem agendada para {h.strip()}")

    print("Agendador rodando. Ctrl+C para parar.")
    while True:
        schedule.run_pending()
        time.sleep(30)


if __name__ == "__main__":
    if os.environ.get("POSTAR_AGORA") == "1":
        executar_postagem()
    else:
        main()
