#!/bin/sh

# export TMPDIR=/dev/shm
exec carton exec plackup \
    --port 8080
    -s Starlet \
    --max-reqs-per-child=50000 --min-reqs-per-child=50000 \
    --max-workers=5 \
    -E prod app.psgi
