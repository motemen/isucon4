#!/bin/sh

# export TMPDIR=/dev/shm
exec carton exec plackup -s Starlet \
    --max-reqs-per-child=50000 --min-reqs-per-child=50000 \
    --max-workers=5 \
    --host localhost:8080 -E prod app.psgi
