module MIDICommunicationsWindows
  # Utility methods for converting between MIDI data formats.
  #
  # @api public
  module TypeConversion
    extend self

    # Converts an array of numeric bytes to a hex string.
    #
    # @param bytes [Array<Integer>] numeric bytes, e.g. `[0x90, 0x40, 0x40]`
    # @return [String] uppercase hex, two characters per byte, e.g. `'904040'`
    #
    # @example
    #   TypeConversion.numeric_bytes_to_hex_string([0x90, 0x40, 0x40])
    #   # => "904040"
    def numeric_bytes_to_hex_string(bytes)
      bytes.map { |byte| format('%02X', byte) }.join
    end
  end
end
