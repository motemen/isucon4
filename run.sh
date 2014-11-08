#!/bin/sh

export TMPDIR=/dev/shm
export NYTPROF=sigexit=int:savesrc=0:start=no
exec carton exec perl -d:NYTProf local/bin/plackup -s Starlet \
    --max-reqs-per-child=50000 --min-reqs-per-child=50000 \
    --max-workers=5 \
    --host localhost:8080 -E prod app.psgi
