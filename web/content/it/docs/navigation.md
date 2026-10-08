---
title: Navigazione svolta per svolta
description: Segui un percorso mentre registri, con un banner di svolta e indicazioni vocali, e scopri cosa fa Velorki quando lasci il percorso.
order: 6
---

Velorki ti guida lungo un percorso mentre un giro è in registrazione: un banner sopra la mappa mostra la prossima svolta, e una voce la dice ad alta voce. Attiva gli interruttori della navigazione, scegli un percorso da seguire nel tab Registra e avvia il giro.

La navigazione è gratuita, funziona offline dove hai scaricato i dati di routing, e non richiede un account.

## Attivarla

Le impostazioni stanno in due posti contemporaneamente, e sono la stessa impostazione in entrambi: in **Opzioni → Navigazione**, e nel pannello del tab Registra sotto **Schermo sempre acceso**.

1. **Indicazioni di svolta**, "Mostra la prossima svolta mentre registri lungo un percorso". È l'interruttore principale; il resto è in grigio finché è spento.
2. **Voce**, "Annuncia le svolte a voce".
3. **Quando esci dal percorso**: **Guidami al percorso**, **Nuovo percorso alla destinazione** o **Nessun ricalcolo**. Vedi [quando lasci il percorso](#quando-lasci-il-percorso).

Poi nel tab **Registra** scegli qualcosa sotto **Segui un percorso**: **Il percorso nella scheda Pianifica** se il pianificatore contiene un percorso, oppure un percorso qualsiasi dalla tua libreria. Avvia il giro e il banner compare.

## Il banner di svolta

Una pillola lungo il bordo superiore della mappa, sopra i controlli della mappa. Da sinistra a destra: una freccia per la svolta, la distanza a cui si trova in cifre grandi, e l'istruzione.

Le istruzioni sono: **Svolta a sinistra**, **Svolta a destra**, **Svolta leggermente a sinistra**, **Svolta leggermente a destra**, **Svolta tutto a sinistra**, **Svolta tutto a destra**, **Tieni la sinistra**, **Tieni la destra**, **Fai inversione**, **Alla rotonda, prendi l'uscita 3**, **Prendi l'uscita a sinistra**, **Prendi l'uscita a destra**, **Prosegui dritto** e **Arrivo a destinazione**.

Quando una seconda svolta segue subito dopo la prima, una piccola freccia grigia per essa sta in fondo alla pillola.

Un percorso importato con un elenco svolte mostra invece le parole dell'autore per una svolta, "Turn left onto Main Street", e la voce dice anche quelle.

Un punto di interesse sul percorso, una fontanella o una zona in cui scendere dalla bici da un file importato, prende il banner quando è più vicino della prossima svolta ed entro 300 m: la sua icona, la distanza e il nome, un pericolo come "Attenzione: …" nel colore di avviso. La voce lo annuncia una volta, con lo stesso anticipo di una svolta, "Tra 100 metri, attenzione: start dismount zone". Vedi [sensori e il tuo orologio](./sensors-and-watch) per cosa arriva all'orologio, e [importare ed esportare](./import-and-export) per da dove vengono i punti.

Alla fine del percorso il banner diventa verde e dice **Destinazione raggiunta**.

## La voce

Con **Voce** attiva, ogni svolta viene annunciata una volta mentre ti avvicini e un'altra alla svolta: "Tra 200 metri, svolta a sinistra", poi "Ora svolta a sinistra". Due svolte vicine vengono dette come un'unica indicazione, "svolta a sinistra, poi svolta a destra". Con le unità imperiali: "Tra 500 piedi", "Tra un quarto di miglio", "Tra mezzo miglio", "Tra un miglio".

**Annuncio svolte** in Opzioni → Navigazione stabilisce quanto in anticipo: il cursore è in secondi, e il suggerimento dice "12 secondi prima della svolta alla tua velocità, mai a meno di 50 metri". Poiché conta i secondi anziché i metri, l'indicazione arriva nello stesso momento sia che tu stia arrancando in salita sia che tu stia volando in discesa.

Il banner porta anche un pulsante **silenzia** mentre Voce è attiva. Mette a tacere la voce **solo per il resto di questo giro** e non tocca la tua impostazione; il giro successivo parte con l'audio attivo.

## Scegliere una voce

1. **Opzioni → Navigazione → Voce guida**.
2. La prima riga è **Predefinita di sistema**, "La voce del telefono per la tua lingua". Sotto c'è ogni voce installata sul telefono, con nomi come "Voce femminile 2 (Regno Unito)".
3. Tocca una riga per sceglierla. Mentre lo fai, pronuncia un esempio.
4. Tocca **Ascolta** su qualsiasi riga per ascoltarla senza sceglierla.

Due cose che vale la pena sapere:

- **Voci che hanno bisogno di internet.** Alcuni telefoni offrono voci generate su un server. Sono nascoste finché non attivi **Mostra voci online** in fondo, e ognuna è segnata con **Richiede internet**. Velorki avvisa: "Una voce con il simbolo della nuvola viene generata online. Senza segnale la svolta non viene annunciata o arriva in ritardo. Per i giri, preferisci una voce salvata sul telefono."
- **Su un iPhone con la sola voce compatta**, Velorki mostra **Voci migliori, basta scaricarle** e ti accompagna: Impostazioni → Accessibilità → Contenuto letto → Voci → la tua lingua → tocca la nuvoletta accanto a una voce Avanzata o Premium. Dopo, l'app sceglie da sola la voce migliore sul telefono.

Se il telefono non ha alcuna voce per la tua lingua: "Nessuna voce installata per la tua lingua. Aggiungine una nelle impostazioni del telefono, sotto sintesi vocale o Contenuto letto."

## Quando lasci il percorso

La maggior parte delle svolte sbagliate si rimedia entro un isolato, quindi non succede nulla nel momento in cui ti allontani.

A circa **75 metri** dal percorso, per due posizioni di fila o circa otto secondi, il banner diventa arancione: **Torna sul percorso, alla tua sinistra**, con la distanza dal punto più vicino del percorso ancora davanti a te. Fin qui succede in ogni modalità, e non costa alcun calcolo.

Cosa succede dopo è la scelta sotto **Quando esci dal percorso**. L'attesa è la stessa per entrambe le modalità che calcolano: circa **tre quarti di minuto fuori percorso, o 150 metri da dove l'hai lasciato**, e mai prima di 15 secondi, così una raffica di posizioni sbagliate non costa nulla. **Tocca il banner** per saltare l'attesa.

### Guidami indietro

La modalità predefinita. Il tuo piano non viene mai sostituito. Velorki calcola una via per tornarci, verso un punto **davanti** a te: prova 300 metri, 800 metri e 2 chilometri più avanti lungo il piano, contati da dove sei arrivato accanto a esso e non da dove l'hai lasciato, e prende la prima che non sia una deviazione assurda e non ti mandi contromano in un senso unico, su un marciapiede o indietro da dove sei venuto. La via di ritorno è disegnata come una linea a sé con un suo colore, con il piano ancora sulla mappa, e il banner e la voce la seguono. Una volta di nuovo sul piano, la via di ritorno sparisce senza una parola e le svolte del piano riprendono.

Se invece vai per la tua strada, la via di ritorno viene ricalcolata, ma solo quando sei a **300 metri** da dove è stata calcolata l'ultima, e mai verso un punto prima dell'ultimo: avanza con te invece di richiamarti indietro, e un minuto di pedalata è il massimo che chiederà al router. Non rinuncia mai al piano e non pianifica un nuovo percorso da sola.

### Nuovo percorso alla destinazione

Quando lasci il percorso, Velorki ripianifica da dove sei fino alla destinazione, passando per le soste che non hai ancora raggiunto, e quello diventa il percorso per il resto del giro. Il vecchio piano resta sulla mappa, sbiadito. Lascia anche il nuovo percorso e ripianifica di nuovo, una volta che sei a 300 metri da dove l'ha fatto l'ultima volta, così non può girare in cerchio.

### Non ricalcolare

Solo il banner arancione, con la distanza dal percorso e la direzione per tornarci. Velorki non chiede nulla al router, e toccare il banner non fa nulla.

### Mentre sei fuori percorso

Il banner dice **Ricalcolo…** mentre viene calcolata una via di ritorno o un nuovo percorso, e **Percorso ricalcolato** quando arriva un nuovo percorso. **Nuovo percorso da qui**, un pulsante accanto al banner arancione, pianifica subito da dove sei alla destinazione, qualunque sia l'impostazione.

Tutte le distanze sopra crescono con la qualità del tuo segnale GPS, più o meno raddoppiando con la precisione riportata, così un telefono sotto gli alberi non continua a dichiarare che hai perso la strada. Smettono di crescere a 100 metri di precisione, così un telefono che ha perso del tutto il cielo non può disattivare il rilevamento del fuori percorso.

## La mappa durante la navigazione

- Il pulsante bussola sulla mappa alterna tra **Nord in alto** e **La mappa gira con te**. La tua scelta viene ricordata per il giro successivo.
- La tua posizione sta nella parte di mappa sopra il pannello: al centro con il nord in alto, in basso quando la mappa gira con te, così la maggior parte di ciò che si vede è la strada davanti.
- La mappa mantiene lo zoom che imposti con due dita mentre ti segue, da qualche chilometro a un singolo isolato; solo trascinarla interrompe l'inseguimento.
- **Mostra la mia posizione** riprende a seguirti dopo che hai spostato la mappa, al consueto zoom a livello di strada.
- Mentre sei sul percorso il segnaposto della posizione è disegnato sul percorso e orientato lungo di esso, invece di vagare con il segnale.
- Anche i punti del percorso sono sulla mappa: la partenza, la destinazione con la sua bandierina, ogni sosta con un nome o un tipo, e i luoghi accanto al percorso. Un punto che dà solo forma alla linea è omesso. Le soste che hai superato sbiadiscono, e restano sbiadite se torni indietro. Dopo un nuovo percorso alla destinazione, i segnaposto sono ancora quelli del tuo percorso.

## Vedi anche

- [Registrare un giro](./recording-a-ride)
- [Pianificare un percorso](./planning-a-route)
- [Mappe offline e calcolo del percorso](./offline-maps-and-routing)
- [Impostazioni e aspetto](./settings-and-appearance)
- [Risoluzione dei problemi](./troubleshooting)
