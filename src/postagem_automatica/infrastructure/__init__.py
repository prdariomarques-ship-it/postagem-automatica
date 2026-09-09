"""Camada de infraestrutura: implementações concretas das ports definidas em
application/ports.py, mais o composition root (composition.py) que as conecta.

É a única camada que conhece o SDK da Anthropic, a Graph API da Meta via
`requests`, o SDK do Twilio e `sqlite3`.
"""
