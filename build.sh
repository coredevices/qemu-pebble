#!/bin/bash
# Build script for Pebble QEMU
# Overlays Pebble device model files onto QEMU submodule, patches build system, and builds.
#
# Usage:
#   bash build.sh [--clean]
#
# Options:
#   --clean   Reset QEMU submodule to clean state before building
#
# Prerequisites:
#   macOS:        brew install sdl2 pixman glib pkg-config
#   Debian/Ubuntu: sudo apt install libsdl2-dev libpixman-1-dev libglib2.0-dev \
#                                   pkg-config ninja-build python3-venv build-essential
set -euo pipefail

OS="$(uname -s)"
ARCH="$(uname -m)"
echo "=== Host: ${OS} ${ARCH} ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QEMU_SRC="${SCRIPT_DIR}/qemu"
BUILD_DIR="${QEMU_SRC}/build"
VENV_DIR="${SCRIPT_DIR}/.venv"
PEBBLE_DIR="${SCRIPT_DIR}/pebble"

# Parse args
CLEAN=false
for arg in "$@"; do
    case "$arg" in
        --clean) CLEAN=true ;;
        *) echo "Unknown option: $arg"; echo "Usage: $0 [--clean]"; exit 1 ;;
    esac
done

# Init submodule if needed
if [ ! -f "${QEMU_SRC}/configure" ]; then
    echo "=== Initializing QEMU submodule ==="
    git submodule update --init --depth 1
fi

# Clean if requested
if [ "$CLEAN" = true ]; then
    echo "=== Cleaning QEMU submodule ==="
    git -C "${QEMU_SRC}" checkout .
    rm -rf "${BUILD_DIR}"
fi

echo "=== Overlaying Pebble files onto QEMU ==="

# Copy include files
mkdir -p "${QEMU_SRC}/include/hw/arm"
cp "${PEBBLE_DIR}/include/hw/arm/stm32_common.h" "${QEMU_SRC}/include/hw/arm/"
cp "${PEBBLE_DIR}/include/hw/arm/pebble.h" "${QEMU_SRC}/include/hw/arm/"
cp "${PEBBLE_DIR}/include/hw/arm/stm32_clktree.h" "${QEMU_SRC}/include/hw/arm/"
cp "${PEBBLE_DIR}/include/hw/arm/pebble_generic.h" "${QEMU_SRC}/include/hw/arm/"
cp "${PEBBLE_DIR}/include/hw/arm/pebble_simple_uart.h" "${QEMU_SRC}/include/hw/arm/"
cp "${PEBBLE_DIR}/include/hw/arm/pebble_gpio.h" "${QEMU_SRC}/include/hw/arm/"

# Copy hw source files (including headers in source dirs)
for dir in arm misc char ssi timer dma display gpio block; do
    if [ -d "${PEBBLE_DIR}/hw/${dir}" ]; then
        mkdir -p "${QEMU_SRC}/hw/${dir}"
        for f in "${PEBBLE_DIR}/hw/${dir}"/*; do
            [ -f "$f" ] && cp "$f" "${QEMU_SRC}/hw/${dir}/" && echo "  -> hw/${dir}/$(basename "$f")"
        done
    fi
done

# === Apply source patches ===
echo "  Applying patches..."
for p in "${PEBBLE_DIR}/patches/"*.patch; do
    [ -f "$p" ] || continue
    # --forward skips already-applied patches; || true so we don't fail
    patch -d "${QEMU_SRC}" -p1 --forward < "$p" || true
done

# === Patch Kconfig ===
KCONFIG="${QEMU_SRC}/hw/arm/Kconfig"
if ! grep -q "CONFIG_PEBBLE" "${KCONFIG}"; then
    echo "  Patching hw/arm/Kconfig..."
    cat >> "${KCONFIG}" << 'EOF'

config PEBBLE
    bool
    default y
    depends on TCG && ARM
    imply ARM_V7M
    select ARM_V7M
    select PFLASH_CFI02
EOF
fi

# === Patch default.mak ===
DEFAULT_MAK="${QEMU_SRC}/configs/devices/arm-softmmu/default.mak"
if ! grep -q "CONFIG_PEBBLE" "${DEFAULT_MAK}"; then
    echo "CONFIG_PEBBLE=y" >> "${DEFAULT_MAK}"
fi

# === Patch meson.build files ===
# Helper: append to meson file if marker not present
patch_meson() {
    local file="$1"
    local marker="$2"
    local content="$3"
    if ! grep -q "${marker}" "${file}"; then
        echo "  Patching ${file}..."
        echo "" >> "${file}"
        echo "${content}" >> "${file}"
    fi
}

# hw/arm/meson.build — QEMU 10.1 uses arm_common_ss (not arm_ss)
patch_meson "${QEMU_SRC}/hw/arm/meson.build" "CONFIG_PEBBLE" \
"arm_common_ss.add(when: 'CONFIG_PEBBLE', if_true: files(
  'pebble.c',
  'pebble_robert.c',
  'pebble_silk.c',
  'pebble_control.c',
  'pebble_stm32f4xx_soc.c',
  'pebble_stm32f2xx_soc.c',
))"

# hw/arm/meson.build — generic Pebble machines (new platforms)
patch_meson "${QEMU_SRC}/hw/arm/meson.build" "pebble_generic" \
"arm_common_ss.add(when: 'CONFIG_PEBBLE', if_true: files(
  'pebble_generic.c',
))"

# hw/misc/meson.build — generic Pebble peripherals
patch_meson "${QEMU_SRC}/hw/misc/meson.build" "pebble_simple_uart" \
"system_ss.add(when: 'CONFIG_PEBBLE', if_true: files(
  'pebble_simple_uart.c',
  'pebble_sysctrl.c',
  'pebble_rtc.c',
  'pebble_timer.c',
  'pebble_extflash.c',
  'pebble_touch.c',
  'pebble_audio.c',
))"

# hw/misc/meson.build
patch_meson "${QEMU_SRC}/hw/misc/meson.build" "stm32_pebble" \
"system_ss.add(when: 'CONFIG_PEBBLE', if_true: files(
  'stm32_pebble_rcc.c',
  'stm32_pebble_clktree.c',
  'stm32_pebble_common.c',
  'stm32_pebble_exti.c',
  'stm32_pebble_syscfg.c',
  'stm32_pebble_adc.c',
  'stm32_pebble_pwr.c',
  'stm32_pebble_crc.c',
  'stm32_pebble_flash.c',
  'stm32_pebble_dummy.c',
  'stm32_pebble_i2c.c',
))"

# hw/timer/meson.build
patch_meson "${QEMU_SRC}/hw/timer/meson.build" "stm32_pebble" \
"system_ss.add(when: 'CONFIG_PEBBLE', if_true: files(
  'stm32_pebble_tim.c',
  'stm32_pebble_rtc.c',
))"

# hw/ssi/meson.build
patch_meson "${QEMU_SRC}/hw/ssi/meson.build" "stm32_pebble" \
"system_ss.add(when: 'CONFIG_PEBBLE', if_true: files(
  'stm32_pebble_spi.c',
  'stm32_pebble_qspi.c',
))"

# hw/block/meson.build
patch_meson "${QEMU_SRC}/hw/block/meson.build" "pebble_mx25u" \
"system_ss.add(when: 'CONFIG_PEBBLE', if_true: files('pebble_mx25u.c'))"

# hw/dma/meson.build
patch_meson "${QEMU_SRC}/hw/dma/meson.build" "stm32_pebble" \
"system_ss.add(when: 'CONFIG_PEBBLE', if_true: files('stm32_pebble_dma.c'))"

# hw/display/meson.build
patch_meson "${QEMU_SRC}/hw/display/meson.build" "pebble_snowy" \
"system_ss.add(when: 'CONFIG_PEBBLE', if_true: files(
  'pebble_snowy_display.c',
  'pebble_sm_lcd.c',
  'pebble_display.c',
))"

# hw/gpio/meson.build
patch_meson "${QEMU_SRC}/hw/gpio/meson.build" "stm32_pebble" \
"system_ss.add(when: 'CONFIG_PEBBLE', if_true: files('stm32_pebble_gpio.c'))"

# hw/gpio/meson.build — generic Pebble GPIO
patch_meson "${QEMU_SRC}/hw/gpio/meson.build" "'pebble_gpio.c'" \
"system_ss.add(when: 'CONFIG_PEBBLE', if_true: files('pebble_gpio.c'))"

# hw/char/meson.build — Pebble's own UART (type "stm32-uart", no conflict
# with mainline's "stm32f2xx-usart")
patch_meson "${QEMU_SRC}/hw/char/meson.build" "stm32_pebble_uart" \
"system_ss.add(when: 'CONFIG_PEBBLE', if_true: files('stm32_pebble_uart.c'))"

echo ""
echo "=== Building ==="

# Ensure venv
if [ ! -d "${VENV_DIR}" ]; then
    python3 -m venv "${VENV_DIR}"
    "${VENV_DIR}/bin/pip" install meson ninja distlib tomli
fi

export PATH="${VENV_DIR}/bin:$PATH"

# Build inside qemu/build/
mkdir -p "${BUILD_DIR}"

# Reconfigure to pick up new files (delete build.ninja to force)
rm -f "${BUILD_DIR}/build.ninja"

cd "${BUILD_DIR}"

# Linux gets a fully static binary so the dist tarball doesn't need bundled libs.
# macOS dynamically links and ships dylibs alongside the binary (static linking
# of system frameworks isn't supported on Darwin).
CONFIGURE_EXTRA=()
if [ "$OS" = "Linux" ]; then
    CONFIGURE_EXTRA+=(--static --disable-pie)
fi

"${QEMU_SRC}/configure" \
    --target-list=arm-softmmu \
    --python="${VENV_DIR}/bin/python3" \
    --enable-sdl \
    --disable-gnutls \
    --disable-libssh \
    --disable-libusb \
    --disable-usb-redir \
    --disable-slirp \
    --disable-zstd \
    --disable-png \
    --disable-capstone \
    --disable-gio \
    --disable-vnc-jpeg \
    --disable-gcrypt \
    --disable-nettle \
    --disable-werror \
    ${CONFIGURE_EXTRA[@]+"${CONFIGURE_EXTRA[@]}"} 2>&1 | tail -5

if [ "$OS" = "Darwin" ]; then
    NPROC=$(sysctl -n hw.ncpu)
else
    NPROC=$(nproc)
fi
ninja -j"${NPROC}" qemu-system-arm 2>&1

echo ""
echo "=== Build complete ==="
echo "Binary: ${BUILD_DIR}/qemu-system-arm"

# === Bundle distributable ===
DIST_DIR="${SCRIPT_DIR}/dist"
echo ""
echo "=== Bundling distributable ==="
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}/bin"

cp "${BUILD_DIR}/qemu-system-arm" "${DIST_DIR}/bin/qemu-pebble"

if [ "$OS" = "Darwin" ]; then
    mkdir -p "${DIST_DIR}/lib"
    # Resolve Homebrew dylibs (direct + transitive deps).
    # `brew --prefix <pkg>` works on both arm64 (/opt/homebrew) and x86_64 (/usr/local).
    for lib in \
        "$(brew --prefix pixman)/lib/libpixman-1.0.dylib" \
        "$(brew --prefix sdl2)/lib/libSDL2-2.0.0.dylib" \
        "$(brew --prefix glib)/lib/libglib-2.0.0.dylib" \
        "$(brew --prefix glib)/lib/libgmodule-2.0.0.dylib" \
        "$(brew --prefix gettext)/lib/libintl.8.dylib" \
        "$(brew --prefix pcre2)/lib/libpcre2-8.0.dylib"; do
        if [ -f "$lib" ]; then
            cp "$lib" "${DIST_DIR}/lib/"
            echo "  -> lib/$(basename "$lib")"
        else
            echo "  WARNING: $lib not found"
        fi
    done
else
    # Linux build is fully static — no bundled libs needed.
    echo "  static build — no libs to bundle"
fi

echo ""
echo "=== Distributable ready ==="
echo "  ${DIST_DIR}/bin/qemu-pebble"
[ -d "${DIST_DIR}/lib" ] && echo "  ${DIST_DIR}/lib/"
