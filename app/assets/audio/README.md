# assets/audio

`silence.wav` is 1.5 seconds of 16-bit mono silence at 8 kHz, generated with
Python's `wave` module. iOS plays it through `AVAudioPlayer` just before a
spoken turn cue (`app.velorki/audio` → `playLeadIn`): a Bluetooth headset that
has let its A2DP link go idle needs about a second to come back, and without
the lead-in the first syllables of the cue are lost or scrambled. Nothing
plays between cues.
