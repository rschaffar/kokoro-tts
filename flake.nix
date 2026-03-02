{
  description = "kokoro-say: Local text-to-speech CLI powered by Kokoro";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      # Override datasette to skip its failing test_max_csv_mb test
      # (SQLite compatibility issue with datasette 0.65.2).
      # Dependency chain: phonemizer-fork → segments → csvw → frictionless → datasette
      python = pkgs.python312.override {
        packageOverrides = _final: prev: {
          datasette = prev.datasette.overrideAttrs { doCheck = false; };
        };
      };
      pyPkgs = python.pkgs;

      # -- Model files (cached in Nix store) -----------------------------------

      kokoroModel = pkgs.fetchurl {
        url = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx";
        hash = "sha256-fV347PfUsYeAFaMmhgU/0O6+K8N3I0YIdkzA7zY2psU=";
      };

      kokoroVoices = pkgs.fetchurl {
        url = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin";
        hash = "sha256-vKYQuDCOjZnzLm/kGX5+wBZ5Jk7+0MrJFA/pwp8fv30=";
      };

      # -- Stub espeakng_loader ------------------------------------------------
      # The real package bundles 18 MB of espeak-ng binaries.
      # On NixOS we use the system espeak-ng, so we provide a tiny stub that
      # returns the right paths.

      espeakng-loader = pyPkgs.buildPythonPackage {
        pname = "espeakng-loader";
        version = "0.2.4";
        format = "setuptools";

        src = pkgs.writeTextDir "setup.py" ''
          from setuptools import setup, find_packages
          setup(
              name="espeakng_loader",
              version="0.2.4",
              packages=find_packages(),
          )
        '';

        postUnpack = ''
          mkdir -p $sourceRoot/espeakng_loader
          cat > $sourceRoot/espeakng_loader/__init__.py << 'PYEOF'
          import os

          def get_data_path():
              return os.environ.get(
                  "ESPEAK_NG_DATA",
                  "${pkgs.espeak-ng}/share/espeak-ng-data",
              )

          def get_library_path():
              return os.environ.get(
                  "PHONEMIZER_ESPEAK_LIBRARY",
                  "${pkgs.espeak-ng}/lib/libespeak-ng.so",
              )
          PYEOF
        '';

        doCheck = false;
        meta.description = "NixOS stub for espeakng_loader pointing to system espeak-ng";
      };

      # -- phonemizer-fork (replaces the phonemizer module) --------------------

      phonemizer-fork = pyPkgs.buildPythonPackage {
        pname = "phonemizer-fork";
        version = "3.3.2";
        pyproject = true;

        src = pkgs.fetchPypi {
          pname = "phonemizer_fork";
          version = "3.3.2";
          hash = "sha256-EOFugn0EQ7CHBi4htV6AXACYnPE0Oy6B5zTK5fbAz2k=";
        };

        build-system = [ pyPkgs.hatchling ];

        dependencies = [
          pyPkgs.joblib
          pyPkgs.segments
          pyPkgs.attrs
          pyPkgs.dlinfo
          pyPkgs.typing-extensions
        ];

        # Tests require espeak-ng binary at build time
        doCheck = false;

        meta.description = "Fork of phonemizer for kokoro-onnx TTS";
      };

      # -- kokoro-onnx ---------------------------------------------------------

      kokoro-onnx = pyPkgs.buildPythonPackage {
        pname = "kokoro-onnx";
        version = "0.5.0";
        pyproject = true;

        src = pkgs.fetchPypi {
          pname = "kokoro_onnx";
          version = "0.5.0";
          hash = "sha256-W+sV8IXigo7Y1JP3ksB5r4VxA6stzqoeESsXYFh6yWo=";
        };

        build-system = [ pyPkgs.hatchling ];

        dependencies = [
          pyPkgs.numpy
          pyPkgs.onnxruntime
          espeakng-loader
          phonemizer-fork
        ];

        doCheck = false;

        meta.description = "TTS with kokoro and ONNX runtime";
      };

      # -- Python environment with all deps ------------------------------------

      pythonEnv = python.withPackages (ps: [
        kokoro-onnx
        ps.soundfile
      ]);

      # -- The CLI wrapper -----------------------------------------------------

      kokoro-say = pkgs.stdenvNoCC.mkDerivation {
        pname = "kokoro-say";
        version = "0.1.0";

        src = ./.;
        dontBuild = true;

        nativeBuildInputs = [ pkgs.makeWrapper ];

        installPhase = ''
          mkdir -p $out/bin
          # Use the Python from our environment as the interpreter
          cat > $out/bin/kokoro-say << WRAPPER
          #!${pythonEnv}/bin/python3
          WRAPPER
          tail -n +2 kokoro-say.py >> $out/bin/kokoro-say
          chmod +x $out/bin/kokoro-say

          wrapProgram $out/bin/kokoro-say \
            --prefix PATH : ${
              pkgs.lib.makeBinPath [
                pkgs.mpv
                pkgs.espeak-ng
              ]
            } \
            --set KOKORO_MODEL "${kokoroModel}" \
            --set KOKORO_VOICES "${kokoroVoices}" \
            --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath [ pkgs.espeak-ng ]}"
        '';

        meta = {
          description = "Local text-to-speech CLI powered by Kokoro";
          mainProgram = "kokoro-say";
        };
      };
    in
    {
      packages.${system}.default = kokoro-say;

      apps.${system}.default = {
        type = "app";
        program = "${kokoro-say}/bin/kokoro-say";
      };
    };
}
