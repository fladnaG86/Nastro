# Controlli manuali di Nastro

Controlli da fare a mano sull'app installata (`./build.sh --install`). Ogni passo dice
cosa fare e cosa deve succedere. Se il risultato è diverso, annota cosa è successo.

I passi 19–22 in fondo coprono le correzioni successive (impostazioni bloccate, scorciatoia
occupata, riga del permesso); i passi 23–28 coprono AirPods, sincronia, recupero dopo un arresto,
ascolto con un solo auricolare e disco esterno scollegato; i passi 29–33 coprono trascrizione e riassunto.

**Icone nella barra dei menu.** Il triangolo arancione accanto all'icona compare solo per un
problema da risolvere prima di registrare (per esempio un permesso mancante). Durante la
registrazione, se una voce non viene registrata (audio di sistema o microfono non registrati,
microfono scollegato) accanto al pallino rosso compare un ottagono rosso con la croce. Il silenzio
non cambia l'icona: compare solo nel pannello, sotto la barra di livello.

## Primo avvio e permessi

1. Togli a Nastro i permessi di Registrazione schermo e Microfono (Impostazioni di Sistema →
   Privacy e sicurezza), poi avvia Nastro.
   **Atteso:** compare una volta la richiesta di sistema per la Registrazione schermo; nella
   barra dei menu c'è l'icona di Nastro con il triangolo di avviso.
2. Apri il menu di Nastro.
   **Atteso:** in alto c'è il riquadro arancione "Serve il permesso di Registrazione schermo."
   con il pulsante "Apri Impostazioni di Sistema".
3. Premi "Apri Impostazioni di Sistema".
   **Atteso:** si apre Impostazioni di Sistema sulla pagina Privacy e sicurezza →
   Registrazione schermo (e audio di sistema).
4. Concedi il permesso schermo, riapri Nastro, lascia il microfono attivo nel menu e premi
   "Avvia registrazione".
   **Atteso:** compare la richiesta di accesso al Microfono. Se la neghi, la registrazione non
   parte e il menu mostra "Serve il permesso di accesso al Microfono." con il pulsante; il
   pulsante apre la pagina Privacy e sicurezza → Microfono.

## Scorciatoia

5. Con Nastro aperto premi ⌃⌥N.
   **Atteso:** la registrazione parte; premendo di nuovo ⌃⌥N si ferma.
6. Con Postino aperto premi ⌃⌥S, ⌃⌥R e ⌃⌥T.
   **Atteso:** fanno ancora le azioni di Postino; Nastro non reagisce.
7. Nelle Impostazioni di Nastro cambia la scorciatoia (per esempio ⌃⌥M), poi prova ⌃⌥M e ⌃⌥N.
   **Atteso:** ⌃⌥M avvia e ferma la registrazione, ⌃⌥N non fa più nulla. Nell'elenco delle
   lettere non compaiono S, R e T.
8. Apri "Impostazioni…" dal menu.
   **Atteso:** la finestra delle Impostazioni si apre davanti alle altre finestre.

## Icona e menu durante la registrazione

9. Avvia una registrazione e guarda la barra dei menu.
   **Atteso:** l'icona diventa un pallino rosso con il tempo trascorso che avanza (per esempio
   `0:05`).
10. Apri il menu durante la registrazione.
    **Atteso:** "Ferma registrazione", il tempo, due barre di livello (Audio di sistema,
    Microfono) che si muovono; nessuna scelta di sorgente e nessun "Esci".
11. Ferma la registrazione e guarda subito la barra dei menu.
    **Atteso:** per qualche istante compare la clessidra (file in preparazione), poi torna
    l'icona normale.

## Notifiche

12. Alla fine di una registrazione aspetta la notifica.
    **Atteso:** arriva la notifica "Registrazione salvata" con il nome del file; cliccandola
    si apre il Finder con il file selezionato.

## Avvisi sull'audio

13. Avvia una registrazione con il microfono in muto o coperto.
    **Atteso:** entro circa 5 secondi sotto la barra del Microfono compare "Microfono muto" in
    arancione; l'icona nella barra dei menu non cambia (resta il pallino rosso con il tempo, senza
    triangolo né ottagono); per questo avviso non arriva nessuna notifica.
14. Durante una registrazione scollega o spegni il microfono scelto.
    **Atteso:** la registrazione continua; entro circa 5 secondi sotto la barra del Microfono
    compare un avviso rosso ("Microfono scollegato" o "Il microfono non viene registrato: ferma e avvia una nuova registrazione"), accanto
    al pallino rosso nella barra dei menu compare l'ottagono rosso e arriva una notifica; il file
    finale contiene comunque l'audio di sistema.
    **Se invece si ferma tutta la registrazione, annotalo** (questione aperta nota).

## Sorgente che sparisce, sospensione

15. Scegli come sorgente una finestra, avvia la registrazione e chiudi quella finestra.
    **Atteso:** la registrazione si ferma da sola, arriva la notifica e cliccandola il file si
    apre (si vede nel Finder).
    **Se invece la registrazione continua con l'immagine ferma, annotalo** (questione aperta
    nota).
16. Durante una registrazione metti il Mac in stop (menu Apple → Stop), poi riattivalo.
    **Atteso:** al risveglio la registrazione risulta salvata (notifica e file nella cartella).

## Scelte ricordate e finestre escluse

17. Scegli "Solo audio" oppure una sorgente diversa e un microfono diverso, esci da Nastro e
    riaprilo.
    **Atteso:** il menu mostra le stesse scelte di prima.
18. Registra lo schermo mentre il menu di Nastro e la finestra delle Impostazioni sono aperti,
    poi guarda il file.
    **Atteso:** né il menu di Nastro né la finestra delle Impostazioni compaiono nel video.

## Correzioni successive

19. Durante una registrazione apri le Impostazioni.
    **Atteso:** in alto la riga "Registrazione in corso: queste impostazioni valgono dalla
    prossima registrazione."; cartella, risoluzione, fotogrammi, tracce separate e microfono
    sono disattivati; la scorciatoia resta modificabile.
20. In un'altra app (per esempio Impostazioni di Sistema → Tastiera → Abbreviazioni da
    tastiera, o un'app di scorciatoie) assegna ⌃⌥N, poi riavvia Nastro.
    **Atteso:** accanto ad "Avvia registrazione" non compare ⌃⌥N; nel menu compare la riga "La
    scorciatoia ⌃⌥N è usata da un'altra app…" e nelle Impostazioni lo stesso avviso sotto la
    scorciatoia. Scegliendo una lettera libera l'avviso sparisce e la scorciatoia appare accanto
    al pulsante. (Se macOS accetta comunque ⌃⌥N senza errore, annotalo.)
21. Senza permesso schermo apri il menu, concedi il permesso in Impostazioni di Sistema e
    riapri il menu.
    **Atteso:** la riga del permesso dice "Dopo averlo concesso, esci e riapri Nastro." e offre
    "Esci da Nastro"; dopo la riapertura di Nastro la riga non c'è più. Se la riga sparisce già
    riaprendo il menu, senza riavviare, annotalo (va bene comunque).
22. Nel menu scegli come sorgente video una finestra, chiudi il menu, chiudi quella finestra
    (o esci dalla sua app) e riapri il menu di Nastro; poi avvia una registrazione.
    **Atteso:** la sorgente video mostra lo schermo principale e la registrazione cattura lo
    schermo principale (nessun errore "La sorgente scelta non è disponibile.").

## AirPods, sincronia, recupero, ascolto, disco esterno

23. Collega gli AirPods (o altre cuffie Bluetooth con microfono) **prima** di avviare la
    registrazione, scegli il loro microfono (o lascia quello di sistema se sono già il
    predefinito), fai una call di prova di un paio di minuti parlando e ascoltando, poi ferma.
    **Atteso:** nel file finale si sentono entrambe le voci (la tua e quella degli altri); la tua
    voce ha l'altezza normale (non accelerata né rallentata, non "da robot"); nessun ottagono
    rosso durante la registrazione.
24. Avvia una registrazione con il microfono del Mac e, a registrazione in corso, collega gli
    AirPods.
    **Atteso (limite noto):** il microfono può smettere di essere registrato per il resto della
    registrazione: sotto la barra del Microfono compare l'avviso rosso "Il microfono non viene
    registrato", nella barra dei menu l'ottagono rosso e arriva una notifica. Annota cosa succede
    davvero (avviso sì/no, la tua voce nel file prima e dopo il collegamento). Il rimedio è fermare
    e avviare una nuova registrazione.
25. Scegli come sorgente video la finestra della call (o un video con persone che parlano) e
    registra per almeno 10 minuti.
    **Atteso:** alla fine del file il labiale è ancora a tempo con le voci, come all'inizio (nessun
    ritardo o anticipo che cresce col tempo).
26. Con l'app installata avvia una registrazione, dopo circa 15 secondi terminala con
    `pkill -9 Nastro` dal Terminale, poi riapri Nastro.
    **Atteso:** arriva la notifica "Registrazione recuperata" con il nome del file; il file si apre
    e dura circa quanto la registrazione (al massimo qualche secondo in meno); nella cartella non
    restano file `.nastro-partial.mov` né `.nastro-finalizing.mp4`.
27. Ascolta un file finale (con entrambe le voci) usando un solo auricolare (solo il sinistro, poi
    solo il destro).
    **Atteso:** in ciascun orecchio si sentono entrambe le voci, la tua e quella degli altri.
28. Nelle Impostazioni scegli come cartella delle registrazioni una cartella su un disco esterno,
    poi espelli e scollega il disco e premi "Avvia registrazione".
    **Atteso:** la registrazione non parte; il menu mostra un errore chiaro ("La cartella delle
    registrazioni non è scrivibile.") e arriva una notifica; nessun file viene creato altrove.

## Trascrizione e riassunto

Servono macOS 26 e il server LLM locale (`llama-up`, porta 8001) per i passi che riassumono.

29. Con "Tieni tracce audio separate" attivo, registra una call vera di circa 1 ora (due voci),
    poi scegli "Trascrivi e riassumi…" su quella registrazione. Cronometra le due fasi.
    **Atteso:** la trascrizione è in italiano, con le righe etichettate Io e Altri; il riassunto è
    leggibile e fedele. Annota i tempi e la qualità (parole sbagliate, voci scambiate).
30. Ferma il server LLM, poi avvia il riassunto di una registrazione.
    **Atteso:** arriva una notifica con "Trascrizione salvata, riassunto non riuscito." e, a capo, "Modello non raggiungibile su <indirizzo>: server LLM acceso?"; il file `.trascrizione.txt` resta.
    Riavvia il server con `llama-up` e rilancia sulla stessa registrazione: la trascrizione viene
    saltata e si rifà solo il riassunto.
31. Avvia una trascrizione lunga e annullala a metà.
    **Atteso:** l'elaborazione si ferma; nella cartella non restano file temporanei.
32. Mentre una trascrizione è in corso, avvia una nuova registrazione.
    **Atteso:** la registrazione parte e non compare l'avviso "Alcuni frammenti audio sono andati persi"; alla fine il file si apre e non ha buchi.
33. Nelle Impostazioni, sezione Riassunto, scrivi un indirizzo remoto (per esempio
    `https://example.com/v1`).
    **Atteso:** compare l'avviso arancione "Con un indirizzo remoto il testo della call esce dal
    Mac"; con `http://127.0.0.1:8001/v1` l'avviso sparisce. Rimetti l'indirizzo predefinito.
