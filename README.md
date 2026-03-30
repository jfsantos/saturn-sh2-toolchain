# saturn-sh2-toolchain

Native ARM64 macOS (and Linux) build of the SH2 cross-compiler for Sega Saturn development.

Builds `sh2eb-elf-gcc` 14.2.0 with C++23 support, compatible with [SaturnRingLib](https://github.com/ReyeMe/SaturnRingLib).

## Prerequisites

### macOS (Apple Silicon)

```bash
brew install gmp mpfr libmpc isl texinfo wget
```

### Linux (Debian/Ubuntu)

```bash
sudo apt install build-essential texinfo wget libgmp-dev libmpfr-dev libmpc-dev libisl-dev
```

## Build

```bash
./build-toolchain.sh
```

This builds binutils, GCC (two-stage bootstrap with newlib), and installs to `./toolchain/`.

Takes ~20-30 minutes on Apple Silicon.

### Individual steps

```bash
./build-toolchain.sh binutils    # GNU binutils 2.43
./build-toolchain.sh gcc1        # GCC stage 1 (C only, no libc)
./build-toolchain.sh newlib      # newlib C library
./build-toolchain.sh gcc2        # GCC stage 2 (C + C++ with libstdc++)
```

## Usage

```bash
export PATH="$(pwd)/toolchain/bin:$PATH"
sh2eb-elf-gcc --version
sh2eb-elf-g++ -std=c++23 -m2 -c myfile.cxx
```

## Cleaning

```bash
./build-toolchain.sh clean       # Remove build/source dirs (keep downloads)
./build-toolchain.sh distclean   # Remove everything including toolchain
```

## What it builds

| Component | Version | Purpose |
|-----------|---------|---------|
| binutils  | 2.43    | Assembler, linker, objcopy |
| GCC       | 14.2.0  | C/C++ compiler with C++23 support |
| newlib    | 4.4.0   | Bare-metal C library |

Target: `sh-elf` with `--program-prefix=sh2eb-elf-` and `--with-cpu=m2`
