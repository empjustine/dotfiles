#!/usr/bin/env ruby
require "bundler/cli"

puts Bundler::CLI.tasks.map { |k, _| k }