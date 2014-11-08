#!/bin/sh

# export TMPDIR=/dev/shm
exec su -c "carton exec plackup \
    --port 80 \
    -s Starlet \
    --max-reqs-per-child=50000 --min-reqs-per-child=50000 \
    --max-workers=5 \
    -E prod app.psgi"
