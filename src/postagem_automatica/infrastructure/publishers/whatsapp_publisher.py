"""Adapter do Publisher para WhatsApp via Twilio."""
from __future__ import annotations

from twilio.rest import Client

from ...domain.entities import Canal, Post
from ..retry import retry_twilio


class WhatsAppPublisher:
    """Envia o post para cada destino configurado.

    Uma falha em um destino não descarta o sucesso dos demais: a versão
    anterior deixava a exceção do primeiro destino que falhasse subir e perdia
    os SIDs de mensagens já enviadas com sucesso. Aqui o resultado reporta
    sucesso total, falha total (levanta exceção) ou sucesso parcial (retorna
    string descrevendo o que passou e o que falhou, para ficar auditável).
    """

    canal = Canal.WHATSAPP

    def __init__(self, account_sid: str, auth_token: str, remetente: str, destinos: tuple[str, ...]) -> None:
        self._client = Client(account_sid, auth_token)
        self._remetente = remetente
        self._destinos = destinos

    def publicar(self, post: Post) -> str:
        sids: list[str] = []
        erros: list[str] = []
        for destino in self._destinos:
            try:
                sids.append(self._enviar_um(post.texto, destino))
            except Exception as exc:
                erros.append(f"{destino}: {exc}")

        if erros and not sids:
            raise RuntimeError("; ".join(erros))
        if erros:
            return f"parcial: {len(sids)}/{len(self._destinos)} enviados; falhas: {'; '.join(erros)}"
        return ",".join(sids)

    @retry_twilio
    def _enviar_um(self, texto: str, destino: str) -> str:
        mensagem = self._client.messages.create(body=texto, from_=self._remetente, to=destino.strip())
        return mensagem.sid
