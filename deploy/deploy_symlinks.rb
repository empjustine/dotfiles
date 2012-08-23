#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-

#source_root = "#{ENV['DOTFILES_PATH']}/home"
source_root = "/home/empjustine/.dotfiles/home"

source_glob = Dir["#{source_root}/**/*"]

source_directories = source_glob.select { |f| File.directory?(f) && !File.symlink?(f) }.map { |f| f.gsub("#{source_root}/", '') }
source_files = source_glob.select { |f| !File.directory?(f) || File.symlink?(f) }.map { |f| f.gsub("#{source_root}/", '') }

source_directories.each { |d| puts "mkdir -p \"#{d.gsub(/「dot」/, '.')}\""}
source_files.each { |f| puts "ln -s \"#{source_root}/#{f}\" \"#{f.gsub(/「symlink」/, '').gsub(/「dot」/, '.')}\"" }
