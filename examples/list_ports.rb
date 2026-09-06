#!/usr/bin/env ruby
$:.unshift(File.join('..', 'lib'))

require 'midi-communications-windows'

# This lists every MIDI port WinMM offers, in both directions.
#
# The ids are indexes within a direction, so input 0 and output 0 are different
# ports. Names come back truncated to 31 characters, which is all WinMM stores.

%i[input output].each do |direction|
  puts "#{direction}s:"

  MIDICommunicationsWindows::Device.all_by_type[direction].each do |port|
    puts "  #{port.id}: #{port.name}"
  end
end
