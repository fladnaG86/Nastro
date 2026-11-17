# Nastro — design

Data: 2026-11-17. Stato: in attesa di approvazione.

## Intento

Nastro è un'app macOS che vive nella barra dei menu e registra le video call:
il video dello schermo, l'audio della call (le voci degli altri, cioè l'audio
di sistema) e la voce di chi registra (il microfono), in un unico file che si
apre ovunque. Ha anche una modalità solo audio.

Perché: QuickTime e ⌘⇧5 non registrano l'audio di sistema, quindi una call
registrata con gli strumenti di macOS contiene solo la propria voce. Le app
open source esistenti (BetterCapture, QuickRecorder, Azayaka) lo fanno, ma
Maurizio vuole un'app propria, piccola, con lo stesso impianto di Postino,
su cui in futuro costruire altro (trascrizione, verbali). Per ora conta solo
la registrazione.

## Obiettivi

- Avviare e fermare una registrazione dalla barra dei menu o con una
  scorciatoia globale, senza aprire finestre.
- Registrare video dello schermo + audio di sistema + microfono insieme.
- Registrare solo audio (audio di sistema + microfono) senza video.
- Produrre un file che si sente per intero in qualsiasi player e quando viene
  condiviso (una sola traccia audio con entrambe le voci).
- Reggere call lunghe (2 ore) senza perdere sincronia tra audio e video e
  senza file enormi.
- Non perdere la registrazione se l'app o il Mac si fermano a metà.

## Non obiettivi (v1)

- Webcam in sovrimpressione, selezione di un'area dello schermo, editing,
  zoom automatico, cursore evidenziato.
- Trascrizione, riassunti, qualsiasi uso di modelli.
- Cancellazione dell'eco: con gli altoparlanti il microfono riprende anche le
  voci degli altri. Si risolve usando le cuffie; l'app non interviene.
- Avvio automatico al login, avvio automatico quando parte una call.
- ProRes, HDR, canale alfa.
- Distribuzione (dmg, notarizzazione, Homebrew).

## Anti-obiettivi

- Una registrazione che sembra riuscita ma ha una delle due voci muta. È il
  fallimento peggiore: si scopre a call finita. L'app deve rendere visibile,
  mentre registra, che entrambe le sorgenti audio stanno arrivando.
- Un file finale che in alcuni player fa sentire solo una delle due voci.
- Toccare Postino: nessuna modifica a `~/Postino`, nessuna scorciatoia che
  entri in conflitto con le sue (Postino usa ⌃⌥S, ⌃⌥R, ⌃⌥T). La scorciatoia
  di Nastro è ⌃⌥N, confermata da Maurizio.

## Vincoli

- macOS 15 o successivo: la cattura del microfono dentro ScreenCaptureKit
  (`SCStreamConfiguration.captureMicrophone`, uscita di tipo `.microphone`)
  esiste da macOS 15. La macchina di sviluppo è su macOS 27.3, Apple Silicon.
  Il target di compilazione è macOS 15, ma l'app viene provata solo su 27.3:
  il funzionamento sulle versioni intermedie non è garantito né richiesto
  (scelta di Claude).
- Swift + Swift Package Manager, senza progetto Xcode, come Postino: un
  target `NastroCore` con la logica testabile, un target eseguibile `Nastro`,
  un target di test, uno `build.sh` che assembla `dist/Nastro.app` con
  `LSUIElement` (nessuna icona nel Dock).
- Nessuna dipendenza esterna: solo framework Apple (ScreenCaptureKit,
  AVFoundation, SwiftUI/AppKit, Carbon per la scorciatoia come in Postino).
- Permessi richiesti: Registrazione schermo e audio di sistema, Microfono.
  `Info.plist` deve avere `NSMicrophoneUsageDescription`.
- Sulla macchina non c'è nessuna identità di firma del codice. Con la firma
  ad-hoc usata da Postino macOS può considerare ogni nuova build un'app
  diversa e richiedere di nuovo il permesso di Registrazione schermo. Va
  gestito (vedi "Lasciato a chi costruisce").
- Licenze: si può copiare codice da BetterCapture (MIT, con attribuzione).
  Azayaka non ha licenza: si può leggere, non copiare. QuickRecorder è
  AGPL-3.0: non copiare.
- Repository: `~/Nastro`, GitHub `fladnaG86/Nastro`, privata finché l'app non
  funziona. Licenza MIT, README in inglese e italiano come Postino.
  Maurizio ha chiesto una repository separata su GitHub e ha approvato nome
  e visibilità: la repository privata va creata all'inizio del lavoro e i
  commit vanno pubblicati lì. Renderla pubblica richiede una sua conferma
  esplicita.

## Approcci considerati

1. **Registratore pronto di Apple** (`SCRecordingOutput`): ScreenCaptureKit
   scrive il file da solo. Pochissimo codice e sincronia gestita da Apple, ma
   poco controllo: incerto se il microfono finisca nel file nel modo che
   serve e se si possa registrare solo audio.
2. **Scrittura del file gestita dall'app** (scelto): ScreenCaptureKit
   consegna tre flussi (video, audio di sistema, microfono) e l'app li scrive
   con `AVAssetWriter`. Più codice e la sincronia è la parte delicata, ma dà
   controllo pieno su tracce, modalità solo audio, qualità e peso. È la
   strada di BetterCapture e Azayaka.
3. **Fork di BetterCapture**: funziona subito, ma è un progetto Xcode con
   un'architettura altrui e molte funzioni non richieste da mantenere.

Maurizio ha scelto il 2, in una repository separata da Postino.

## Come funziona

### Interfaccia

Icona nella barra dei menu. A riposo il menu contiene:

```
● Avvia registrazione            ⌃⌥N
──────────────────────────────────────
Cosa registrare
  ✓ Video + audio
    Solo audio
Sorgente video
  ✓ Schermo principale
    Schermo 2
    Finestra: <finestre aperte>
Audio
  ✓ Audio di sistema (la call)
  ✓ Microfono: <dispositivo>
──────────────────────────────────────
Apri cartella registrazioni
Impostazioni…
Esci
```

Durante la registrazione l'icona diventa rossa con il tempo trascorso
(`● 12:34`). Il menu mostra "Ferma registrazione" e due indicatori di
livello, uno per l'audio di sistema e uno per il microfono, così si vede
subito se una sorgente è muta. Le scelte di sorgente non sono modificabili
mentre si registra.

Finita la registrazione l'icona mostra per pochi secondi che il file è in
preparazione, poi una notifica con il nome del file; cliccandola si apre il
Finder sul file.

Le scelte del menu vengono ricordate tra un avvio e l'altro.

Impostazioni (finestra piccola): cartella di destinazione, qualità video
(risoluzione massima e fotogrammi al secondo), "tieni tracce audio separate",
scelta del microfono, scorciatoia.

Primo avvio: se manca un permesso, il menu lo dice e offre un pulsante che
apre la pagina giusta di Impostazioni di Sistema. "Avvia registrazione" non
parte in silenzio senza permessi.

Lingua dell'interfaccia: italiano e inglese secondo la lingua di sistema,
come Postino.

### Registrazione

- Sorgente video: uno schermo intero oppure una singola finestra. Le finestre
  di Nastro sono escluse dalla cattura.
- L'audio di sistema è sempre quello dell'intero sistema, anche quando la
  sorgente video è una sola finestra: la call deve sentirsi comunque. L'audio
  prodotto da Nastro stesso è escluso.
- Video: HEVC, 30 fotogrammi al secondo, lato lungo ridotto a un massimo
  equivalente a 1080p mantenendo le proporzioni. Sono valori predefiniti,
  modificabili nelle Impostazioni.
- Audio: AAC. Audio di sistema e microfono vengono scritti su due tracce
  separate durante la registrazione, ognuna con il proprio formato, senza
  mixaggio in tempo reale.
- Solo audio: stesse due tracce, nessun video.
- Si può disattivare una delle due sorgenti audio dal menu; almeno una deve
  restare attiva in modalità solo audio.

### File

- Cartella predefinita: `~/Movies/Nastro/`.
- Nome: `2026-11-17 14.30 Call.mp4` (video) o `.m4a` (solo audio). Se il nome
  esiste già si aggiunge un numero.
- Scrittura in due fasi:
  1. Durante la registrazione si scrive un file di lavoro `.mov` a frammenti
     (`movieFragmentInterval`), nella stessa cartella, con nome che lo rende
     riconoscibile come incompleto. Se l'app o il Mac si fermano, quel file
     resta leggibile fino all'ultimo frammento.
  2. Alla fine si produce il file definitivo: il video viene copiato senza
     ricodifica, le due tracce audio vengono fuse in una sola traccia AAC.
     Poi il file di lavoro viene cancellato. Con "tieni tracce audio
     separate" attivo il file definitivo conserva le due tracce e non le
     fonde.
- Recupero: all'avvio, se nella cartella c'è un file di lavoro rimasto da una
  registrazione interrotta, l'app lo porta a file definitivo con la stessa
  procedura e lo segnala.

### Errori

- Se la sorgente sparisce (finestra chiusa, schermo scollegato) o il flusso
  si interrompe, la registrazione si ferma e il file viene finalizzato con
  quanto registrato; una notifica spiega il motivo.
- Se il microfono scelto viene scollegato a metà, la registrazione continua
  con ciò che resta e una notifica lo segnala.
- Se una sorgente audio attiva non produce segnale per più di qualche
  secondo dopo l'avvio, l'icona lo segnala (anti-obiettivo: voce muta
  scoperta a call finita).
- Se la fusione finale fallisce, il file di lavoro non viene cancellato.
- Spazio su disco quasi esaurito: la registrazione si ferma e finalizza
  prima di riempire il disco.

## Struttura

- `NastroCore` (senza dipendenze da cattura, coperto da test): modello delle
  impostazioni e loro persistenza, macchina a stati della registrazione
  (riposo → in registrazione → in finalizzazione → riposo, con gli errori),
  nomi dei file e gestione dei doppioni, calcolo della risoluzione ridotta,
  formattazione del tempo, riconoscimento dei file di lavoro da recuperare,
  testi in italiano e inglese.
- `Nastro` (eseguibile): app e voce nella barra dei menu, elenco di schermi,
  finestre e microfoni, cattura con ScreenCaptureKit, scrittura con
  `AVAssetWriter`, finalizzazione, misura dei livelli audio, scorciatoia
  globale, finestra Impostazioni, notifiche, controllo dei permessi.

## Verifica

- Test automatici su `NastroCore`.
- Test automatico della finalizzazione su un file di lavoro sintetico (video
  breve più due tracce audio generate): il risultato ha una traccia video e
  una sola traccia audio, con durata corretta.
- Prova manuale, da fare prima di dichiarare l'app funzionante:
  - call vera di almeno 30 minuti con le cuffie: entrambe le voci si
    sentono, audio e video sono in sincronia all'inizio e alla fine;
  - stessa prova in solo audio;
  - il file si apre e si sente per intero in QuickTime, in VLC e dopo l'invio
    su WhatsApp;
  - uccidere l'app a metà registrazione: al riavvio il file viene recuperato;
  - chiudere la finestra registrata a metà: il file viene finalizzato;
  - con Postino aperto, le scorciatoie di entrambe le app funzionano.

## Scelte fatte da Claude, non discusse nel dettaglio

Maurizio ha approvato la bozza in blocco; questi punti sono proposte da
correggere se sbagliate:

- File di lavoro `.mov` a frammenti e poi conversione: nella bozza era solo
  "file scritto a frammenti".
- Finestre di Nastro escluse dalla cattura; audio di sistema sempre globale.
- Segnalazione di sorgente audio muta.
- Interfaccia in italiano e inglese.
- Licenza MIT, identificativo dell'app `it.nastro.app` (sul modello di
  `it.postino.app`).

## Lasciato a chi costruisce

- Come ottenere l'audio dell'intero sistema quando la sorgente video è una
  singola finestra (un solo flusso o un secondo flusso solo audio): va
  verificato sul comportamento reale di ScreenCaptureKit.
- Come registrare solo audio dato che ScreenCaptureKit richiede comunque una
  sorgente video (per esempio video minimo scartato).
- Allineamento dei tempi tra i tre flussi e gestione dei buchi (campioni
  audio che arrivano prima del primo fotogramma, schermo fermo che non
  produce fotogrammi).
- Tecnica della fusione finale: `AVAssetExportSession` non può copiare il
  video senza ricodifica e insieme fondere l'audio, quindi serve
  probabilmente lettura e riscrittura (`AVAssetReaderAudioMixOutput` per
  l'audio, copia diretta per il video). Da verificare.
- Verificare che `movieFragmentInterval` dia davvero un file leggibile dopo
  un'interruzione brusca; se no, proporre un'alternativa equivalente.
- Firma: trovare il modo di non perdere il permesso di Registrazione schermo
  a ogni build (per esempio un certificato di firma locale autofirmato),
  oppure documentare il limite.
- Bitrate, soglie di "sorgente muta", soglia di spazio su disco, aspetto
  dell'icona e degli indicatori di livello.
- Quali parti copiare da BetterCapture e come attribuirle.
