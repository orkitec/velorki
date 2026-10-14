---
title: Strava e Ride with GPS
description: Velorki funziona con Strava e Ride with GPS, gratis. Collega un account per caricare i giri registrati e importare percorsi, e scopri perché inviare un percorso a Strava è un file.
order: 13
---

Velorki è compatibile con Strava e con Ride with GPS: può caricare un giro che hai registrato, e portare i tuoi percorsi da quegli account nella tua libreria. Collegare uno dei due servizi è gratuito, con o senza [Velorki Plus](./velorki-plus). Velorki non è prodotto, approvato né sponsorizzato da Strava o da Ride with GPS.

Nulla viene inviato a nessuno dei due servizi finché non sei tu a collegare l'account e poi a chiedere qualcosa.

## Collegare un account

1. Apri **Opzioni** e trova la sezione **Connessioni**.
2. Tocca **Connetti con Strava** o **Connetti Ride with GPS**.
3. La pagina di accesso del servizio si apre in un browser. Accedi lì e approva l'accesso.
4. Torni in Velorki, e la riga mostra il tuo nome al posto di **Non connesso**.

Velorki chiede a Strava solo due permessi: **read**, il tuo profilo pubblico (il tuo id e il tuo nome, mostrati in Opzioni), e **activity:write**, per caricare i giri che scegli di caricare. Non legge le tue attività.

Il tuo telefono conserva il token di accesso nell'archivio sicuro del telefono, in una forma che solo il server di Velorki può aprire, e lo esclude dai backup. Da quel momento ogni caricamento e importazione passa per quel server, che apre il token per quella singola richiesta e la inoltra. Non conserva né il file né il token, né alcuna traccia della chiamata, e non può usare il token da solo.

Se un tentativo di connessione fallisce, Velorki dice "Connessione non riuscita:" con il motivo. Annullare la pagina di accesso non dice nulla.

Una riga con **Non disponibile in questa build** significa che questa build di Velorki è stata compilata senza le chiavi di quel servizio, come accade per una copia compilata in autonomia finché non fornisci le tue.

## Disconnettere

Tocca **Disconnetti** sulla riga connessa e conferma. Disconnettere dice anche al servizio di revocare l'accesso di Velorki, quando il server è raggiungibile. Non rimuove nulla dal tuo account Strava o Ride with GPS.

**Strava.** Disconnettere elimina dal telefono ogni dato di Strava: il token di accesso, i percorsi che hai importato da Strava e quelli che hai modificato a partire da questi, l'elenco dei percorsi in cache e i collegamenti dei tuoi giri alle rispettive attività Strava. I giri in sé restano. Velorki dice poi "I tuoi dati di Strava sono stati eliminati da questo telefono."

Se invece rimuovi Velorki dal tuo account Strava su strava.com, Velorki se ne accorge alla successiva chiamata a Strava, elimina gli stessi dati e te lo dice.

**Ride with GPS.** Velorki dimentica il token di accesso. Percorsi e giri già in libreria restano.

## Caricare un giro

1. Apri il giro in **Libreria → Giri**.
2. Tocca il pulsante a nuvoletta in alto a destra, etichettato **Carica**.
3. Scegli **Carica su Strava** o **Carica su Ride with GPS**.

Velorki dice "Caricamento su Strava…", poi "Caricato su Strava" con un'azione **View on Strava** che lo apre. Velorki conserva per questo il collegamento all'attività insieme al giro, finché non disconnetti. Un giro che è già lì non viene mai caricato due volte: la voce di menu diventa invece **View on Strava** o **Apri su Ride with GPS**.

Un caricamento su Strava può richiedere un po', perché Strava elabora il file prima che esista come attività; Velorki lo aspetta e collega il risultato.

## Importare percorsi

1. Apri il tab **Libreria**.
2. Tocca il pulsante a nuvoletta in alto a destra e scegli **Importa da Strava** o **Importa da Ride with GPS**.
3. L'elenco si intitola **Percorsi Strava** o **Percorsi Ride with GPS**. Ogni riga mostra il nome, la distanza, il dislivello e la data.
4. Tocca **Importa** su quello che vuoi. Finisce nella tua libreria, e Velorki dice "Anello alpino importato". Un percorso importato da Strava resta sul telefono: non viene mai inviato all'assistente, inserito in un link di condivisione o inviato a Ride with GPS o a qualsiasi altro servizio, e disconnettere Strava lo elimina.

Un percorso di Strava, e ogni percorso che modifichi a partire da esso, resta solo finché esiste ancora su Strava. Mentre Velorki è aperto, online e collegato, ricontrolla quel percorso su Strava ogni 48 ore; le tue modifiche restano finché il percorso è ancora lì. Se è stato eliminato su Strava, o non è stato possibile controllarlo per 7 giorni (offline, scollegato, o controlli che falliscono), Velorki lo rimuove e dice "Un percorso di Strava è stato rimosso: non esiste più su Strava, oppure non è stato possibile controllarlo per 7 giorni."

Il piè di pagina dice **Letto 16 set 2026**, il momento in cui l'elenco è stato recuperato. Velorki tiene l'elenco sul telefono al massimo 48 ore, e **Aggiorna** in alto a destra lo recupera di nuovo.

Se l'account non è collegato la schermata dice "Prima connetti Strava in Opzioni → Connessioni."

## Inviare un percorso a Ride with GPS

Apri il percorso, tocca **Invia**, scegli **Invia a Ride with GPS**. Viene caricato sul tuo account e Velorki propone **Apri** per vederlo lì.

## Inviare un percorso a Strava

L'API di Strava può leggere i percorsi ma non può crearli, quindi non c'è nulla su cui Velorki possa caricare. Scegliere **Invia a Strava** apre perciò una spiegazione:

> **Strava non può ricevere percorsi.** L'API di Strava può leggere i percorsi ma non crearli. Velorki esporta invece un file GPX: condividilo, poi importalo su strava.com.

Tocca **Esporta GPX**, salva o invia il file, e caricalo come percorso su strava.com. Questa strada è gratuita e non richiede alcuna connessione.

## È tutto gratuito

Collegare Strava o Ride with GPS, caricare un giro, importare percorsi e inviare un percorso a Ride with GPS sono gratuiti, come i file GPX, FIT e TCX, che fanno lo stesso lavoro a mano. Nulla di tutto questo richiede Velorki Plus.

## I dati di Strava restano sul telefono

I dati di Strava vengono solo mostrati a te. Le condizioni dell'API di Strava non permettono di dare i loro dati a un fornitore di IA o ad altri servizi, quindi Velorki non invia mai all'assistente un percorso arrivato da Strava, non lo inserisce mai in un link di condivisione e non lo invia mai a Ride with GPS né altrove. **Descrivi questo percorso**, ad esempio, non è offerto per un percorso così.

Sui nostri server non conserviamo alcun dato di Strava: sono tutti sul tuo telefono. Domande, o una richiesta di eliminazione dei dati, vanno a [ride@velorki.com](mailto:ride@velorki.com); vedi l'[informativa sulla privacy](/privacy).

## Vedi anche

- [Velorki Plus](./velorki-plus)
- [Importare ed esportare](./import-and-export)
- [Libreria](./library)
- [Assistente](./assistant)
- [Privacy sul telefono](./privacy-on-the-phone)
