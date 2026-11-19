import Foundation

/// Keyed localization. Every key must have both an Italian and an English string.
public enum L10n {
    public enum Language: Sendable {
        case it, en

        /// Italian if the first preferred system language starts with "it", English otherwise.
        public static var current: Language {
            from(preferred: Locale.preferredLanguages)
        }

        public static func from(preferred: [String]) -> Language {
            (preferred.first ?? "en").lowercased().hasPrefix("it") ? .it : .en
        }
    }

    /// Later tasks add their keys here.
    public enum Key: CaseIterable, Sendable {
        case appName
        case quit
        // Menu
        case startRecording, stopRecording
        case menuWhatToRecord, modeVideoAndAudio, modeAudioOnly
        case menuVideoSource, menuDisplays, menuWindows, mainDisplayPlaceholder
        case menuAudio, systemAudio, microphone, microphoneNotConnected
        case openRecordingsFolder, settingsEllipsis, preparingFile, openSystemSettings
        // Settings window
        case settingsTitle, settingsFolder, chooseFolder, settingsMaxResolution, settingsFramesPerSecond
        case settingsKeepSeparateTracks, settingsMicrophone, systemDefaultMicrophone, settingsHotKey
        case settingsAppliesNextRecording
        case settingsSummary, settingsServerURL, settingsModel, settingsAPIKey, settingsServerHint, settingsRemoteWarning
        // Hotkey conflict (%@ = the shortcut) and permission relaunch
        case hotKeyInUseMenu, hotKeyInUseSettings, relaunchAfterGranting, quitNastro
        // Notifications
        case recordingSaved, recordingEmpty, recordingStopped
        case stoppedSourceLost, stoppedStreamError, stoppedDiskFull
        case writeFailed, finalizeFailed, noRoomToFinalize, workFileKept
        case recordingRecovered, recordingDamaged
        /// %@ = the work file's name.
        case recoveryNoRoom
        case startFailed, noFirstFrame
        // Warnings
        case warningSystemAudioSilent, warningMicrophoneSilent, warningMicrophoneLost
        case warningSystemAudioNotRecorded, warningMicrophoneNotRecorded, warningAudioDropouts
        case noAudio, recordingNotSaved
        // Start problems
        case problemScreenPermission, problemMicrophonePermission, problemFolder
        case problemSourceUnavailable, problemOther
        // Transcription and summary (%d = percent; %d, %d = part, parts; %@ = server URL;
        // %d, %@ = HTTP status, detail)
        case summarizeEllipsis, summaryPreparing, summaryTranscribing, summarySummarizingOne, summarySummarizing
        case summaryReady, transcriptSavedSummaryFailed, cancel
        case errNoAudio, errNoSpeech, errSpeechModel, errCannotWrite, errInvalidURL, errUnreachable
        case errHTTP, errServer, errEmptyReply
    }

    public static func t(_ key: Key, language: Language = .current) -> String {
        switch language {
        case .it: return italian(key)
        case .en: return english(key)
        }
    }

    private static func italian(_ key: Key) -> String {
        switch key {
        case .appName: return "Nastro"
        case .quit: return "Esci"
        case .startRecording: return "Avvia registrazione"
        case .stopRecording: return "Ferma registrazione"
        case .menuWhatToRecord: return "Cosa registrare"
        case .modeVideoAndAudio: return "Video + audio"
        case .modeAudioOnly: return "Solo audio"
        case .menuVideoSource: return "Sorgente video"
        case .menuDisplays: return "Schermi"
        case .menuWindows: return "Finestre"
        case .mainDisplayPlaceholder: return "Schermo principale"
        case .menuAudio: return "Audio"
        case .systemAudio: return "Audio di sistema"
        case .microphone: return "Microfono"
        case .microphoneNotConnected: return "non collegato"
        case .openRecordingsFolder: return "Apri cartella registrazioni"
        case .settingsEllipsis: return "Impostazioni…"
        case .preparingFile: return "Preparazione del file…"
        case .openSystemSettings: return "Apri Impostazioni di Sistema"
        case .settingsTitle: return "Impostazioni di Nastro"
        case .settingsFolder: return "Cartella registrazioni"
        case .chooseFolder: return "Scegli…"
        case .settingsMaxResolution: return "Risoluzione massima"
        case .settingsFramesPerSecond: return "Fotogrammi al secondo"
        case .settingsKeepSeparateTracks: return "Tieni tracce audio separate"
        case .settingsMicrophone: return "Microfono"
        case .systemDefaultMicrophone: return "Predefinito di sistema"
        case .settingsHotKey: return "Scorciatoia"
        case .settingsAppliesNextRecording: return "Registrazione in corso: queste impostazioni valgono dalla prossima registrazione."
        case .settingsSummary: return "Riassunto"
        case .settingsServerURL: return "Indirizzo server"
        case .settingsModel: return "Modello"
        case .settingsAPIKey: return "Chiave API (facoltativa)"
        case .settingsServerHint: return "Locale: http://127.0.0.1:8001/v1 (llama.cpp). Nastro non avvia il server: avvialo tu prima di riassumere."
        case .settingsRemoteWarning: return "Con un indirizzo remoto il testo della call esce dal Mac."
        case .hotKeyInUseMenu: return "La scorciatoia %@ è usata da un'altra app. Puoi cambiarla nelle Impostazioni."
        case .hotKeyInUseSettings: return "%@ è usata da un'altra app: scegli un'altra lettera."
        case .relaunchAfterGranting: return "Dopo averlo concesso, esci e riapri Nastro."
        case .quitNastro: return "Esci da Nastro"
        case .recordingSaved: return "Registrazione salvata"
        case .recordingEmpty: return "Registrazione vuota: nessun file salvato."
        case .recordingStopped: return "Registrazione interrotta"
        case .stoppedSourceLost: return "La sorgente registrata non è più disponibile."
        case .stoppedStreamError: return "La cattura si è interrotta."
        case .stoppedDiskFull: return "Spazio su disco quasi esaurito."
        case .writeFailed: return "Errore durante la scrittura della registrazione."
        case .finalizeFailed: return "Impossibile preparare il file finale."
        case .noRoomToFinalize: return "Spazio insufficiente per preparare il file finale."
        case .workFileKept: return "Il file di lavoro è stato conservato e verrà recuperato al prossimo avvio:"
        case .recordingRecovered: return "Registrazione recuperata"
        case .recordingDamaged: return "Registrazione interrotta non recuperabile"
        case .recoveryNoRoom: return "Spazio insufficiente per preparare %@: libera spazio e riapri Nastro."
        case .startFailed: return "Impossibile avviare la registrazione"
        case .noFirstFrame: return "Nessuna immagine dallo schermo entro 5 secondi: registrazione annullata."
        case .warningSystemAudioSilent: return "Audio di sistema muto"
        case .warningMicrophoneSilent: return "Microfono muto"
        case .warningMicrophoneLost: return "Microfono scollegato"
        case .warningSystemAudioNotRecorded: return "L'audio di sistema non viene registrato"
        case .warningMicrophoneNotRecorded: return "Il microfono non viene registrato: ferma e avvia una nuova registrazione"
        case .warningAudioDropouts: return "Alcuni frammenti audio sono andati persi"
        case .noAudio: return "Nessun audio entro 5 secondi: registrazione annullata."
        case .recordingNotSaved: return "La registrazione non è stata salvata."
        case .problemScreenPermission: return "Serve il permesso di Registrazione schermo."
        case .problemMicrophonePermission: return "Serve il permesso di accesso al Microfono."
        case .problemFolder: return "La cartella delle registrazioni non è scrivibile."
        case .problemSourceUnavailable: return "La sorgente scelta non è disponibile."
        case .problemOther: return "Errore imprevisto all'avvio della registrazione."
        case .summarizeEllipsis: return "Trascrivi e riassumi…"
        case .summaryPreparing: return "Preparazione…"
        case .summaryTranscribing: return "Trascrizione %d%%"
        case .summarySummarizingOne: return "Riassunto…"
        case .summarySummarizing: return "Riassunto %d di %d…"
        case .summaryReady: return "Riassunto pronto"
        case .transcriptSavedSummaryFailed: return "Trascrizione salvata, riassunto non riuscito."
        case .cancel: return "Annulla"
        case .errNoAudio: return "La registrazione non ha audio leggibile."
        case .errNoSpeech: return "Nella registrazione non si sente parlare."
        case .errSpeechModel: return "Il riconoscimento vocale italiano non è disponibile."
        case .errCannotWrite: return "Impossibile scrivere accanto alla registrazione."
        case .errInvalidURL: return "Indirizzo del server non valido."
        case .errUnreachable: return "Modello non raggiungibile su %@: server LLM acceso?"
        case .errHTTP: return "Errore %d dal server: %@"
        case .errServer: return "Errore dal server."
        case .errEmptyReply: return "Il modello ha risposto senza testo."
        }
    }

    private static func english(_ key: Key) -> String {
        switch key {
        case .appName: return "Nastro"
        case .quit: return "Quit"
        case .startRecording: return "Start Recording"
        case .stopRecording: return "Stop Recording"
        case .menuWhatToRecord: return "What to Record"
        case .modeVideoAndAudio: return "Video + Audio"
        case .modeAudioOnly: return "Audio Only"
        case .menuVideoSource: return "Video Source"
        case .menuDisplays: return "Displays"
        case .menuWindows: return "Windows"
        case .mainDisplayPlaceholder: return "Main Display"
        case .menuAudio: return "Audio"
        case .systemAudio: return "System Audio"
        case .microphone: return "Microphone"
        case .microphoneNotConnected: return "not connected"
        case .openRecordingsFolder: return "Open Recordings Folder"
        case .settingsEllipsis: return "Settings…"
        case .preparingFile: return "Preparing the file…"
        case .openSystemSettings: return "Open System Settings"
        case .settingsTitle: return "Nastro Settings"
        case .settingsFolder: return "Recordings folder"
        case .chooseFolder: return "Choose…"
        case .settingsMaxResolution: return "Maximum resolution"
        case .settingsFramesPerSecond: return "Frames per second"
        case .settingsKeepSeparateTracks: return "Keep separate audio tracks"
        case .settingsMicrophone: return "Microphone"
        case .systemDefaultMicrophone: return "System default"
        case .settingsHotKey: return "Shortcut"
        case .settingsAppliesNextRecording: return "Recording in progress: these settings apply from the next recording."
        case .settingsSummary: return "Summary"
        case .settingsServerURL: return "Server address"
        case .settingsModel: return "Model"
        case .settingsAPIKey: return "API key (optional)"
        case .settingsServerHint: return "Local: http://127.0.0.1:8001/v1 (llama.cpp). Nastro does not start the server: start it before summarizing."
        case .settingsRemoteWarning: return "With a remote address the call text leaves your Mac."
        case .hotKeyInUseMenu: return "The shortcut %@ is used by another app. You can change it in Settings."
        case .hotKeyInUseSettings: return "%@ is used by another app: choose another letter."
        case .relaunchAfterGranting: return "After granting it, quit and reopen Nastro."
        case .quitNastro: return "Quit Nastro"
        case .recordingSaved: return "Recording saved"
        case .recordingEmpty: return "Empty recording: no file was saved."
        case .recordingStopped: return "Recording stopped"
        case .stoppedSourceLost: return "The recorded source is no longer available."
        case .stoppedStreamError: return "Capture stopped unexpectedly."
        case .stoppedDiskFull: return "The disk is almost full."
        case .writeFailed: return "An error occurred while writing the recording."
        case .finalizeFailed: return "Could not prepare the final file."
        case .noRoomToFinalize: return "Not enough free space to prepare the final file."
        case .workFileKept: return "The work file was kept and will be recovered at the next launch:"
        case .recordingRecovered: return "Recording recovered"
        case .recordingDamaged: return "Interrupted recording could not be recovered"
        case .recoveryNoRoom: return "Not enough space to prepare %@; free some space and reopen Nastro."
        case .startFailed: return "Could not start recording"
        case .noFirstFrame: return "No image from the screen within 5 seconds: recording cancelled."
        case .warningSystemAudioSilent: return "System audio is silent"
        case .warningMicrophoneSilent: return "Microphone is silent"
        case .warningMicrophoneLost: return "Microphone disconnected"
        case .warningSystemAudioNotRecorded: return "System audio is not being recorded"
        case .warningMicrophoneNotRecorded: return "The microphone is not being recorded: stop and start a new recording"
        case .warningAudioDropouts: return "Some audio was lost"
        case .noAudio: return "No audio within 5 seconds: recording cancelled."
        case .recordingNotSaved: return "The recording could not be saved."
        case .problemScreenPermission: return "Screen Recording permission is required."
        case .problemMicrophonePermission: return "Microphone permission is required."
        case .problemFolder: return "The recordings folder is not writable."
        case .problemSourceUnavailable: return "The chosen source is not available."
        case .problemOther: return "Unexpected error while starting the recording."
        case .summarizeEllipsis: return "Transcribe and summarize…"
        case .summaryPreparing: return "Preparing…"
        case .summaryTranscribing: return "Transcribing %d%%"
        case .summarySummarizingOne: return "Summarizing…"
        case .summarySummarizing: return "Summary %d of %d…"
        case .summaryReady: return "Summary ready"
        case .transcriptSavedSummaryFailed: return "Transcript saved, summary failed."
        case .cancel: return "Cancel"
        case .errNoAudio: return "The recording has no readable audio."
        case .errNoSpeech: return "No speech was heard in the recording."
        case .errSpeechModel: return "Italian speech recognition is not available."
        case .errCannotWrite: return "Cannot write next to the recording."
        case .errInvalidURL: return "Invalid server address."
        case .errUnreachable: return "Model not reachable at %@: is the LLM server running?"
        case .errHTTP: return "Error %d from the server: %@"
        case .errServer: return "Error from the server."
        case .errEmptyReply: return "The model replied with no text."
        }
    }
}
