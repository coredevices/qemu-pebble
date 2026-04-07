# qemu-pebble

QEMU for emulating Pebble smartwatches. Pebble device model files are stored separately and overlaid onto a clean [QEMU stable-10.1](https://github.com/qemu/qemu/tree/stable-10.1) submodule at build time.

## Supported machines

| Machine | Flag |
|---|---|
| Aplite | `-machine pebble-bb2` |
| Basalt | `-machine pebble-snowy-bb` |
| Chalk | `-machine pebble-s4-bb` |
| Diorite | `-machine pebble-silk-bb` |
| Emery | `-machine pebble-snowy-emery-bb` |
| Gabbro | `-machine pebble-spalding-gabbro-bb` |

## Prerequisites

- macOS or Linux
- Python 3
- SDL2 (`brew install sdl2` on macOS)

## Build

```bash
bash build.sh
```

This will:
1. Initialize the QEMU submodule (if needed)
2. Overlay Pebble device files onto the QEMU source tree
3. Patch meson.build/Kconfig for the Pebble machine types
4. Apply the pflash CFI02 patch (Macronix NOR flash support)
5. Build `qemu-system-arm`

Use `bash build.sh --clean` to reset the submodule before rebuilding.