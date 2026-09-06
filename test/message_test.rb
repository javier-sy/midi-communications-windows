require_relative 'helper'

# These tests deliberately load one file rather than the gem. Message is the
# only part of the library with logic in it, and keeping it free of any binding
# to winmm.dll means its behaviour can be checked on any machine — including
# the one where this gem is written, which is not a Windows machine.
require 'midi-communications-windows/message'

class MessageTest < Minitest::Test
  Message = MIDICommunicationsWindows::Message

  context 'Message.length_of' do
    should 'give three bytes to the channel messages that carry two data bytes' do
      assert_equal 3, Message.length_of(0x80) # Note Off
      assert_equal 3, Message.length_of(0x90) # Note On
      assert_equal 3, Message.length_of(0xA0) # Polyphonic Key Pressure
      assert_equal 3, Message.length_of(0xB0) # Control Change
      assert_equal 3, Message.length_of(0xE0) # Pitch Bend
    end

    should 'give two bytes to the channel messages that carry one' do
      assert_equal 2, Message.length_of(0xC0) # Program Change
      assert_equal 2, Message.length_of(0xD0) # Channel Pressure
    end

    should 'read the channel out of the low nibble and ignore it' do
      assert_equal 3, Message.length_of(0x9F)
      assert_equal 2, Message.length_of(0xCF)
    end

    should 'give one byte to every System Real Time message' do
      (0xF8..0xFF).each { |status| assert_equal 1, Message.length_of(status) }
    end

    should 'know the lengths of the System Common messages' do
      assert_equal 2, Message.length_of(0xF1) # MIDI Time Code Quarter Frame
      assert_equal 3, Message.length_of(0xF2) # Song Position Pointer
      assert_equal 2, Message.length_of(0xF3) # Song Select
      assert_equal 1, Message.length_of(0xF6) # Tune Request
    end

    should 'refuse a data byte' do
      assert_raises(ArgumentError) { Message.length_of(0x3C) }
    end

    should 'refuse System Exclusive, which never arrives as a short message' do
      assert_raises(ArgumentError) { Message.length_of(0xF0) }
    end
  end

  context 'Message.unpack' do
    should 'read a Note On out of the word' do
      assert_equal [0x90, 0x3C, 0x64], Message.unpack(0x0064_3C90)
    end

    should 'read a Program Change without inventing a third byte' do
      assert_equal [0xC0, 0x05], Message.unpack(0x0000_05C0)
    end

    # The defect this whole module exists to prevent: a Clock is one byte, and
    # the two zeroes above it in the word are padding, not data. Returned as
    # [0xF8, 0, 0] it is not a Clock any more, and MusaDSL's InputMidiClock
    # stops following the DAW.
    should 'read a Clock as one byte, not as three' do
      assert_equal [0xF8], Message.unpack(0x0000_00F8)
    end

    should 'ignore whatever the driver leaves in the unused high byte' do
      assert_equal [0x90, 0x3C, 0x64], Message.unpack(0xFF64_3C90)
    end

    should 'not confuse a Note On whose data bytes are zero with a Clock' do
      assert_equal [0x90, 0x00, 0x00], Message.unpack(0x0000_0090)
    end
  end

  context 'Message.pack' do
    should 'pack a Note On' do
      assert_equal 0x0064_3C90, Message.pack([0x90, 0x3C, 0x64])
    end

    should 'pack a Clock into the low byte alone' do
      assert_equal 0x0000_00F8, Message.pack([0xF8])
    end

    should 'refuse a message with fewer bytes than its status byte needs' do
      assert_raises(ArgumentError) { Message.pack([0x90, 0x3C]) }
    end

    # Dropping the surplus quietly would send a message the caller did not
    # write, and say nothing about it.
    should 'refuse a message with more bytes than its status byte allows' do
      assert_raises(ArgumentError) { Message.pack([0xC0, 0x05, 0x7F]) }
    end
  end

  context 'packing and unpacking' do
    should 'be inverses for every length of message' do
      [[0x90, 0x3C, 0x64], [0xC0, 0x05], [0xF8], [0xF2, 0x00, 0x40]].each do |bytes|
        assert_equal bytes, Message.unpack(Message.pack(bytes))
      end
    end
  end

  context 'Message.sysex?' do
    should 'recognise a System Exclusive message by its status byte' do
      assert Message.sysex?([0xF0, 0x7E, 0x7F, 0xF7])
      refute Message.sysex?([0x90, 0x3C, 0x64])
    end
  end
end
