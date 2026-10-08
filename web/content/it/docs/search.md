---
title: Ricerca
description: Trova luoghi, vie, numeri civici e cose come acqua potabile o bagni, sul telefono dove hai scaricato un'area e online ovunque altrove.
order: 4
---

Il campo di ricerca in alto nel tab Pianifica trova città, vie, numeri civici e punti di interesse come caffè, acqua potabile e negozi di bici. Dove hai scaricato un'area risponde dal telefono, all'istante e senza segnale; ovunque altrove interroga un geocoder online.

## Come cercare

1. Apri il tab **Pianifica** e tocca il campo in alto, con il suggerimento **Cerca un luogo**.
2. Digita almeno tre caratteri. I risultati compaiono in una scheda sotto il campo mentre scrivi.
3. Tocca un risultato.

Compare una scheda con il nome del luogo, cos'è, quanto è distante da te e, con un percorso, quanto è lontano dal percorso. La mappa si sposta sul luogo e lo segna con uno spillo. Cosa offre la scheda dipende dal piano:

- **Niente ancora pianificato**: **Percorso fin qui** va da dove sei al luogo; **Parti da qui** lo rende il primo punto del percorso.
- **Solo una partenza**: **Destinazione** lo rende la fine del percorso.
- **Un percorso**: **Aggiungi come sosta** lo inserisce nel percorso dove si trova lungo la strada; **Destinazione** lo aggiunge in fondo.

Sotto questi, **Dettagli** recupera da OpenStreetMap gli orari di apertura del luogo (e se è aperto ora), sito web, numero di telefono e simili, solo quando lo tocchi; manca per vie e luoghi senza un id OpenStreetMap. **Apri in…** mostra il luogo in un'altra app di mappe o su openstreetmap.org, oppure lo condivide.

Chiudere la scheda (la **X**, uno scorrimento verso il basso o un tocco sulla mappa) non cambia nulla e svuota la ricerca. Una sosta toccata sulla mappa apre la stessa scheda.

## Offline o online

Velorki decide in base al **centro della mappa**, non alla tua connessione. Ogni riquadro di routing scaricato porta con sé un indice di ricerca della sua area, quindi:

- se il riquadro sotto il centro della mappa ha il suo indice sul telefono, la richiesta viene risolta sul telefono;
- se non lo ha, la richiesta va online a Photon.

In fondo alla scheda dei risultati c'è esattamente una riga, e quale sia ti dice da dove vengono i risultati:

| Riga | Significa | Toccandola |
|---|---|---|
| **Cerca online "…"** | stai guardando risultati offline | esegue lo stesso testo online |
| **Mostra risultati offline** | stai guardando risultati online | esegue di nuovo lo stesso testo sul telefono |
| **Scarica quest'area per cercare offline** | quest'area non ha un indice sul telefono | apre la schermata offline per l'area visibile |

Quella riga resta visibile mentre scorri l'elenco, ed è mostrata anche sotto un messaggio di errore, dove conta di più.

## Cosa trova

- **Luoghi**: città, paesi, villaggi, frazioni, sobborghi, quartieri, località e isole.
- **Vie**, con i numeri civici.
- **Punti di interesse**, ognuno con la sua icona e la sua etichetta: Caffè, Acqua potabile, Bagni, Stazione di riparazione bici, Negozio di bici, Noleggio bici, Parcheggio bici, Ricarica e-bike, Riparo, Campeggio, Hotel, Ostello, Rifugio, Supermercato, Panetteria, Farmacia, Area picnic, Stazione, Terminal traghetti, Aeroporto, Punto panoramico, Vetta, Passo, Parco, Spiaggia, Acqua, Riserva naturale, Attrazione, Museo, Sito storico, Luogo di culto, Ospedale, Università, Impianto sportivo, Centro commerciale, Torre, Faro, Edificio.

Le righe offline mostrano il tipo, la distanza, il numero civico e la città sotto il nome, in quest'ordine, per quanto ciascuno sia noto: "Acqua potabile · 350 m", "Via · 400 · Manhattan". Una fontanella, un bagno, un riparo o una rastrelliera senza un nome proprio è elencato sotto il suo tipo.

## Cercare per tipo

Digita il nome di un tipo anziché il nome di un luogo. "acqua potabile", "panetteria", "bagni" e tutti gli altri funzionano, nella lingua in cui gira l'app.

L'elenco si apre allora con i cinque più vicini di quel tipo al centro della mappa, ognuno con la sua distanza, e sotto seguono le normali corrispondenze per nome. Velorki cerca in un'area che cresce da 5 a 50 km intorno al centro della mappa finché non ne ha abbastanza. È il modo veloce per rispondere a "dov'è la fontanella più vicina" nel mezzo di un giro.

Una ricerca per tipo ignora gli interruttori dei gruppi descritti sotto.

## Numeri civici

Metti il numero all'inizio o alla fine: "Via Roma 12", "400 W 42nd". Velorki toglie il numero, trova la via e risponde alla posizione del numero lungo di essa.

Dove l'indice contiene esattamente quel numero, la posizione è esatta. Dove il numero cade tra due che conosce, Velorki interpola e segna la riga con **≈ 400** così vedi che è una stima. Un numero in mezzo a una ricerca è trattato come parte del nome, e così anche un ordinale come "42nd".

## Errori di battitura

Se una ricerca non trova proprio nulla, Velorki prende le parole che non riconosce, trova nell'indice le parole più probabili a una o due lettere di distanza, e cerca di nuovo. La scheda dice allora **Risultati per "…"** sopra l'elenco, con ciò che ha cercato davvero.

## Ordinare i gruppi

I risultati offline sono raggruppati, e decidi tu quali gruppi compaiono e in che ordine.

1. Apri **Opzioni**.
2. Tocca **Ricerca**, con il sottotitolo "Cosa mostra la ricerca offline, e in che ordine. Trascina per cambiare la priorità."
3. Trascina una riga dalla sua maniglia per spostarla in su o in giù. Usa l'interruttore a destra per disattivare un gruppo.

Gli otto gruppi, nell'ordine predefinito: **Luoghi**, **Vie e indirizzi**, **Punti di riferimento**, **Soste in bici**, **Pernottamento**, **Natura**, **Trasporti**, **Servizi**.

Non c'è un pulsante di salvataggio; le modifiche hanno effetto al prossimo tasto premuto. Un gruppo disattivato sparisce dalle corrispondenze per nome, e l'ordine decide i pareggi tra risultati che corrispondono al testo altrettanto bene.

## Quando la ricerca non funziona

- **"Nessun risultato."** Il testo non corrisponde a nulla, né offline né online. Prova la riga in fondo per cambiare sorgente, o meno parole.
- **"Ricerca non riuscita."** con un motivo significa che il geocoder online non era raggiungibile. La ricerca offline continua a funzionare dove hai scaricato un'area.
- **"Nessun server di ricerca configurato, impostane uno in Opzioni → Avanzate."** significa che questa build non ha né un indirizzo del geocoder né alcun indice scaricato. Il campo è disabilitato finché non ne esiste uno.

## Vedi anche

- [Mappe offline e calcolo del percorso](./offline-maps-and-routing)
- [Pianificare un percorso](./planning-a-route)
- [Impostazioni e aspetto](./settings-and-appearance)
- [Privacy sul telefono](./privacy-on-the-phone)
