#!/usr/bin/env ruby
$:.unshift(File.join('..', 'lib'))

require 'midi-communications-windows'

# This program selects the first midi input and sends an inspection of the first
# 10 messages it receives to standard out
#
# gets blocks until something arrives, so this loop needs no delay of its own

num_messages = 10

MIDICommunicationsWindows::Input.first.open do |input|
  puts "Using input: #{input.id}, #{input.name}"

  puts 'send some MIDI to your input now...'

  received = 0
  while received < num_messages
    input.gets.each do |message|
      puts message.inspect
      received += 1
    end
  end

  puts 'finished'
end
