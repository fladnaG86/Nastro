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
   microphone, so you can see at a glance that both are arriving. A muted source raises a warning.
4. **Nastro writes a work file** next to the final one (`... .nastro-partial.mov`), in small
   fragments, so a crash does not lose the recording.
5. **When you stop**, it produces the final file: the video is copied without re-encoding and the
   two audio tracks are merged into one, so both voices play in any player. Then the work file is
   deleted and a notification appears; clicking it shows the file in Finder.

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
shows the elapsed time.

In the panel, when idle:

- **What to record**: *Video + audio* or *Audio only*.
- **Video source**: a screen or a single window. System audio is always the whole system's, even
  when only one window is filmed, because the call must be heard anyway. Nastro's own windows and
  sound are left out.
- **Audio**: system audio (the call) and microphone can each be turned off. In audio-only mode at
  least one must stay on.
- **Open recordings folder**, **Settings…**, **Quit**.

The choices cannot be changed while recording, and they are remembered between launches.

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
notification. A work file that cannot be recovered is renamed `... .nastro-damaged.mov` so it is
not retried every time. If the final merge fails, the work file is kept, never deleted. This was
confirmed on a crash test (an app killed with `kill -9` left a file that opens, see
[docs/capture-findings.md](docs/capture-findings.md)), but not yet through the full app on a real
interruption.

## Diagnostics (for developers)

The binary can run a few checks from the terminal instead of starting the menu bar app:

```bash
dist/Nastro.app/Contents/MacOS/Nastro --probe-record 10 display   # or: window | audio
dist/Nastro.app/Contents/MacOS/Nastro --probe-recover
dist/Nastro.app/Contents/MacOS/Nastro --preview idle              # or: recording | problem | settings
```

`--probe-record <seconds> <display|window|audio>` records into `~/Movies/Nastro/` and prints
`PROBE-RECORD ok <file>` or `PROBE-RECORD failed <reason>`. `--probe-recover` finalizes leftover work
files in the default folder and prints one `PROBE-RECOVER ...` line per file. `--preview` shows the
panel or the Settings window in a given state. There is also a separate `NastroProbe` tool used to
measure the capture APIs (`swift run NastroProbe`; see [docs/capture-findings.md](docs/capture-findings.md)).

## Known limits

- **No echo cancellation.** With speakers, the microphone also picks up the other people's voices.
  Use headphones.
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
   avviso.
4. **Nastro scrive un file di lavoro** accanto a quello finale (`... .nastro-partial.mov`), a piccoli
   frammenti, così un arresto improvviso non fa perdere la registrazione.
5. **Quando fermi**, produce il file finale: il video viene copiato senza ricodifica e le due tracce
   audio vengono fuse in una sola, così entrambe le voci si sentono in qualsiasi player. Poi il file
   di lavoro viene cancellato e arriva una notifica; cliccandola il file si mostra nel Finder.

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
registrazione l'icona diventa rossa e mostra il tempo trascorso.

Nel pannello, a riposo:

- **Cosa registrare**: *Video + audio* oppure *Solo audio*.
- **Sorgente video**: uno schermo o una singola finestra. L'audio di sistema è sempre quello di tutto
  il sistema, anche se si riprende una sola finestra, perché la call deve comunque sentirsi. Le
  finestre e il suono di Nastro stesso sono esclusi.
- **Audio**: audio di sistema (la call) e microfono si possono disattivare separatamente. In
  modalità solo audio ne deve restare attivo almeno uno.
- **Apri cartella registrazioni**, **Impostazioni…**, **Esci**.

Le scelte non si cambiano durante la registrazione e vengono ricordate tra un avvio e l'altro.

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
dice con una notifica. Un file di lavoro che non si riesce a recuperare viene rinominato
`... .nastro-damaged.mov`, così non viene ritentato a ogni avvio. Se la fusione finale fallisce, il
file di lavoro viene conservato, mai cancellato. Questo è stato confermato con una prova di arresto
(un'app terminata con `kill -9` ha lasciato un file che si apre, vedi
[docs/capture-findings.md](docs/capture-findings.md)), ma non ancora con l'app completa su
un'interruzione reale.

## Diagnostica (per sviluppatori)

L'eseguibile può fare alcune verifiche da terminale invece di avviare l'app nella barra dei menu:

```bash
dist/Nastro.app/Contents/MacOS/Nastro --probe-record 10 display   # oppure: window | audio
dist/Nastro.app/Contents/MacOS/Nastro --probe-recover
dist/Nastro.app/Contents/MacOS/Nastro --preview idle              # oppure: recording | problem | settings
```

`--probe-record <secondi> <display|window|audio>` registra in `~/Movies/Nastro/` e stampa
`PROBE-RECORD ok <file>` oppure `PROBE-RECORD failed <motivo>`. `--probe-recover` finalizza i file di
lavoro rimasti nella cartella predefinita e stampa una riga `PROBE-RECOVER ...` per ciascuno.
`--preview` mostra il pannello o la finestra Impostazioni in uno stato dato. Esiste anche uno
strumento separato, `NastroProbe`, usato per misurare le API di cattura (`swift run NastroProbe`;
vedi [docs/capture-findings.md](docs/capture-findings.md)).

## Limiti noti

- **Nessuna cancellazione dell'eco.** Con gli altoparlanti il microfono riprende anche le voci degli
  altri. Usa le cuffie.
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
