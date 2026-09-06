module MIDICommunicationsWindows
  # Conversion between MIDI bytes and the packed 32-bit word WinMM uses for
  # short messages.
  #
  # WinMM does not pass short messages as byte strings. It packs them into a
  # `DWORD`: the status byte in the low-order byte, the first data byte next,
  # the second data byte after that, and the high-order byte unused. The same
  # packing is used in both directions — as `dwMsg` for `midiOutShortMsg`, and
  # as `dwParam1` in the notification a client receives for input.
  #
  # ## Why the length matters
  #
  # A packed word carries no length. Nothing distinguishes a Clock, which is one
  # byte, from a Note On whose two data bytes happen to be zero: both arrive as
  # a word whose upper three bytes are zero. The length has to be derived from
  # the status byte, and getting it wrong is not a cosmetic problem — a Clock
  # delivered as `[0xF8, 0, 0]` is not a MIDI Clock message, and a parser
  # reading it will either reject it or invent two events that were never sent.
  # In MusaDSL that is the difference between a piece that follows the DAW's
  # tempo and one that does not start at all.
  #
  # ## Why this file has no FFI in it
  #
  # This is the only part of the gem with logic rather than plumbing, and it is
  # also the part most likely to be wrong. Keeping it free of any binding to
  # `winmm.dll` means it can be tested on any machine, by anyone, without
  # Windows and without a MIDI port — which is what lets `test/message_test.rb`
  # run anywhere.
  #
  # @api public
  module Message
    # Number of bytes in a channel message, indexed by the status byte's high
    # nibble. Program Change and Channel Pressure carry one data byte; every
    # other channel message carries two.
    CHANNEL_MESSAGE_LENGTHS = {
      0x8 => 3, # Note Off
      0x9 => 3, # Note On
      0xA => 3, # Polyphonic Key Pressure
      0xB => 3, # Control Change
      0xC => 2, # Program Change
      0xD => 2, # Channel Pressure
      0xE => 3  # Pitch Bend Change
    }.freeze

    # Number of bytes in a System Common message, indexed by status byte.
    # Everything from 0xF8 up is System Real Time and is always one byte, so it
    # is not listed here.
    SYSTEM_COMMON_MESSAGE_LENGTHS = {
      0xF1 => 2, # MIDI Time Code Quarter Frame
      0xF2 => 3, # Song Position Pointer
      0xF3 => 2, # Song Select
      0xF6 => 1  # Tune Request
    }.freeze

    module_function

    # How many bytes the message with this status byte occupies.
    #
    # @param status [Integer] a MIDI status byte, 0x80..0xFF
    # @return [Integer] 1, 2 or 3
    # @raise [ArgumentError] if the byte is not a status byte, or begins a
    #   System Exclusive message, which is never delivered as a short message
    #
    # @example
    #   Message.length_of(0x90)  # => 3   Note On
    #   Message.length_of(0xC0)  # => 2   Program Change
    #   Message.length_of(0xF8)  # => 1   Clock
    def length_of(status)
      raise ArgumentError, "not a status byte: #{format('0x%02X', status)}" if status < 0x80 || status > 0xFF

      # System Exclusive does not travel as a short message: WinMM delivers it
      # through a buffer instead, so a caller who reaches here with 0xF0 has
      # confused the two paths.
      raise ArgumentError, 'System Exclusive is not a short message' if status == 0xF0

      return 1 if status >= 0xF8
      return SYSTEM_COMMON_MESSAGE_LENGTHS.fetch(status, 1) if status >= 0xF0

      CHANNEL_MESSAGE_LENGTHS.fetch(status >> 4)
    end

    # Unpacks the word WinMM delivers for an incoming short message.
    #
    # @param word [Integer] the `dwParam1` of an `MM_MIM_DATA` notification
    # @return [Array<Integer>] the message's bytes, of the length its status
    #   byte calls for
    #
    # @example A Clock arrives as a word whose upper bytes are zero
    #   Message.unpack(0x0000_00F8)  # => [0xF8]
    #
    # @example A Note On carries all three
    #   Message.unpack(0x0064_3C90)  # => [0x90, 0x3C, 0x64]
    def unpack(word)
      bytes = [word & 0xFF, (word >> 8) & 0xFF, (word >> 16) & 0xFF]

      bytes.first(length_of(bytes.first))
    end

    # Packs a short message into the word `midiOutShortMsg` expects.
    #
    # The length must be exactly what the status byte calls for. Too few bytes
    # is plainly a mistake; too many is either a mistake or an attempt at
    # running status, which WinMM does not accept on output. Quietly dropping
    # the surplus would send something the caller did not ask for and give no
    # sign of it.
    #
    # @param bytes [Array<Integer>] the message, status byte first
    # @return [Integer] the packed word
    # @raise [ArgumentError] if the message is not the length its status byte
    #   calls for
    #
    # @example
    #   Message.pack([0x90, 0x3C, 0x64])  # => 0x00643C90
    def pack(bytes)
      length = length_of(bytes.first)

      unless bytes.size == length
        raise ArgumentError,
              "#{format('0x%02X', bytes.first)} is a #{length}-byte message, got #{bytes.size} bytes"
      end

      bytes[0] | ((bytes[1] || 0) << 8) | ((bytes[2] || 0) << 16)
    end

    # Is this the start of a System Exclusive message?
    #
    # @param bytes [Array<Integer>] a message, status byte first
    # @return [Boolean]
    def sysex?(bytes)
      bytes.first == 0xF0
    end
  end
end
