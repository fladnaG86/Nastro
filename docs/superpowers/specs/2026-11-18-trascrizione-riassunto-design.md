# Nastro — trascrizione e riassunto delle call

Data: 2026-11-18. Stato: bozza, in attesa di approvazione dell'utente.

## Intento

L'utente registra le call con Nastro e vuole poterne avere, **quando gli serve**,
il testo e un riassunto, tutto sul Mac: niente audio o testo verso servizi esterni.
Dal riassunto vuole due cose insieme: il racconto di cosa si è detto e l'elenco
di decisioni e cose da fare. Le call sono in italiano.

Il riassunto lo fa Gemma 4 26B-A4B, già installato e servito da llama.cpp su
`http://127.0.0.1:8001/v1` (API compatibile OpenAI, lo stesso che usa Postino).
Gemma 26B-A4B non accetta audio (solo testo e immagini), quindi serve prima un
passo di trascrizione separato.

## Obiettivi

- Dal menu di Nastro, scegliere una registrazione (`.mp4` o `.m4a` in
  `~/Movies/Nastro/`) e ottenere accanto ad essa:
  - `<nome>.trascrizione.txt` — testo completo con orari;
  - `<nome>.riassunto.md` — riassunto in tre parti: **Di cosa si è parlato**
    (racconto breve in ordine), **Decisioni**, **Cose da fare** (chi, cosa,
    scadenze se nominate).
- Se la registrazione ha le tracce audio separate (impostazione esistente
  "Tieni tracce audio separate"), il testo indica chi parla: **Io** (microfono)
  e **Altri** (audio di sistema). Con traccia unica mista, nessuna etichetta.
- Rifare il riassunto senza ritrascrivere: se la trascrizione esiste già, si usa.
- Avanzamento visibile nel pannello del menu e notifica a fine lavoro.
- Una call di 1 ora trascritta in pochi minuti su M1 Max (da misurare).

## Non obiettivi

- Trascrizione dal vivo durante la call.
- Riconoscere le singole persone tra gli "Altri" (diarizzazione).
- Lingue diverse dall'italiano.
- Ricerca tra le call dentro Nastro (i `.txt` restano comunque trovabili da
  Spotlight).
- Avvio automatico a fine registrazione.
- Modifica del riassunto dentro l'app (si apre nell'editor di sistema).

## Anti-obiettivi

- Rovinare o rallentare una registrazione in corso.
- Mandare audio o testo fuori dal Mac senza che l'utente lo sappia.
- Perdere la trascrizione perché il riassunto è fallito.
- Toccare i modelli locali dell'utente. Nastro non avvia né ferma mai server
  LLM (Gemma e thinkingcap non stanno insieme in 32 GB; li gestisce l'utente con
  `llama-up`/`llama-down`). Deciso dall'utente il 2026-11-18: "stessa cosa che
  fa app postino", cioè solo avvisare.

## Vincoli

- Trascrizione con il riconoscimento vocale di macOS (`SpeechAnalyzer` +
  `SpeechTranscriber`, framework Speech). Verificato il 2026-11-18 su questo Mac
  (macOS 27.3): `it_IT` supportato **e già installato**. Richiede macOS 26.
  Il repo è pubblico con release scaricabili: il minimo dell'app **resta
  macOS 15** e la funzione esiste solo da macOS 26 in su (`@available` sul
  target `NastroTranscribe`, riga di menu e sezione Impostazioni nascoste
  sotto 26). Scelta di Claude.
- Gemma: contesto del server 65536 token (`llama-moe`). Un'ora di parlato
  italiano ≈ 9–10 mila parole ≈ 15–20 mila token; due ore sono vicine al
  limite lasciando spazio per istruzioni e risposta.
- Tracce separate: `MovieWriter` crea le tracce audio nell'ordine audio di
  sistema, poi microfono; il `Finalizer` le copia così. Nessuna etichetta nel
  file oggi.
- Con le casse invece delle cuffie il microfono sente anche gli altri: nelle
  registrazioni a tracce separate le stesse frasi possono comparire sia come
  "Io" sia come "Altri". Il README chiede già le cuffie; in v1 nessuna
  correzione, solo il limite scritto nel README. Scelta di Claude.
- Le registrazioni sono `.mp4` HEVC (video + 1 o 2 tracce AAC) o `.m4a`.
- Nessuna dipendenza esterna nuova (come il resto di Nastro: Swift + SPM).

## Approcci considerati

| | Trascrizione | Pro | Contro |
|---|---|---|---|
| **A (scelto)** | Riconoscimento vocale di macOS dentro Nastro | Niente da installare, italiano già presente, offline, veloce, una sola app | Qualità sul parlato italiano con gergo/nomi propri da verificare |
| B | whisper.cpp large-v3-turbo | Probabilmente più preciso in italiano | Installazione a parte (Homebrew + ~1,6 GB), più lento, dipendenza esterna |
| scartato | Script separato fuori da Nastro | — | L'utente vuole la funzione nel menu dell'app |

Scelto A dall'utente il 2026-11-18, senza prova preliminare. Il passo di
trascrizione sta dietro un'interfaccia (`Transcriber`), così se la qualità
delude si può sostituire con Whisper senza toccare formato, riassunto e menu.

## Come funziona

### Interfaccia

- Nuova riga nel pannello del menu, sopra "Apri cartella registrazioni":
  **Trascrivi e riassumi…**. Apre un pannello di scelta file nella cartella
  registrazioni, filtrato su `.mp4`/`.m4a`.
- La riga è disattivata durante una registrazione (scelta di Claude: la
  registrazione ha la precedenza). Se invece si avvia una registrazione mentre
  una trascrizione è in corso, la trascrizione continua a bassa priorità
  (`QoS .utility`); le prove manuali verificano che non causi buchi audio.
- Durante il lavoro il pannello mostra una riga di stato con il nome della
  registrazione e la fase: "Trascrizione 42%" → "Riassunto…", con un pulsante
  **Annulla**. Un lavoro alla volta.
- A fine lavoro: notifica "Riassunto pronto"; cliccandola si apre il `.md`.
  In caso di errore: notifica con il motivo (vedi Errori).
- Impostazioni: nuova sezione **Riassunto**, uguale a quella di Postino:
  indirizzo del server (predefinito `http://127.0.0.1:8001/v1`), nome del
  modello (predefinito `gemma-4-26b-a4b`), chiave API facoltativa nel
  Portachiavi (per server che la chiedono). Se l'indirizzo non è locale (non 127.0.0.1/localhost),
  avviso come in Postino: "Con un indirizzo remoto il testo della call esce dal
  Mac".

```
┌──────────────────────────────────┐
│ ■ Avvia registrazione     ⌃⌥N    │
│ ...                              │
│ Trascrizione — 2026-11-18 10.02  │
│ ███████░░░░░ 58%      [Annulla]  │
│ Trascrivi e riassumi…            │
│ Apri cartella registrazioni      │
│ Impostazioni…                    │
└──────────────────────────────────┘
```

### Flusso

1. Se esiste `<nome>.trascrizione.txt`, salta al passo 4.
2. Legge le tracce audio della registrazione (AVFoundation). Una traccia →
   un flusso senza etichetta. Due tracce → traccia 1 = **Altri**, traccia 2 =
   **Io** (ordine di `MovieWriter`).
3. Trascrive ogni flusso con `SpeechTranscriber` (locale `it_IT`, con orari
   per segmento), unisce i segmenti in ordine di tempo, scrive il `.txt`
   (prima in un file temporaneo, poi rinomina, come il `Finalizer`).
4. Costruisce la richiesta per Gemma (istruzioni in italiano + trascrizione) e
   la manda a `/chat/completions`. Se la trascrizione è troppo lunga per il
   contesto, la divide in parti, riassume ogni parte e poi fonde i riassunti
   parziali in quello finale.
5. Scrive `<nome>.riassunto.md` (temporaneo + rinomina). Un riassunto già
   presente viene sostituito (scelta di Claude: rifare il riassunto è proprio
   il caso d'uso).

### Formato della trascrizione

```
[00:00:04] Altri: Buongiorno, ci siete tutti?
[00:00:07] Io: Sì, ci sono. Partiamo dal preventivo.
```

Senza tracce separate le righe non hanno "Io:"/"Altri:". Un segmento per riga;
segmenti consecutivi della stessa voce vicini nel tempo si possono unire in un
paragrafo (dettaglio lasciato a chi costruisce).

### Formato del riassunto

```markdown
# Riassunto — <nome registrazione>
Durata: 58 min · Trascritto il 2026-11-18

## Di cosa si è parlato
...

## Decisioni
- ...

## Cose da fare
- [Io] Mandare il preventivo aggiornato — entro venerdì
- [Altri] ...
```

Se una sezione è vuota, Gemma scrive "Nessuna" invece di inventare. Le
istruzioni chiedono esplicitamente di non aggiungere fatti non presenti nella
trascrizione.

### Errori

- **Modello italiano assente** (es. su un altro Mac): chiedere a macOS di
  scaricarlo (`AssetInventory`), mostrando l'avanzamento; se non si può,
  errore "Il riconoscimento vocale italiano non è disponibile".
- **Registrazione senza audio o illeggibile**: errore, nessun file scritto.
- **Trascrizione vuota** (silenzio): errore "Nella registrazione non si sente
  parlare", nessun file.
- **Modello non raggiungibile** (connessione rifiutata o scaduta, come in
  Postino): la trascrizione resta salvata; notifica "Trascrizione salvata.
  Modello non raggiungibile su <indirizzo>: server LLM acceso?". Nastro non
  prova ad avviarlo. L'utente lo avvia (`llama-up`) e rilancia: il passo 1
  salta la trascrizione.
- **Risposta HTTP di errore** dal server: stesso trattamento, con codice e
  primi ~400 caratteri della risposta nel messaggio (come Postino).
- **Annulla**: si ferma; i file temporanei si cancellano; una trascrizione già
  completata resta.

## Struttura

- `NastroCore` (logica pura, testata): unione e formattazione dei segmenti,
  nomi dei file accanto alla registrazione, costruzione delle istruzioni per
  Gemma, stima della lunghezza e divisione in parti, controllo indirizzo
  locale/remoto, testi IT/EN in `L10n`.
- Nuovo target `NastroTranscribe` (dipende da `NastroCore`): lettura delle
  tracce audio, `Transcriber` (protocollo) + implementazione `SpeechAnalyzer`,
  client `/chat/completions` (protocollo, sostituibile nei test).
- `Nastro`: controller del lavoro (fasi, avanzamento, annulla), riga nel menu,
  sezione Impostazioni, notifiche.
- Diagnostica da terminale, come le altre: `Nastro --probe-transcribe <file>`
  (scrive solo il `.txt`, stampa il tempo impiegato) e
  `Nastro --probe-summarize <file.trascrizione.txt>`.

## Verifica

- Test unitari con trascrittore e client finti: unione segmenti a due voci,
  formato righe, divisione in parti e fusione, errori (Gemma giù, annulla,
  trascrizione vuota), sostituzione del riassunto, file temporanei mai lasciati.
- Test di integrazione su un file corto generato (voce sintetica italiana con
  `say`) per la trascrizione reale.
- Prove manuali: call vera di ~1 ora con tracce separate; misurare tempo di
  trascrizione e di riassunto; leggere qualità del testo e del riassunto;
  avviare una registrazione durante una trascrizione e controllare che non ci
  siano buchi.

## Scelte fatte da Claude, non discusse nel dettaglio

- Minimo app resta macOS 15; funzione solo da macOS 26.
- Casse/eco tra tracce: solo limite nel README, nessuna correzione in v1.
- Chiave API facoltativa come Postino.
- README IT/EN aggiornati (funzione, requisito macOS 26, server LLM da avviare
  a mano, indirizzo predefinito).
- Riga disattivata durante la registrazione; trascrizione che continua se si
  avvia una registrazione.
- Riassunto esistente sostituito senza chiedere.
- Indirizzo e modello configurabili nelle Impostazioni, avviso se remoto.
- Nomi file `.trascrizione.txt` / `.riassunto.md`.
- Trascrizione vuota = errore, nessun file.

## Lasciato a chi costruisce

- Formato audio passato a `SpeechAnalyzer` (estrazione in file temporaneo o
  lettura diretta) e gestione delle due tracce (in sequenza o in parallelo).
- Soglia esatta di lunghezza oltre cui dividere in parti e dimensione delle parti.
- Testo esatto delle istruzioni per Gemma (temperatura, max token).
- Raggruppamento dei segmenti in paragrafi.
- Se scrivere etichette di traccia nei nuovi file al momento della
  finalizzazione (utile ma non necessario).
