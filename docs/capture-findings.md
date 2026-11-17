# Capture API findings (NastroProbe)

Measured on macOS 27.3, 2026-11-17, with `swift run NastroProbe <subcommand>`.

A: no — window filter (SCContentFilter(desktopIndependentWindow:), no Finder window on screen so the first on-screen window of another app, "Windows App", was used): afplay Glass.aiff played at 1 s, 320 audio buffers arrived but peak = -inf dB (threshold -40 dB). Window-scoped capture does not carry system-wide audio; the same sound reached the display-filtered stream at -14.1 dB (see B). Caveat: Finder window was not available; the result depends on the window's owning app not playing the sound.
B: yes — display filter, 2x2 px, 1 fps, no .screen output: 311 system-audio buffers (peak -14.1 dB) and 578 microphone buffers (peak -20.4 dB), 0 video frames.
C: yes — first system-audio pts 158408.611 s, first microphone pts 158408.694 s, delta 82.9 ms (< 500 ms): same time base. Microphone format: 48000 Hz, 1 ch, float32 interleaved; system audio: 48000 Hz, 2 ch, float32 non-interleaved.
D: yes — crash-write (1280x720@30 HEVC + stereo 48 kHz AAC via MovieWriter) killed with kill -9 at 25 s (exit 137): file 417343 bytes opens with AVURLAsset, 1 video track, 1 audio track, duration 22.07 s (>= 10 s).
