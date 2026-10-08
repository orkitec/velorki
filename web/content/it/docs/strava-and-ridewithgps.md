---
title: Strava e Ride with GPS
description: Collega il tuo account Strava o Ride with GPS per caricare i giri registrati e importare percorsi, e scopri perché inviare un percorso a Strava è un file.
order: 12
---

Velorki può parlare con Strava e con Ride with GPS per conto tuo: caricare un giro che hai registrato, e portare i tuoi percorsi da quegli account nella tua libreria. Collegare uno dei due servizi fa parte di [Velorki Plus](./velorki-plus); i file GPX, FIT e TCX restano gratuiti e fanno lo stesso lavoro a mano.

Nulla viene inviato a nessuno dei due servizi finché non sei tu a collegare l'account e poi a chiedere qualcosa.

## Collegare un account

1. Apri **Opzioni** e trova la sezione **Connessioni**.
2. Tocca **Connetti con Strava** o **Connetti Ride with GPS**.
3. La pagina di accesso del servizio si apre in un browser. Accedi lì e approva l'accesso.
4. Torni in Velorki, e la riga mostra il tuo nome al posto di **Non connesso**.

Il tuo telefono conserva il token di accesso nell'archivio sicuro del telefono, in una forma che solo il server di Velorki può aprire. Da quel momento ogni caricamento e importazione passa per quel server, che verifica il tuo abbonamento, apre il token per quella singola richiesta e la inoltra. Non conserva né il file né il token, e non può usare il token da solo.

Se un tentativo di connessione fallisce, Velorki dice "Connessione non riuscita:" con il motivo. Annullare la pagina di accesso non dice nulla.

Una riga con **Non disponibile in questa build** significa che questa build di Velorki è stata compilata senza le chiavi di quel servizio, come accade per una copia compilata in autonomia finché non fornisci le tue.

## Disconnettere

Tocca **Disconnetti** sulla riga connessa. Velorki chiede "Disconnettere Strava?" e spiega: "Velorki dimentica il token di accesso. Percorsi e giri già in libreria restano."

Disconnettere dice anche al servizio di revocare l'accesso di Velorki, quando il server è raggiungibile. Non rimuove nulla da Strava o Ride with GPS, e nulla dalla tua libreria.

## Caricare un giro

1. Apri il giro in **Libreria → Giri**.
2. Tocca il pulsante a nuvoletta in alto a destra, etichettato **Carica**.
3. Scegli **Carica su Strava** o **Carica su Ride with GPS**.

Velorki dice "Caricamento su Strava…", poi "Caricato su Strava" con un'azione **Vedi su Strava** che lo apre. Un giro che è già lì non viene mai caricato due volte: la voce di menu diventa invece **Vedi su Strava** o **Apri su Ride with GPS**.

Un caricamento su Strava può richiedere un po', perché Strava elabora il file prima che esista come attività; Velorki lo aspetta e collega il risultato.

## Importare percorsi

1. Apri il tab **Libreria**.
2. Tocca il pulsante a nuvoletta in alto a destra e scegli **Importa da Strava** o **Importa da Ride with GPS**.
3. L'elenco si intitola **Percorsi Strava** o **Percorsi Ride with GPS**. Ogni riga mostra il nome, la distanza, il dislivello e la data.
4. Tocca **Importa** su quello che vuoi. Finisce nella tua libreria come un percorso normale, e Velorki dice "Anello alpino importato".

Il piè di pagina dice **Letto 16 set 2026**, il momento in cui l'elenco è stato recuperato. Velorki lo tiene in cache fino a sette giorni, come richiedono le condizioni di Strava, e **Aggiorna** in alto a destra lo recupera di nuovo.

Se l'account non è collegato la schermata dice "Prima connetti Strava in Opzioni → Connessioni."

## Inviare un percorso a Ride with GPS

Apri il percorso, tocca **Invia**, scegli **Invia a Ride with GPS**. Viene caricato sul tuo account e Velorki propone **Apri** per vederlo lì.

## Inviare un percorso a Strava

L'API di Strava può leggere i percorsi ma non può crearli, quindi non c'è nulla su cui Velorki possa caricare. Scegliere **Invia a Strava** apre perciò una spiegazione:

> **Strava non può ricevere percorsi.** L'API di Strava può leggere i percorsi ma non crearli. Velorki esporta invece un file GPX: condividilo, poi importalo su strava.com.

Tocca **Esporta GPX**, salva o invia il file, e caricalo come percorso su strava.com. Questa strada è gratuita e non richiede alcuna connessione.

## Cosa è gratuito e cosa richiede Plus

| | Richiede Plus |
|---|---|
| Collegare Strava o Ride with GPS | sì |
| Caricare un giro su uno dei due | sì |
| Importare percorsi da uno dei due | sì |
| Inviare un percorso a Ride with GPS | sì |
| Esportare GPX, FIT o TCX e caricarlo da te | no |
| Importare un file GPX, FIT o TCX da uno dei due servizi | no |

## Una nota sull'assistente e Strava

**Descrivi questo percorso** non è offerto per un percorso arrivato da Strava. Le condizioni dell'API di Strava non permettono di inviare i loro dati a un fornitore di IA, quindi Velorki nasconde il pulsante anziché violarle.

## Vedi anche

- [Velorki Plus](./velorki-plus)
- [Importare ed esportare](./import-and-export)
- [Libreria](./library)
- [Assistente](./assistant)
- [Privacy sul telefono](./privacy-on-the-phone)
