#!/usr/bin/env ruby

require 'yaml'
require 'bundler/cli'

ALL_TASKS = Bundler::CLI.printable_tasks[1..-1].map { |l| l.first.gsub($0, '').strip }
HOME = Dir.home
FOLDER = File.expand_path('.')

def get_bundle_config(current=FOLDER)
    return nil if current.size < HOME.size

    if File.exist? "#{current}/.bundle/config"
        return [YAML.load_file("#{current}/.bundle/config"), current]
    else
        get_bundle_config(File.expand_path "#{current}/..")
    end
end

def get_bins(config, root)
    Dir["#{root}/#{config['BUNDLE_PATH']}/**/bin/*"]
end

cfg, bc = get_bundle_config
gb = get_bins(cfg, bc)
p [cfg, bc, gb]
