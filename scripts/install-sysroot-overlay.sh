#!/usr/bin/env bash

set -euo pipefail

SYSROOT="${1:-/opt/toolchain/aarch64/modalix}"
LIBDIR="${SYSROOT}/usr/lib/aarch64-linux-gnu"

if [[ $# -lt 2 ]]; then
  echo "Usage: $(basename "$0") SYSROOT package[:arch] [package[:arch] ...]" >&2
  exit 1
fi

shift
PACKAGES=("$@")

export DEBIAN_FRONTEND=noninteractive

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "${workdir}"
}
trap cleanup EXIT

mkdir -p "${SYSROOT}" "${LIBDIR}" "${workdir}/archives"

echo "Downloading sysroot overlay packages into ${SYSROOT}"
printf '  %s\n' "${PACKAGES[@]}"

apt-get update --allow-releaseinfo-change
apt-get install -y --download-only --no-install-recommends \
  -o Dir::Cache::archives="${workdir}/archives" \
  "${PACKAGES[@]}"

find "${workdir}/archives" -maxdepth 1 -type f -name '*.deb' -print0 \
  | while IFS= read -r -d '' deb; do
      echo "Extracting $(basename "${deb}")"
      dpkg-deb -x "${deb}" "${SYSROOT}"
    done

# dpkg-deb -x does not run maintainer scripts or update-alternatives, so
# recreate the linker-facing BLAS/LAPACK/OpenBLAS links in the sysroot.
if [[ -f "${LIBDIR}/openblas-pthread/libblas.so.3" ]]; then
  ln -sfn openblas-pthread/libblas.so.3 "${LIBDIR}/libblas.so.3"
fi
if [[ -f "${LIBDIR}/openblas-pthread/liblapack.so.3" ]]; then
  ln -sfn openblas-pthread/liblapack.so.3 "${LIBDIR}/liblapack.so.3"
fi
if [[ -e "${LIBDIR}/libblas.so.3" ]]; then
  ln -sfn libblas.so.3 "${LIBDIR}/libblas.so"
fi
if [[ -e "${LIBDIR}/liblapack.so.3" ]]; then
  ln -sfn liblapack.so.3 "${LIBDIR}/liblapack.so"
fi

if [[ ! -e "${LIBDIR}/libopenblas.so.0" ]]; then
  candidate="$(find "${LIBDIR}" -maxdepth 2 -type f -name 'libopenblas*.so*' | sort | head -n1 || true)"
  if [[ -n "${candidate}" ]]; then
    rel_target="$(realpath --relative-to="${LIBDIR}" "${candidate}")"
    ln -sfn "${rel_target}" "${LIBDIR}/libopenblas.so.0"
  fi
fi
if [[ -e "${LIBDIR}/libopenblas.so.0" && ! -e "${LIBDIR}/libopenblas.so" ]]; then
  ln -sfn libopenblas.so.0 "${LIBDIR}/libopenblas.so"
fi

echo "Sysroot overlay complete"
