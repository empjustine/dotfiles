#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-

repositories_root = "#{ENV['HOME']}/repositories"
source_root = "#{repositories_root}/self/dotfiles/home"
source_glob = Dir["#{source_root}/**/*"]

source_directories = source_glob.select { |f| File.directory?(f) && !File.symlink?(f) }.map { |f| f.gsub("#{source_root}/", '') }
source_files = source_glob.select { |f| !File.directory?(f) || File.symlink?(f) }.map { |f| f.gsub("#{source_root}/", '') }

puts "cd"
source_directories.each { |d| puts "mkdir \"#{d.gsub(/「dot」/, '.')}\""}
source_files.each { |f| puts "ln -s \"#{source_root}/#{f}\" \"#{f.gsub(/「symlink」/, '').gsub(/「dot」/, '.')}\"" }

puts "mkdir \".vim\""
puts "mkdir \".vim/bundle\""
vim_bundle_root = "#{repositories_root}/vim"
vim_glob = Dir["#{vim_bundle_root}/*"]

vim_directories = vim_glob.select { |f| File.directory?(f) && !File.symlink?(f) }.map { |f| f.gsub("#{vim_bundle_root}/", '') }
vim_directories.each { |d| puts "ln -s \"#{vim_bundle_root}/#{d}\" \".vim/bundle/#{d.gsub(/「symlink」/, '').gsub(/「dot」/, '.')}\"" }

puts "ln -s \"#{repositories_root}/solarized/solarized-xmonad/Solarized.hs\" \".xmonad/lib\""
