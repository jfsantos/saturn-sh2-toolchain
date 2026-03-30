#!/usr/bin/env bash
# build-toolchain.sh — Build sh2eb-elf cross-compiler for Sega Saturn
#
# Native ARM64 macOS + Linux support.
# Based on kentosama/sh2-elf-gcc structure, updated for GCC 14.2.0 + C++23.
#
# Usage:
#   ./build-toolchain.sh              Build everything
#   ./build-toolchain.sh binutils     Build binutils only
#   ./build-toolchain.sh gcc1         Build GCC stage 1 only
#   ./build-toolchain.sh newlib       Build newlib only
#   ./build-toolchain.sh gcc2         Build GCC stage 2 (final)
#   ./build-toolchain.sh clean        Remove build artifacts
#
# Prerequisites (macOS):
#   brew install gmp mpfr libmpc isl texinfo wget
#
# Prerequisites (Linux):
#   apt install build-essential texinfo wget libgmp-dev libmpfr-dev libmpc-dev libisl-dev

set -e

# ── Configuration ─────────────────────────────────────────────────────────────

BINUTILS_VERSION="2.43"
GCC_VERSION="14.2.0"
NEWLIB_VERSION="4.4.0.20231231"

TARGET="sh-elf"
PROGRAM_PREFIX="sh2eb-elf-"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$SCRIPT_DIR/toolchain}"
BUILD_DIR="$SCRIPT_DIR/build"
SOURCE_DIR="$SCRIPT_DIR/source"
DOWNLOAD_DIR="$SCRIPT_DIR/download"

# ── Platform detection ────────────────────────────────────────────────────────

detect_platform() {
    local arch=$(uname -m)
    local os=$(uname -s)

    case "$os" in
        Darwin)
            HOST_TRIPLET="${arch}-apple-darwin$(uname -r)"
            NPROC=$(sysctl -n hw.ncpu)
            # Homebrew paths for dependencies
            if [ -d "/opt/homebrew" ]; then
                BREW_PREFIX="/opt/homebrew"
            elif [ -d "/usr/local" ]; then
                BREW_PREFIX="/usr/local"
            fi
            export CFLAGS_FOR_HOST="-I${BREW_PREFIX}/include"
            export LDFLAGS_FOR_HOST="-L${BREW_PREFIX}/lib"
            export CFLAGS="-I${BREW_PREFIX}/include"
            export CXXFLAGS="-I${BREW_PREFIX}/include"
            export LDFLAGS="-L${BREW_PREFIX}/lib"
            # texinfo from Homebrew isn't in PATH by default
            if [ -d "${BREW_PREFIX}/opt/texinfo/bin" ]; then
                export PATH="${BREW_PREFIX}/opt/texinfo/bin:$PATH"
            fi
            ;;
        Linux)
            HOST_TRIPLET="${arch}-pc-linux-gnu"
            NPROC=$(nproc)
            ;;
        *)
            echo "ERROR: Unsupported OS: $os"
            exit 1
            ;;
    esac

    echo "Host: $HOST_TRIPLET ($NPROC cores)"
}

# ── Helpers ───────────────────────────────────────────────────────────────────

download() {
    local url="$1"
    local file="$2"

    if [ -f "$file" ]; then
        echo "  already downloaded: $(basename "$file")"
        return
    fi

    echo "  downloading: $(basename "$file")"
    mkdir -p "$(dirname "$file")"

    if command -v wget &>/dev/null; then
        wget -q --show-progress -O "$file" "$url"
    elif command -v curl &>/dev/null; then
        curl -L -# -o "$file" "$url"
    else
        echo "ERROR: Neither wget nor curl found"
        exit 1
    fi
}

# ── Build steps ───────────────────────────────────────────────────────────────

build_binutils() {
    echo "=== Building binutils $BINUTILS_VERSION ==="

    local archive="$DOWNLOAD_DIR/binutils-${BINUTILS_VERSION}.tar.xz"
    download "https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz" "$archive"

    echo "  extracting..."
    mkdir -p "$SOURCE_DIR"
    if [ ! -d "$SOURCE_DIR/binutils-${BINUTILS_VERSION}" ]; then
        tar xf "$archive" -C "$SOURCE_DIR"
    fi

    echo "  configuring..."
    local builddir="$BUILD_DIR/binutils"
    rm -rf "$builddir"
    mkdir -p "$builddir"
    cd "$builddir"

    "$SOURCE_DIR/binutils-${BINUTILS_VERSION}/configure" \
        --build="$HOST_TRIPLET" \
        --host="$HOST_TRIPLET" \
        --target="$TARGET" \
        --program-prefix="$PROGRAM_PREFIX" \
        --prefix="$INSTALL_DIR" \
        --with-cpu=m2 \
        --with-system-zlib \
        --disable-nls \
        --disable-werror \
        --disable-shared \
        --disable-debug \
        --disable-dependency-tracking \
        --disable-sim \
        --disable-gdb

    echo "  building..."
    make -j"$NPROC"

    echo "  installing..."
    make install

    echo "  binutils done."
}

build_gcc_stage1() {
    echo "=== Building GCC $GCC_VERSION (stage 1 — bootstrap) ==="

    local archive="$DOWNLOAD_DIR/gcc-${GCC_VERSION}.tar.xz"
    download "https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz" "$archive"

    echo "  extracting..."
    mkdir -p "$SOURCE_DIR"
    if [ ! -d "$SOURCE_DIR/gcc-${GCC_VERSION}" ]; then
        tar xf "$archive" -C "$SOURCE_DIR"
    fi

    echo "  configuring..."
    local builddir="$BUILD_DIR/gcc-stage1"
    rm -rf "$builddir"
    mkdir -p "$builddir"
    cd "$builddir"

    "$SOURCE_DIR/gcc-${GCC_VERSION}/configure" \
        --build="$HOST_TRIPLET" \
        --host="$HOST_TRIPLET" \
        --target="$TARGET" \
        --program-prefix="$PROGRAM_PREFIX" \
        --prefix="$INSTALL_DIR" \
        --without-headers \
        --with-newlib \
        --with-cpu=m2 \
        --with-multilib-list=m2 \
        --with-system-zlib \
        --enable-languages=c \
        --disable-nls \
        --disable-werror \
        --disable-shared \
        --disable-threads \
        --disable-libssp \
        --disable-libgomp \
        --disable-libmudflap \
        --disable-libquadmath \
        --disable-libatomic \
        --disable-decimal-float \
        --disable-win32-registry

    echo "  building..."
    make -j"$NPROC" all-gcc all-target-libgcc

    echo "  installing..."
    make install-gcc install-target-libgcc

    # Create sh-elf-* symlinks so newlib's configure can find the tools
    # (newlib uses --target=sh-elf, but our tools are named sh2eb-elf-*)
    for tool in gcc g++ ar as ld nm objcopy objdump ranlib readelf strip; do
        if [ -f "$INSTALL_DIR/bin/${PROGRAM_PREFIX}${tool}" ] && [ ! -f "$INSTALL_DIR/bin/${TARGET}-${tool}" ]; then
            ln -sf "${PROGRAM_PREFIX}${tool}" "$INSTALL_DIR/bin/${TARGET}-${tool}"
        fi
    done

    echo "  GCC stage 1 done."
}

build_newlib() {
    echo "=== Building newlib $NEWLIB_VERSION ==="

    local archive="$DOWNLOAD_DIR/newlib-${NEWLIB_VERSION}.tar.gz"
    download "https://sourceware.org/pub/newlib/newlib-${NEWLIB_VERSION}.tar.gz" "$archive"

    echo "  extracting..."
    mkdir -p "$SOURCE_DIR"
    if [ ! -d "$SOURCE_DIR/newlib-${NEWLIB_VERSION}" ]; then
        tar xf "$archive" -C "$SOURCE_DIR"
    fi

    echo "  configuring..."
    local builddir="$BUILD_DIR/newlib"
    rm -rf "$builddir"
    mkdir -p "$builddir"
    cd "$builddir"

    # newlib needs the stage 1 compiler on PATH
    export PATH="$INSTALL_DIR/bin:$PATH"

    "$SOURCE_DIR/newlib-${NEWLIB_VERSION}/configure" \
        --target="$TARGET" \
        --prefix="$INSTALL_DIR" \
        --disable-nls \
        --disable-werror \
        --disable-shared \
        --disable-newlib-supplied-syscalls

    echo "  building..."
    make -j"$NPROC"

    echo "  installing..."
    make install

    echo "  newlib done."
}

build_gcc_stage2() {
    echo "=== Building GCC $GCC_VERSION (stage 2 — final with C++) ==="

    local builddir="$BUILD_DIR/gcc-stage2"
    rm -rf "$builddir"
    mkdir -p "$builddir"
    cd "$builddir"

    export PATH="$INSTALL_DIR/bin:$PATH"

    "$SOURCE_DIR/gcc-${GCC_VERSION}/configure" \
        --build="$HOST_TRIPLET" \
        --host="$HOST_TRIPLET" \
        --target="$TARGET" \
        --program-prefix="$PROGRAM_PREFIX" \
        --prefix="$INSTALL_DIR" \
        --with-newlib \
        --with-cpu=m2 \
        --with-multilib-list=m2 \
        --with-system-zlib \
        --enable-languages=c,c++ \
        --enable-lto \
        --disable-nls \
        --disable-werror \
        --disable-shared \
        --disable-threads \
        --disable-libssp \
        --disable-libgomp \
        --disable-libmudflap \
        --disable-libquadmath \
        --disable-libatomic \
        --disable-decimal-float \
        --disable-win32-registry \
        --disable-libstdcxx-pch \
        --disable-libstdcxx-threads \
        --disable-libstdcxx-time \
        --disable-rpath \
        --disable-dlopen \
        --enable-cxx-flags="-fno-exceptions -fno-rtti"

    echo "  building..."
    make -j"$NPROC"

    echo "  installing..."
    make install

    echo "  GCC stage 2 done."
}

# ── Main ──────────────────────────────────────────────────────────────────────

detect_platform

export PATH="$INSTALL_DIR/bin:$PATH"

case "${1:-all}" in
    binutils)
        build_binutils
        ;;
    gcc1)
        build_gcc_stage1
        ;;
    newlib)
        build_newlib
        ;;
    gcc2)
        build_gcc_stage2
        ;;
    all)
        build_binutils
        build_gcc_stage1
        build_newlib
        build_gcc_stage2
        echo ""
        echo "=== Toolchain built successfully ==="
        echo "Installed to: $INSTALL_DIR"
        echo "Add to PATH:  export PATH=\"$INSTALL_DIR/bin:\$PATH\""
        echo ""
        echo "Test:"
        echo "  ${PROGRAM_PREFIX}gcc --version"
        echo "  ${PROGRAM_PREFIX}g++ --version"
        ;;
    clean)
        echo "Cleaning build artifacts..."
        rm -rf "$BUILD_DIR" "$SOURCE_DIR"
        echo "Done. (Downloads preserved in $DOWNLOAD_DIR)"
        ;;
    distclean)
        echo "Cleaning everything..."
        rm -rf "$BUILD_DIR" "$SOURCE_DIR" "$DOWNLOAD_DIR" "$INSTALL_DIR"
        echo "Done."
        ;;
    *)
        echo "Usage: $0 [all|binutils|gcc1|newlib|gcc2|clean|distclean]"
        exit 1
        ;;
esac
