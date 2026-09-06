#!/usr/bin/env ruby
$:.unshift(File.join('..', 'lib'))

require 'midi-communications-windows'

# This example outputs a raw sysex message to the first output port
# there will not be any output to the console
#
# The call does not return until the device reports the message sent, which at
# MIDI's 31250 baud takes about 320 microseconds per byte

output = MIDICommunicationsWindows::Output.first
sysex_msg = [0xF0, 0x41, 0x10, 0x42, 0x12, 0x40, 0x00, 0x7F, 0x00, 0x41, 0xF7]

output.open { |port| port.puts(sysex_msg) }
