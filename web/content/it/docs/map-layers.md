---
title: Livelli della mappa
description: La mappa ciclabile offline e le sue parti, la mappa ciclabile online e le soste, tutto nel foglio Livelli.
order: 6
---

**Livelli** sta nella colonna di pulsanti a destra della mappa, nei tab Pianifica e Registra. Il suo foglio contiene la mappa ciclabile, la mappa ciclabile online e le soste. Il pulsante è evidenziato finché una di esse è attiva.

<!-- screenshot: layers -->

## Mappa ciclabile

**Mappa ciclabile**: "Piste, corsie e itinerari ciclabili delle aree scaricate · funziona offline · visibile ingrandendo". La disegna l'app dai dati di routing sul telefono, quindi non serve connessione, e solo dove un'area è scaricata.

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
| **Salite** | Tratti ripidi delle vie che una bici può usare, come una banda: giallo dal 6 %, arancione dal 10 %, rosso dal 15 %; i chevron indicano la salita dallo zoom 15. Le quote vengono dal modello del terreno nei dati di routing. Una salita conta solo se continua per almeno 150 m e 10 m di dislivello, quindi le rampe brevi non compaiono; nei centri città con edifici alti può comunque mostrare una salita che non c'è o non vederne una. Ponti e gallerie sono esclusi. Nei centri densi delle città più grandi, dove le quote sono quelle degli edifici, non si disegnano salite. |

All'inizio sono attive tutte le parti tranne **Sterrato & sconnesso**, **Strade a senso unico**, **Strade tranquille**, **MTB** e **Salite**. Una parte aggiunta in una versione successiva parte dal suo valore predefinito; le scelte fatte prima restano.

Nella scheda Pianifica, con la mappa ciclabile attiva su un'area non scaricata, un chip dice **Nessuna mappa ciclabile qui – area non scaricata**, con **Scarica**; un tocco apre il download dell'area visibile. Se vale anche il chip delle soste, questo ha la precedenza.

## Mappa ciclabile online

**Mappa ciclabile online**: "La mappa di CyclOSM con negozi e parcheggi per bici · richiede una connessione". Il livello di CyclOSM, scaricato online. Le due mappe ciclabili si alternano: attivarne una disattiva l'altra.

## Soste

**Soste** è un interruttore nello stesso foglio, spento finché non lo attivi. Disegna acqua potabile, caffè, bagni, stazioni di riparazione bici e altro dall'indice dei luoghi sul telefono. I tipi, la zona che guardi e il percorso davanti a te sono descritti in [soste sulla mappa](./stops-on-the-map).
