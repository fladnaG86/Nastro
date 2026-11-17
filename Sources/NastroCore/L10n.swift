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
        // Notifications
        case recordingSaved, recordingEmpty, recordingStopped
        case stoppedSourceLost, stoppedStreamError, stoppedDiskFull
        case writeFailed, finalizeFailed, noRoomToFinalize, workFileKept
        case recordingRecovered, recordingDamaged
        case startFailed, noFirstFrame
        // Warnings
        case warningSystemAudioSilent, warningMicrophoneSilent, warningMicrophoneLost
        case warningSystemAudioNotRecorded, warningMicrophoneNotRecorded
        // Start problems
        case problemScreenPermission, problemMicrophonePermission, problemFolder
        case problemSourceUnavailable, problemOther
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
        case .startFailed: return "Impossibile avviare la registrazione"
        case .noFirstFrame: return "Nessuna immagine dallo schermo entro 5 secondi: registrazione annullata."
        case .warningSystemAudioSilent: return "Audio di sistema muto"
        case .warningMicrophoneSilent: return "Microfono muto"
        case .warningMicrophoneLost: return "Microfono scollegato"
        case .warningSystemAudioNotRecorded: return "L'audio di sistema non viene registrato"
        case .warningMicrophoneNotRecorded: return "Il microfono non viene registrato"
        case .problemScreenPermission: return "Serve il permesso di Registrazione schermo."
        case .problemMicrophonePermission: return "Serve il permesso di accesso al Microfono."
        case .problemFolder: return "La cartella delle registrazioni non è scrivibile."
        case .problemSourceUnavailable: return "La sorgente scelta non è disponibile."
        case .problemOther: return "Errore imprevisto all'avvio della registrazione."
        }
    }

    private static func english(_ key: Key) -> String {
        switch key {
        case .appName: return "Nastro"
        case .quit: return "Quit"
        case .startRecording: return "Start Recording"
        case .stopRecording: return "Stop Recording"
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
        case .startFailed: return "Could not start recording"
        case .noFirstFrame: return "No image from the screen within 5 seconds: recording cancelled."
        case .warningSystemAudioSilent: return "System audio is silent"
        case .warningMicrophoneSilent: return "Microphone is silent"
        case .warningMicrophoneLost: return "Microphone disconnected"
        case .warningSystemAudioNotRecorded: return "System audio is not being recorded"
        case .warningMicrophoneNotRecorded: return "The microphone is not being recorded"
        case .problemScreenPermission: return "Screen Recording permission is required."
        case .problemMicrophonePermission: return "Microphone permission is required."
        case .problemFolder: return "The recordings folder is not writable."
        case .problemSourceUnavailable: return "The chosen source is not available."
        case .problemOther: return "Unexpected error while starting the recording."
        }
    }
}
