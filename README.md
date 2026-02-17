# kokoro-say

Personal Nix flake wrapping [kokoro-onnx](https://github.com/thewh1teagle/kokoro-onnx) as a local text-to-speech CLI tool.

This is for my own use. No support provided.

## Usage

```bash
nix run . -- "Hello world"
nix run . -- -o output.wav "Save to file"
nix run . -- -v bf_emma -l en-gb "British voice"
nix run . -- --list-voices
echo "piped text" | nix run .
```

## License

MIT
