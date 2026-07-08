"""Publica o conteúdo nas plataformas: Facebook, Instagram e WhatsApp."""
import os

import requests

GRAPH = "https://graph.facebook.com/v21.0"


def publicar_facebook(texto: str) -> str:
    """Publica um post de texto na Página do Facebook."""
    page_id = os.environ["META_PAGE_ID"]
    r = requests.post(
        f"{GRAPH}/{page_id}/feed",
        data={"message": texto, "access_token": os.environ["META_ACCESS_TOKEN"]},
        timeout=30,
    )
    r.raise_for_status()
    return r.json()["id"]


def publicar_instagram(texto: str, imagem_url: str) -> str:
    """Publica no Instagram (exige uma imagem hospedada em URL pública)."""
    ig_user = os.environ["META_IG_USER_ID"]
    token = os.environ["META_ACCESS_TOKEN"]

    r = requests.post(
        f"{GRAPH}/{ig_user}/media",
        data={"image_url": imagem_url, "caption": texto, "access_token": token},
        timeout=30,
    )
    r.raise_for_status()
    creation_id = r.json()["id"]

    r = requests.post(
        f"{GRAPH}/{ig_user}/media_publish",
        data={"creation_id": creation_id, "access_token": token},
        timeout=30,
    )
    r.raise_for_status()
    return r.json()["id"]


def enviar_whatsapp(texto: str) -> list[str]:
    """Envia o texto para os destinos configurados via Twilio."""
    from twilio.rest import Client

    tw = Client(os.environ["TWILIO_ACCOUNT_SID"], os.environ["TWILIO_AUTH_TOKEN"])
    origem = os.environ["TWILIO_WHATSAPP_FROM"]
    destinos = os.environ["WHATSAPP_DESTINOS"].split(",")

    sids = []
    for destino in destinos:
        msg = tw.messages.create(body=texto, from_=origem, to=destino.strip())
        sids.append(msg.sid)
    return sids
