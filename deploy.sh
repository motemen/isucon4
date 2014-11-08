#!/bin/sh

set -e

echo '---> isu31a'
ssh isucon@203.104.111.191 "cd ~/deploy && git pull && carton install --deployment && supervisorctl restart isucon_perl"

echo '---> isu31b'
ssh isucon@203.104.111.192 "cd ~/deploy && git pull && carton install --deployment && supervisorctl restart isucon_perl"

echo '---> isu31c'
ssh isucon@203.104.111.193 "cd ~/deploy && git pull && carton install --deployment && supervisorctl restart isucon_perl"
