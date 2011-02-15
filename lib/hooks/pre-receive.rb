#!/bin/sh
if [[ -s /usr/local/rvm/scripts/rvm ]] ; then source /usr/local/rvm/scripts/rvm ; fi
rvm 1.8.7@base

git-deploy deploy:hook