#!/bin/bash

set -e

PROGDIR=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd )
PREFIX="${1:-/usr/local}"

requisite_paths=(
   bin
   lib/shql
   share/man
   share/shql
)

for f in "${requisite_paths[@]}" ; do
   install -d -m 755 "${PREFIX}/${f}"
done

install -m 755 "${PROGDIR}/bin/"*     "${PREFIX}/bin/"
install -m 755 "${PROGDIR}/lib/"*     "${PREFIX}/lib/shql/"
install -m 644 "${PROGDIR}/share/"*   "${PREFIX}/share/shql/"

echo "Installed 'shql' -> ${PREFIX}."
