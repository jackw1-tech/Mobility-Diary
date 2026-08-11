"""Eccezioni di dominio condivise da tutti i bounded context.

Questo modulo e' l'unico punto in cui vive la forma comune delle eccezioni di
servizio (messaggio + status code HTTP suggerito). Prima della sua
introduzione, ogni context (mobility.services.places, mobility.services.trips,
mobility.services.reload, mobility.ingestion.services, ...) ridefiniva la
stessa classe `XxxServiceError(ValueError)` con identico `__init__` e
`status_code`: la stessa invariante ("un errore di servizio trasporta un
messaggio e uno status code") era duplicata in piu' punti (regola 5
dell'architettura a layer). Ora ogni context definisce solo le proprie
sottoclassi con lo status_code appropriato, ereditando da `ServiceError`.

Nessuna dipendenza da apps/, api/ o bff/: e' kernel puro (vedi regole shared/).
"""

from __future__ import annotations


class ServiceError(Exception):
    """Errore di dominio sollevato da un service.

    Trasporta un messaggio leggibile e uno status code HTTP suggerito per la
    presentazione (Ninja/DRF): la Response HTTP vera e propria resta
    responsabilita' del layer di presentazione, che cattura questa eccezione
    e la traduce in una risposta.
    """

    status_code: int = 400

    def __init__(self, message: str):
        super().__init__(message)
        self.message = message
