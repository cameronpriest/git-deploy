#!/bin/sh
read stdin
declare -x rvm_path="/usr/local/rvm"
if [[ -s /usr/local/rvm/scripts/rvm ]] ; then source /usr/local/rvm/scripts/rvm ; fi
rvm ree@base

echo -e $stdin | git-deploy deploy:hook