"""Registry Pattern: decide quais Publishers participam do fluxo de postagem.

Adicionar um canal novo (ex: Instagram assim que houver pipeline de imagem, ou
um canal futuro do Dario OS) significa registrar um Publisher aqui — o caso de
uso (application/use_cases.py) nunca precisa mudar (Open/Closed Principle).
"""
from __future__ import annotations

from ..application.ports import Publisher
from .config import Settings
from .publishers.facebook_publisher import FacebookPublisher
from .publishers.whatsapp_publisher import WhatsAppPublisher


class PublisherRegistry:
    def __init__(self) -> None:
        self._publishers: list[Publisher] = []

    def registrar(self, publisher: Publisher) -> "PublisherRegistry":
        self._publishers.append(publisher)
        return self

    def todos(self) -> list[Publisher]:
        return list(self._publishers)

    @classmethod
    def padrao(cls, settings: Settings) -> "PublisherRegistry":
        """Monta o registry com os canais ativos hoje: Facebook e WhatsApp.

        Instagram fica de fora deliberadamente — ver publishers/instagram_publisher.py.
        """
        registry = cls()
        registry.registrar(
            FacebookPublisher(page_id=settings.meta_page_id, access_token=settings.meta_access_token)
        )
        registry.registrar(
            WhatsAppPublisher(
                account_sid=settings.twilio_account_sid,
                auth_token=settings.twilio_auth_token,
                remetente=settings.twilio_whatsapp_from,
                destinos=settings.whatsapp_destinos,
            )
        )
        return registry
