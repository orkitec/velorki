---
title: Livelli della mappa
description: La mappa ciclabile offline e le sue parti, la mappa ciclabile online, il radar pioggia, le nuvole e le soste, tutto nel foglio Livelli.
order: 6
---

**Livelli** sta nella colonna di pulsanti a destra della mappa, nei tab Pianifica e Registra. Il suo foglio contiene la mappa ciclabile, la mappa ciclabile online, il radar pioggia, le nuvole e le soste. Il pulsante è evidenziato finché una di esse è attiva.

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

## Radar pioggia e nuvole

**Radar pioggia**: "Radar in Germania e negli Stati Uniti, altrove in Europa e Africa una stima da satellite · previsione fino a 24 ore". **Nuvole**: "Europa, Africa e Americhe · ogni ora in Europa". Sono entrambi gratuiti, disattivati finché non li attivi, e richiedono una connessione.

La pioggia viene da tre tipi di fonte. Adesso: il radar del servizio meteorologico tedesco (Deutscher Wetterdienst) sopra la Germania e i dintorni e del servizio meteorologico statunitense (National Weather Service) sopra gli Stati Uniti, e intorno, sul resto dell'Europa, sull'Africa e sull'Atlantico, la pioggia stimata dal satellite Meteosat da H SAF di EUMETSAT, ogni dieci minuti. Una stima da satellite è più grossolana del radar e perde parte della pioggia debole; non viene mai disegnata sulle zone dei radar, così i due non si contraddicono mai sulla mappa. Le prossime due ore: in Germania la previsione radar del Deutscher Wetterdienst, la pioggia del radar spostata a quarti d'ora; ovunque altrove, e ovunque da tre ore in poi, la previsione del suo modello meteorologico ICON, ora per ora sull'Europa e a passi di sei ore altrove. L'app cerca immagini più recenti ogni cinque minuti.

Con il radar pioggia attivo, il suo controllo del tempo sta in cima al foglio di Pianifica e sulla scheda di Registra, sotto i valori durante un'uscita: un cursore da **Ora** a quarti d'ora fino a due ore avanti, poi a ore fino a 24 ore avanti. La sua etichetta dice il passo, l'ora dell'immagine al centro della mappa e, in avanti, che cos'è, per esempio **Ora · 20:25**, **+45 min · 21:30 · Previsione radar** o **+3 h · 23:00 · Previsione**. Il passo è lo stesso in tutti i tab e torna su **Ora** quando l'app torna dopo più di mezz'ora. La Libreria mostra l'ora in una piccola etichetta sulla mappa.

Le nuvole sono immagini satellitari disegnate in bianco sulla mappa: Meteosat di EUMETSAT sopra Europa, Africa e dintorni, con una nuova immagine a ogni ora esatta, e i satelliti GOES tramite la NASA sopra le Americhe. Mostrano sempre la loro immagine più recente, qualunque cosa dica il cursore della pioggia, e una piccola etichetta sulla mappa ne dice l'ora. Le nuvole più spesse e fredde sono le più chiare; nebbia e nuvole basse appaiono deboli o per niente.

Se un servizio non risponde, la mappa dice **Radar pioggia non disponibile al momento**, **Pioggia da satellite non disponibile al momento**, **Previsione di pioggia non disponibile al momento** o **Nuvole non disponibili al momento**, così una mappa vuota non viene scambiata per una giornata asciutta e serena. L'app carica le immagini direttamente da Deutscher Wetterdienst, NOAA, NASA ed EUMETSAT, non tramite Velorki, quindi questi servizi vedono l'area di mappa richiesta. I loro crediti sono nella riga in fondo alla mappa finché un livello è disegnato.

## Soste

**Soste** è un interruttore nello stesso foglio, spento finché non lo attivi. Disegna acqua potabile, caffè, bagni, stazioni di riparazione bici e altro dall'indice dei luoghi sul telefono. I tipi, la zona che guardi e il percorso davanti a te sono descritti in [soste sulla mappa](./stops-on-the-map).
