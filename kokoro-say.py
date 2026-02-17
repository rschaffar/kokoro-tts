#!/usr/bin/env python3
"""kokoro-say: Local text-to-speech CLI powered by Kokoro."""

import argparse
import os
import subprocess
import sys
import tempfile

import soundfile as sf
from kokoro_onnx import Kokoro


def get_kokoro():
    model_path = os.environ["KOKORO_MODEL"]
    voices_path = os.environ["KOKORO_VOICES"]
    return Kokoro(model_path, voices_path)


def main():
    parser = argparse.ArgumentParser(
        prog="kokoro-say",
        description="Local text-to-speech powered by Kokoro",
    )
    parser.add_argument("text", nargs="*", help="Text to speak (reads stdin if omitted)")
    parser.add_argument(
        "-v", "--voice", default="af_sarah", help="Voice name (default: af_sarah)"
    )
    parser.add_argument(
        "-s", "--speed", type=float, default=1.0, help="Speed 0.5-2.0 (default: 1.0)"
    )
    parser.add_argument(
        "-l", "--lang", default="en-us", help="Language code (default: en-us)"
    )
    parser.add_argument(
        "-o", "--output", metavar="FILE", help="Save to WAV file instead of playing"
    )
    parser.add_argument(
        "--list-voices", action="store_true", help="List available voices and exit"
    )

    args = parser.parse_args()

    kokoro = get_kokoro()

    if args.list_voices:
        for voice in kokoro.get_voices():
            print(voice)
        return

    # Get text from args or stdin
    if args.text:
        text = " ".join(args.text)
    elif not sys.stdin.isatty():
        text = sys.stdin.read().strip()
    else:
        parser.error("No text provided. Pass text as arguments or pipe via stdin.")

    if not text:
        parser.error("Empty text.")

    samples, sample_rate = kokoro.create(
        text, voice=args.voice, speed=args.speed, lang=args.lang
    )

    if args.output:
        sf.write(args.output, samples, sample_rate)
        print(f"Saved to {args.output}", file=sys.stderr)
    else:
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=True) as tmp:
            sf.write(tmp.name, samples, sample_rate)
            try:
                subprocess.run(
                    ["mpv", "--no-terminal", "--no-video", tmp.name],
                    check=True,
                )
            except FileNotFoundError:
                print(
                    "Error: mpv not found. Install mpv or use --output to save to file.",
                    file=sys.stderr,
                )
                sys.exit(1)


if __name__ == "__main__":
    main()
