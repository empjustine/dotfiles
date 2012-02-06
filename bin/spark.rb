#!/usr/bin/env ruby
# -*- encoding : utf-8 -*-

SPARK_GLYPHS = [' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█', ]

def sparkline(list)
  amplitude = (list.max - list.min)
  eighth = amplitude / (SPARK_GLYPHS.size - 1)
  list.map do |value|
    index = (value - list.min) / eighth
    SPARK_GLYPHS[index]
  end
end

if __FILE__ == $0
  list = ARGV.map { |arg| arg.to_f }
  print sparkline(list).join('')
end
