# Capture API findings (NastroProbe)

Measured on macOS 27.3, 2026-11-17, with `swift run NastroProbe <subcommand>`.

A: no — window filter (SCContentFilter(desktopIndependentWindow:), no Finder window on screen so the first on-screen window of another app, "Windows App", was used): afplay Glass.aiff played at 1 s, 320 audio buffers arrived but peak = -inf dB (threshold -40 dB). Window-scoped capture does not carry system-wide audio; the same sound reached the display-filtered stream at -14.1 dB (see B). Caveat: Finder window was not available; the result depends on the window's owning app not playing the sound.
B: yes — display filter, 2x2 px, 1 fps, no .screen output: 311 system-audio buffers (peak -14.1 dB) and 578 microphone buffers (peak -20.4 dB), 0 video frames.
C: yes — first system-audio pts 158408.611 s, first microphone pts 158408.694 s, delta 82.9 ms (< 500 ms): same time base. Microphone format: 48000 Hz, 1 ch, float32 interleaved; system audio: 48000 Hz, 2 ch, float32 non-interleaved.
D: yes — crash-write (1280x720@30 HEVC + stereo 48 kHz AAC via MovieWriter) killed with kill -9 at 25 s (exit 137): file 417343 bytes opens with AVURLAsset, 1 video track, 1 audio track, duration 22.07 s (>= 10 s).

## AVAssetWriter and gaps in audio timestamps

Measured 2026-11-17 by `MovieWriterTests.testMissingAudioBufferKeepsLaterAudioInPlace` (synthetic media, no capture): with 0.49 s of system audio withheld in the middle of a recording (0.768…1.259 s), a tone that starts at 1.515 s was found at 1.024 s in the written file. `AVAssetWriter` (AAC encoding from PCM) joins audio buffers end to end and ignores the gap, so every lost buffer would shift that voice earlier for the rest of the file. Since then `MovieWriter` fills any gap longer than one buffer with silence in the source's format, and queues (instead of dropping) audio the input is momentarily not ready for; with the fix the tone is at its original time (±50 ms).

## Known limitation (not fixed)

A microphone whose first sample arrives more than 2 s after the recording starts, or whose audio format changes mid-recording (for example AirPods connecting during the call, which switches the input device and its sample rate), stops being recorded for the rest of that recording: `MovieWriter` creates each audio track from the source's first format and cannot add or change a track once writing has started. The app shows a red warning ("The microphone is not being recorded: stop and start a new recording") in the panel and in the menu bar, and sends a notification. The remedy is to stop and start a new recording. Converting every source to a fixed format before the writer would remove the limitation; that change is deferred.
