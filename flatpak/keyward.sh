#!/bin/sh
# raco distribute keeps its relative bin/ + lib/ layout; the glaze carrier
# assembles its page tree at runtime from define-runtime-path inside lib/.
exec /app/keyward/bin/keyward "$@"
