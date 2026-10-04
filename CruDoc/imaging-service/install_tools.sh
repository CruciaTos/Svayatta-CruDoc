#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends build-essential cmake git ca-certificates \
  python3-venv python3-dev
rm -rf /var/lib/apt/lists/*
work=$(mktemp -d)
git clone --depth 1 --branch 0.32.0 https://github.com/aous72/OpenJPH "$work/openjph"
cmake -S "$work/openjph" -B "$work/openjph/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$work/openjph/build" -j"$(nproc)"
cmake --install "$work/openjph/build"
git clone --depth 1 --branch v2.5.3 https://github.com/uclouvain/openjpeg "$work/openjpeg"
cmake -S "$work/openjpeg" -B "$work/openjpeg/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_CODEC=ON
cmake --build "$work/openjpeg/build" -j"$(nproc)"
cmake --install "$work/openjpeg/build"
ldconfig
rm -rf "$work"
ojph_compress --help > /dev/null 2>&1 || ojph_compress -h > /dev/null 2>&1 || true
command -v ojph_compress opj_compress opj_decompress