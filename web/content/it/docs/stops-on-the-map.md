---
title: Soste sulla mappa
description: Mostra acqua, caffè, bagni, riparazione bici e altre soste sulla mappa, nella zona che guardi o lungo il percorso davanti a te, e attiva la mappa ciclabile.
order: 5
---

Velorki può disegnare sulla mappa i luoghi dove ci si ferma durante un giro: acqua potabile, caffè, panetterie, bagni, stazioni di riparazione bici e altro. Vengono dall'indice dei luoghi dei dati di routing sul telefono, quindi serve l'area scaricata (vedi [mappe offline e calcolo del percorso](./offline-maps-and-routing)), funzionano senza segnale e non inviano nulla da nessuna parte.

## Il pulsante Livelli

**Livelli** sta nella colonna di pulsanti a destra della mappa, nei tab Pianifica e Registra. Il suo foglio contiene:

- **Mappa ciclabile**: "Piste, corsie e itinerari ciclabili delle aree scaricate · funziona offline · visibile ingrandendo". La disegna l'app dai dati di routing sul telefono, quindi non serve connessione, e solo dove un'area è scaricata. Le sue parti si aprono sotto l'interruttore, vedi [la mappa ciclabile](#la-mappa-ciclabile).
- **Mappa ciclabile online**: "La mappa di CyclOSM con negozi e parcheggi per bici · richiede una connessione". Il livello di CyclOSM, scaricato online. Le due mappe ciclabili si alternano: attivarne una disattiva l'altra.
- **Soste**, un interruttore, spento finché non lo attivi. Sotto, i tipi da mostrare, per gruppo: **Soste in bici**, **Pernottamento** e **Punti di riferimento**. Tocca un tipo per mostrarlo o nasconderlo. La prima volta sono scelti acqua potabile, caffè, panetterie, bagni e stazioni di riparazione bici. Con l'interruttore spento i tipi si richiudono; la tua scelta resta per la volta dopo.

Il pulsante è evidenziato finché la mappa ciclabile, la mappa ciclabile online o le soste sono attive.

## La mappa ciclabile

La mappa ciclabile compare in dissolvenza tra lo zoom 12 e 13, e scompare di nuovo allontanando. Disegna ciò che i dati di routing sanno dell'andare in bici. Attiva, apre sotto l'interruttore un chip per parte, ciascuno con un campione della sua linea come legenda. Tocca un chip per mostrare o nascondere la parte; la scelta resta. Frecce e punti mostrati dallo zoom 15 compaiono in dissolvenza nel passo di zoom precedente.

| Parte | Disegnata come |
| --- | --- |
| **Piste & corsie** | Piste ciclabili in blu pieno, strade ciclabili con una fascia chiara; piste in tratto pieno e corsie a trattini, al bordo della strada, più fuori sulle strade grandi. Corsie condivise (corsie bus percorribili in bici, corsie segnate solo con simboli bici, banchine, marciapiedi percorribili in bici) come trattini radi azzurri accanto alla strada. Le piste ciclabili a doppio senso e le piste e corsie a doppio senso sono disegnate più larghe di quelle a senso unico |
| **Frecce senso unico** | Chevron nel blu proprio della corsia indicano il verso di marcia: su piste ciclabili e percorsi a senso unico dallo zoom 15, e su piste e corsie a senso unico accanto alla strada da circa lo zoom 15,5 |
| **Percorsi condivisi** | Sentieri condivisi con i pedoni a trattini verde acqua, marciapiedi percorribili in bici a puntini grigio-azzurri |
| **Strade a senso unico** | Un chevron grigio al centro delle strade a senso unico anche per le bici, nel verso del traffico, dallo zoom 15. Le strade a senso unico che le bici possono percorrere in entrambi i sensi mostrano invece il segno a due colori di **Doppio senso bici**. Dove una corsia o una pista accanto alla strada mostra il proprio senso, la strada non ha un chevron suo |
| **Doppio senso bici** | Sulle strade a senso unico che le bici possono percorrere in entrambi i sensi, dallo zoom 15 un chevron grigio mostra il verso del traffico e uno blu quello delle bici contromano |
| **Itinerari nazionali**, **Itinerari regionali**, **Itinerari locali** | Itinerari ciclabili segnalati come alone viola, più forte quanto più lontano arriva l'itinerario |
| **Sterrato & sconnesso** | Ghiaia con un trattino ocra, terreno accidentato per MTB con un trattino marrone, selciato sconnesso con tacche rosse |
| **Barriere & scale** | Cancelli, paletti e scalini di attraversamento come punti dallo zoom 15; rossi dove la bici va portata a spalla. Scale come gradini marroni dallo zoom 15, con una striscia blu accanto dove c'è una rampa per bici |
| **Strade tranquille** | Strade colorate secondo la tranquillità: azzurro ciano per 30 km/h (20 mph) o meno, verde per 20 km/h o zone residenziali, verde chiaro per passo d'uomo, verde vivo senza traffico motorizzato; strade chiuse alle bici in grigio |
| **MTB** | Tacche di difficoltà sui sentieri dallo zoom 14: blu per facile (S0–S1), rosso per S2, nero per S3 e più difficile (bianco sulla mappa notturna); itinerari MTB come alone arancione |

All'inizio sono attive tutte le parti tranne **Sterrato & sconnesso**, **Strade a senso unico**, **Strade tranquille** e **MTB**. Una parte aggiunta in una versione successiva parte dal suo valore predefinito; le scelte fatte prima restano.

Nella scheda Pianifica, con la mappa ciclabile attiva su un'area non scaricata, un chip dice **Nessuna mappa ciclabile qui – area non scaricata**, con **Scarica**; un tocco apre il download dell'area visibile. Se vale anche il chip delle soste, questo ha la precedenza.

## Nella zona che guardi

Con **Soste** attivo, le soste nella parte di mappa visibile compaiono dallo zoom 11 in poi. Più lontano, le soste vicine sono raccolte in bolle con un numero; dallo zoom 15 si separano in soste singole con le loro icone. Tocca una bolla per ingrandire fino a dove si separa.

Ancora più lontano, un chip dice **Ingrandisci per vedere le soste**; toccalo e la mappa ingrandisce fino a dove si vedono.

Dove l'area non è scaricata, il chip dice invece **Nessuna sosta qui – area non scaricata**, con **Scarica**; un tocco apre il download dell'area visibile.

## Lungo il percorso davanti a te

Con un percorso scelto sotto **Segui un percorso** nel tab Registra, le soste sono quelle entro 300 m dalla parte di percorso ancora davanti a te, fino a 50 km, a qualsiasi zoom. Una riga sopra la mappa elenca la prossima di ogni tipo con la sua distanza lungo il percorso, "Acqua potabile · 2,4 km"; tocca una voce per vedere la sosta sulla mappa. Mentre la mappa ti segue durante un giro, resta con te e la sosta viene solo evidenziata.

Quando nulla dei prossimi 50 km del percorso è scaricato, lo stesso chip prende il posto di quella riga.

**Lungo il percorso** e **In questa zona** nel foglio Livelli passano dall'una all'altra.

## Tocca una sosta

Una sosta apre la sua scheda del luogo, la stessa che apre un risultato di ricerca: nome, tipo, città, quanto è distante da te e, con un percorso, quanto è lontana da esso. Nel tab Pianifica offre cosa fare del luogo, **Percorso fin qui**, **Parti da qui**, **Aggiungi come sosta** o **Destinazione**; nel tab Registra informa soltanto. **Dettagli** e **Apri in…** ci sono in entrambi. Vedi [la scheda del luogo](./search#la-scheda-del-luogo).

## Vedi anche

- [Ricerca](./search)
- [Pianificare un percorso](./planning-a-route)
- [Navigazione svolta per svolta](./navigation)
- [Mappe offline e calcolo del percorso](./offline-maps-and-routing)
