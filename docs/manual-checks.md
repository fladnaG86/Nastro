# Controlli manuali di Nastro

Controlli da fare a mano sull'app installata (`./build.sh --install`). Ogni passo dice
cosa fare e cosa deve succedere. Se il risultato è diverso, annota cosa è successo.

I passi 19–22 in fondo coprono le correzioni successive (impostazioni bloccate, scorciatoia
occupata, riga del permesso).

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
    arancione e accanto all'icona compare il triangolo; per questo avviso non arriva nessuna
    notifica.
14. Durante una registrazione scollega o spegni il microfono scelto.
    **Atteso:** la registrazione continua; sotto la barra del Microfono compare un avviso e
    arriva una notifica; il file finale contiene comunque l'audio di sistema.
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
