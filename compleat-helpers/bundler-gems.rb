#!/usr/bin/env ruby
require 'bundler'

puts Bundler.load.specs.map { |gem| gem.name }