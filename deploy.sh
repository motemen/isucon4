#!/bin/sh

set -e

deploy="cd ~/deploy && git pull && carton install && supervisorctl restart isucon_perl"

echo '---> isu31a'
ssh isucon@203.104.111.191 "$deploy"

echo '---> isu31b'
ssh isucon@203.104.111.192 "$deploy"

echo '---> isu31c'
ssh isucon@203.104.111.193 "$deploy"
