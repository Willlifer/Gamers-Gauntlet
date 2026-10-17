"""G49: Ogg Vorbis twins of the sound effects and barks, for the browser build only.

Desktop keeps playing the .wav files (Godot's QOA); the web build leaves the
.wav files out (export_presets.cfg, preset "Web") and plays the .ogg twin
beside each one (BWSfx.path_of, BWBarks.clip_path, MmoAudio). Barks are
folded to mono. Re-run after adding or remaking sounds, then
`godot --headless --path . --import` and the web build.

    python game/tools/audio/web_ogg.py
"""
import glob
import os

import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.normpath(os.path.join(HERE, "..", ".."))
DIRS = ["audio/sfx", "audio/barks", "audio/sfx/fps"]      # G62: the FPS's own sounds (FpsAudio)
QUALITY = 0.45          # libsndfile's Vorbis quality, 0..1 (compression_level = 1 - quality)


def main() -> None:
    made = 0
    before = after = 0
    for d in DIRS:
        for wav in sorted(glob.glob(os.path.join(GAME, d, "*.wav"))):
            ogg = wav[:-4] + ".ogg"
            data, rate = sf.read(wav, always_2d=True)
            if d.endswith("barks") and data.shape[1] > 1:
                data = data.mean(axis=1, keepdims=True)
            sf.write(ogg, data, rate, format="OGG", subtype="VORBIS", compression_level=1.0 - QUALITY)
            before += os.path.getsize(wav)
            after += os.path.getsize(ogg)
            made += 1
    print(f"web_ogg: {made} files, wav {before / 1e6:.1f} MB -> ogg {after / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
