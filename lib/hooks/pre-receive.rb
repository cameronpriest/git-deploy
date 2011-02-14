#!/usr/bin/env ruby
require 'rubygems'
require 'git_deploy'
require 'git_deploy/command'
GitDeploy::Command.run "deploy:receive", ""