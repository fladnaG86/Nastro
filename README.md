# Nastro

**English** · [Italiano](#italiano)

A macOS menu bar app that records video calls: your screen, the sound of the call (system audio) and
your own voice (microphone), together in one file. It also has an audio-only mode.

macOS's own recorders (QuickTime, ⌘⇧5) do not capture system audio, so a call recorded with them
contains only your voice. Nastro records both sides.

## Status

Early and private. The code is built and its automated tests pass, but the app has **not yet been
run through its hands-on checklist** ([docs/manual-checks.md](docs/manual-checks.md)) and has **not
yet recorded a real long call**. Treat everything below as intended behavior, not as verified
behavior, except what is stated as measured in [docs/capture-findings.md](docs/capture-findings.md).

## How it works, in plain words

1. **You press a shortcut** (`⌃⌥N`) or the button in the menu bar panel.
2. **Nastro asks macOS for three streams**: the picture of a screen or window, the sound the Mac is
   playing (the other people's voices), and your microphone.
3. **While recording**, the panel shows one level bar for the system audio and one for the
   microphone, so you can see at a glance that both are arriving. A muted source raises a warning
   in the panel; a voice that is not being recorded at all also puts a red octagon next to the menu
   bar icon and sends a notification.
4. **Nastro writes a work file** next to the final one (`... .nastro-partial.mov`), in small
   fragments, so a crash does not lose the recording.
5. **When you stop**, it produces the final file: the video is copied without re-encoding and the
   two audio tracks are merged into one, so both voices play in any player. The copy is written
   under a temporary name (`... .nastro-finalizing.mp4`) and gets its final name only when complete.
   Then the work file is deleted and a notification appears; clicking it shows the file in Finder.

Nastro uses only Apple frameworks and has no dependencies. It records only while you tell it to, and
nothing leaves your Mac.

## Requirements

- macOS 15 or later (microphone capture inside ScreenCaptureKit exists from macOS 15).
- Developed and tested only on macOS 27.3, Apple Silicon. Other versions are not guaranteed.
- To build from source: a Swift toolchain (Xcode or Command Line Tools).

## Build

```bash
scripts/make-dev-cert.sh   # once: creates a local "Nastro Dev" signing certificate
./build.sh                 # creates dist/Nastro.app
./build.sh --install       # also copies it to /Applications (quits a running Nastro first)
swift test                 # unit tests
```

**Why the certificate matters.** `build.sh` signs with the "Nastro Dev" certificate if it exists,
otherwise ad-hoc. With an ad-hoc signature macOS may treat every rebuild as a different app and ask
for the Screen Recording permission again. A stable self-signed certificate is the intended way to
avoid that. `scripts/make-dev-cert.sh` has not been run yet, so this is the plan, not something
proven. If `codesign` cannot use the certificate, the script says to trust it for Code Signing in
Keychain Access.

## Permissions

- **Screen & System Audio Recording**: needed for the picture and for the sound of the call. Nastro
  asks once at first launch. If it is missing, the panel says so and has a button that opens the
  right page of System Settings.
- **Microphone**: asked the first time you start a recording with the microphone on. If you refuse,
  the recording does not start and the panel explains why.

Notifications are also requested, to tell you when a recording is saved or something went wrong.

## Usage

`⌃⌥N` starts and stops a recording, or use the menu bar icon. While recording, the icon turns red and
shows the elapsed time. A red octagon next to it means a voice is not being recorded (system audio
or microphone not recorded, microphone disconnected); silence never changes the icon, it only shows
in the panel under its level bar. An orange triangle next to the idle icon means a problem to fix
before recording, such as a missing permission. If another app already holds the shortcut
(`⌃⌥` plus your letter), the panel shows a row saying so, Settings show the same note, and the
shortcut is not shown next to the Start button; choose another letter.

In the panel, when idle:

- **What to Record**: *Video + Audio* or *Audio Only*.
- **Video Source**: a screen or a single window. System audio is always the whole system's, even
  when only one window is filmed, because the call must be heard anyway. Nastro's own windows and
  sound are left out.
- **Audio**: **System Audio** (the call) and **Microphone** can each be turned off. In audio-only
  mode at least one must stay on: the last one checked cannot be unchecked.
- **Open Recordings Folder**, **Settings…**, **Quit**.

The choices cannot be changed while recording, and they are remembered between launches. While a
recording runs, Settings are locked too (except the shortcut) and say that changes apply from the
next recording. An audio-only recording that receives no audio within 5 seconds stops by itself,
keeps no file and says why.

**Files.** By default they go to `~/Movies/Nastro/`, named like `2026-11-17 14.30 Call.mp4` (video)
or `2026-11-17 14.30 Call.m4a` (audio only). If the name exists, a number is added (`... Call 2.mp4`).

**Settings…** (a small window): destination folder, maximum video resolution (long side, default
1920 px), frames per second (default 30), keep separate audio tracks (off by default: the two
tracks are merged), microphone (default: system default), and the shortcut letter. The shortcut is
`⌃⌥` plus a letter A to Z; S, R and T are not offered because the author's other app, Postino,
uses them.

The interface is in English or Italian, following your Mac's language.

## If the app or the Mac stops mid-recording

The work file stays readable up to the last fragment. At the next launch Nastro looks in the
recordings folder for leftover work files, turns each into a final file and tells you with a
notification. Temporary `... .nastro-finalizing.mp4` files left by an interrupted final step are
deleted first (they are never the only copy), so the recovered file keeps its original name. A work
file that cannot be read, or has no tracks, is renamed `... .nastro-damaged.mov` so it is not
retried every time. If there is not enough free space to prepare it, or the final merge fails for
another reason, the work file is left untouched and tried again at the next launch; a notification
says so. The work file is never deleted before its final file exists.

While recording, Nastro stops by itself when free space falls below the work file's size plus
500 MB (and never below 1 GB), so there is still room to prepare the final file.

Evidence: a recording driven by the app's own recording controller (the `--probe-record`
diagnostic below) was killed with `kill -9` at 13 s, and at the next launch it was recovered as a
12 s file that opens. Not yet confirmed with the installed app on a real interruption.

## Diagnostics (for developers)

The binary can run a few checks from the terminal instead of starting the menu bar app:

```bash
dist/Nastro.app/Contents/MacOS/Nastro --probe-record 10 display   # or: window | audio
dist/Nastro.app/Contents/MacOS/Nastro --probe-recover
dist/Nastro.app/Contents/MacOS/Nastro --preview idle              # or: recording | problem | settings | settings-recording | menubar
```

`--probe-record <seconds> <display|window|audio>` records into `~/Movies/Nastro/` and prints
`PROBE-RECORD ok <file>` or `PROBE-RECORD failed <reason>`. `--probe-recover` finalizes leftover work
files in the default folder and prints one `PROBE-RECOVER ...` line per file. `--preview` shows the
panel, the Settings window or the menu bar icon's states in a given state. There is also a separate `NastroProbe` tool used to
measure the capture APIs (`swift run NastroProbe`; see [docs/capture-findings.md](docs/capture-findings.md)).

## Known limits

- **No echo cancellation.** With speakers, the microphone also picks up the other people's voices.
  Use headphones.
- **A microphone that changes mid-recording stops being recorded.** A microphone whose first sample
  arrives more than 2 s after the recording starts, or whose audio format changes mid-recording (for
  example AirPods connecting during the call), stops being recorded for the rest of that recording.
  The app shows a red warning and sends a notification; the remedy is to stop and start a new
  recording. See [docs/capture-findings.md](docs/capture-findings.md).
- **The video is HEVC.** It plays on Apple devices but may not open on some Windows machines.
- **Recording other people may require their consent.** Tell the participants.
- **Not yet tested by hand or on a real call.** What happens when the recorded window is closed, or
  the microphone is unplugged, in the middle of a recording is the intended behavior (the recording
  stops and is saved in the first case, continues without the microphone in the second) and is not
  yet confirmed.
- **Signing.** Until `scripts/make-dev-cert.sh` has been run and checked, expect macOS to ask for the
  Screen Recording permission again after rebuilds.
- Not included: webcam overlay, region selection, editing, transcription, start at login.

## Similar projects

Other open-source recorders that capture system audio: BetterCapture, QuickRecorder, Azayaka. No code
from them is included in Nastro.

## License

MIT, see [LICENSE](LICENSE).

---

<a name="italiano"></a>

# Nastro (Italiano)

App per la barra dei menu di macOS che registra le video call: lo schermo, l'audio della call
(l'audio di sistema) e la tua voce (il microfono), insieme in un unico file. Ha anche una modalità
solo audio.

I registratori di macOS (QuickTime, ⌘⇧5) non registrano l'audio di sistema, quindi una call
registrata con quelli contiene solo la tua voce. Nastro registra entrambe le parti.

## Stato

Iniziale e privato. Il codice è compilato e i test automatici passano, ma l'app **non è ancora stata
provata con la lista di controlli a mano** ([docs/manual-checks.md](docs/manual-checks.md)) e **non
ha ancora registrato una call vera e lunga**. Quanto segue è il comportamento previsto, non
verificato, tranne ciò che è indicato come misurato in
[docs/capture-findings.md](docs/capture-findings.md).

## Come funziona, in parole semplici

1. **Premi una scorciatoia** (`⌃⌥N`) oppure il pulsante nel pannello della barra dei menu.
2. **Nastro chiede a macOS tre flussi**: l'immagine di uno schermo o di una finestra, il suono che
   sta riproducendo il Mac (le voci degli altri) e il microfono.
3. **Durante la registrazione** il pannello mostra una barra di livello per l'audio di sistema e una
   per il microfono, così vedi subito che arrivano entrambi. Una sorgente muta fa comparire un
   avviso nel pannello; una voce che non viene registrata affatto fa comparire anche un ottagono
   rosso accanto all'icona nella barra dei menu e manda una notifica.
4. **Nastro scrive un file di lavoro** accanto a quello finale (`... .nastro-partial.mov`), a piccoli
   frammenti, così un arresto improvviso non fa perdere la registrazione.
5. **Quando fermi**, produce il file finale: il video viene copiato senza ricodifica e le due tracce
   audio vengono fuse in una sola, così entrambe le voci si sentono in qualsiasi player. La copia
   viene scritta con un nome provvisorio (`... .nastro-finalizing.mp4`) e prende il nome finale solo
   quando è completa. Poi il file di lavoro viene cancellato e arriva una notifica; cliccandola il
   file si mostra nel Finder.

Nastro usa solo framework Apple, senza dipendenze. Registra solo quando glielo dici tu e nulla esce
dal tuo Mac.

## Requisiti

- macOS 15 o successivo (la cattura del microfono dentro ScreenCaptureKit esiste da macOS 15).
- Sviluppata e provata solo su macOS 27.3, Apple Silicon. Le altre versioni non sono garantite.
- Per compilare dai sorgenti: toolchain Swift (Xcode o Command Line Tools).

## Compilazione

```bash
scripts/make-dev-cert.sh   # una volta: crea un certificato di firma locale "Nastro Dev"
./build.sh                 # crea dist/Nastro.app
./build.sh --install       # copia anche in /Applications (chiude prima Nastro se è aperta)
swift test                 # test unitari
```

**Perché il certificato conta.** `build.sh` firma con il certificato "Nastro Dev" se esiste, altrimenti
ad-hoc. Con la firma ad-hoc macOS può considerare ogni ricompilazione un'app diversa e chiedere di
nuovo il permesso di Registrazione schermo. Un certificato autofirmato stabile è il modo previsto per
evitarlo. `scripts/make-dev-cert.sh` non è ancora stato eseguito, quindi questo è il piano, non una
cosa dimostrata. Se `codesign` non riesce a usare il certificato, lo script indica di impostarlo come
attendibile per la firma del codice in Accesso Portachiavi.

## Permessi

- **Registrazione schermo e audio di sistema**: serve per l'immagine e per il suono della call.
  Nastro lo chiede una volta al primo avvio. Se manca, il pannello lo dice e ha un pulsante che apre
  la pagina giusta di Impostazioni di Sistema.
- **Microfono**: richiesto la prima volta che avvii una registrazione con il microfono attivo. Se lo
  neghi, la registrazione non parte e il pannello ne spiega il motivo.

Vengono richieste anche le notifiche, per dirti quando una registrazione è salvata o qualcosa è
andato storto.

## Uso

`⌃⌥N` avvia e ferma la registrazione, oppure usa l'icona nella barra dei menu. Durante la
registrazione l'icona diventa rossa e mostra il tempo trascorso. Un ottagono rosso accanto vuol dire
che una voce non viene registrata (audio di sistema o microfono non registrati, microfono
scollegato); il silenzio non cambia mai l'icona, compare solo nel pannello sotto la sua barra di
livello. Un triangolo arancione accanto all'icona a riposo indica un problema da risolvere prima di
registrare, per esempio un permesso mancante. Se un'altra app usa già la scorciatoia (`⌃⌥` più la
tua lettera), il pannello lo dice in una riga, le Impostazioni mostrano lo stesso avviso e accanto
al pulsante di avvio la scorciatoia non compare; scegli un'altra lettera.

Nel pannello, a riposo:

- **Cosa registrare**: *Video + audio* oppure *Solo audio*.
- **Sorgente video**: uno schermo o una singola finestra. L'audio di sistema è sempre quello di tutto
  il sistema, anche se si riprende una sola finestra, perché la call deve comunque sentirsi. Le
  finestre e il suono di Nastro stesso sono esclusi.
- **Audio**: **Audio di sistema** (la call) e **Microfono** si possono disattivare separatamente. In
  modalità solo audio ne deve restare attivo almeno uno: l'ultimo selezionato non si può
  deselezionare.
- **Apri cartella registrazioni**, **Impostazioni…**, **Esci**.

Le scelte non si cambiano durante la registrazione e vengono ricordate tra un avvio e l'altro.
Durante una registrazione anche le Impostazioni sono bloccate (tranne la scorciatoia) e dicono che le
modifiche valgono dalla prossima registrazione. Una registrazione solo audio che non riceve audio
entro 5 secondi si ferma da sola, non lascia file e ne spiega il motivo.

**File.** Di default vanno in `~/Movies/Nastro/`, con nomi come `2026-11-17 14.30 Call.mp4` (video)
o `2026-11-17 14.30 Call.m4a` (solo audio). Se il nome esiste già si aggiunge un numero
(`... Call 2.mp4`).

**Impostazioni…** (una finestra piccola): cartella di destinazione, risoluzione massima del video
(lato lungo, predefinita 1920 px), fotogrammi al secondo (predefiniti 30), tieni tracce audio separate
(disattivato di default: le due tracce vengono fuse), microfono (predefinito: quello di sistema) e la
lettera della scorciatoia. La scorciatoia è `⌃⌥` più una lettera da A a Z; S, R e T non sono
proposte perché le usa Postino, l'altra app dell'autore.

L'interfaccia è in italiano o in inglese, secondo la lingua del Mac.

## Se l'app o il Mac si fermano a metà registrazione

Il file di lavoro resta leggibile fino all'ultimo frammento. Al prossimo avvio Nastro cerca nella
cartella delle registrazioni i file di lavoro rimasti, ne ricava un file finale per ciascuno e te lo
dice con una notifica. I file provvisori `... .nastro-finalizing.mp4` lasciati da una preparazione
interrotta vengono cancellati prima (non sono mai l'unica copia), così il file recuperato mantiene il
suo nome originale. Un file di lavoro che non si riesce a leggere, o senza tracce, viene rinominato
`... .nastro-damaged.mov`, così non viene ritentato a ogni avvio. Se manca lo spazio per prepararlo,
o la fusione finale fallisce per un altro motivo, il file di lavoro resta intatto e viene ritentato
al prossimo avvio; una notifica lo dice. Il file di lavoro non viene mai cancellato prima che esista
il suo file finale.

Durante la registrazione Nastro si ferma da sola quando lo spazio libero scende sotto la dimensione
del file di lavoro più 500 MB (e mai sotto 1 GB), così resta lo spazio per preparare il file finale.

Prove: una registrazione guidata dal controller di registrazione dell'app stessa (la diagnostica
`--probe-record` qui sotto) è stata terminata con `kill -9` a 13 s e al lancio successivo è stata
recuperata come file di 12 s che si apre. Non ancora confermato con l'app installata su
un'interruzione reale.

## Diagnostica (per sviluppatori)

L'eseguibile può fare alcune verifiche da terminale invece di avviare l'app nella barra dei menu:

```bash
dist/Nastro.app/Contents/MacOS/Nastro --probe-record 10 display   # oppure: window | audio
dist/Nastro.app/Contents/MacOS/Nastro --probe-recover
dist/Nastro.app/Contents/MacOS/Nastro --preview idle              # oppure: recording | problem | settings | settings-recording | menubar
```

`--probe-record <secondi> <display|window|audio>` registra in `~/Movies/Nastro/` e stampa
`PROBE-RECORD ok <file>` oppure `PROBE-RECORD failed <motivo>`. `--probe-recover` finalizza i file di
lavoro rimasti nella cartella predefinita e stampa una riga `PROBE-RECOVER ...` per ciascuno.
`--preview` mostra il pannello, la finestra Impostazioni o gli stati dell'icona nella barra dei menu
in uno stato dato. Esiste anche uno
strumento separato, `NastroProbe`, usato per misurare le API di cattura (`swift run NastroProbe`;
vedi [docs/capture-findings.md](docs/capture-findings.md)).

## Limiti noti

- **Nessuna cancellazione dell'eco.** Con gli altoparlanti il microfono riprende anche le voci degli
  altri. Usa le cuffie.
- **Un microfono che cambia a metà registrazione smette di essere registrato.** Un microfono il cui
  primo campione arriva più di 2 s dopo l'avvio della registrazione, o il cui formato audio cambia a
  metà (per esempio gli AirPods che si collegano durante la call), smette di essere registrato per il
  resto di quella registrazione. L'app mostra un avviso rosso e manda una notifica; il rimedio è
  fermare e avviare una nuova registrazione. Vedi [docs/capture-findings.md](docs/capture-findings.md).
- **Il video è HEVC.** Si apre sui dispositivi Apple ma potrebbe non aprirsi su alcuni computer
  Windows.
- **Registrare altre persone può richiedere il loro consenso.** Avvisa i partecipanti.
- **Non ancora provata a mano né su una call vera.** Cosa succede se si chiude la finestra registrata
  o si scollega il microfono a metà registrazione è il comportamento previsto (nel primo caso la
  registrazione si ferma e viene salvata, nel secondo continua senza microfono) e non è ancora
  confermato.
- **Firma.** Finché `scripts/make-dev-cert.sh` non è stato eseguito e verificato, aspettati che macOS
  chieda di nuovo il permesso di Registrazione schermo dopo le ricompilazioni.
- Non incluso: webcam in sovrimpressione, selezione di un'area, editing, trascrizione, avvio al login.

## Progetti simili

Altri registratori open source che catturano l'audio di sistema: BetterCapture, QuickRecorder,
Azayaka. Nessun codice di questi progetti è incluso in Nastro.

## Licenza

MIT, vedi [LICENSE](LICENSE).
