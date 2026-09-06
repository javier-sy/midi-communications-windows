module MIDICommunicationsWindows
  # A MIDI output port: somewhere to send messages.
  #
  # @example Send a note through the first output
  #   output = MIDICommunicationsWindows::Output.first
  #   output.open
  #   output.puts(0x90, 60, 100)   # Note On, middle C
  #   sleep 0.5
  #   output.puts(0x80, 60, 0)     # Note Off
  #
  # @example Send the same thing as a hex string
  #   output.puts_s('903C64')
  #
  # @see Input for receiving
  #
  # @api public
  class Output
    extend Device::ClassMethods
    include Device::InstanceMethods

    # @return [Symbol] `:output`
    def self.direction
      :output
    end

    # Sends a MIDI message, in whichever form it is given.
    #
    # @param args [Array<Integer>, Array<String>, Integer, String] one message,
    #   as loose bytes, an array of bytes, or a hex string
    # @return [Boolean] true
    # @raise [Error] if WinMM refuses the message
    #
    # @example Every one of these sends the same Note On
    #   output.puts(0x90, 60, 100)
    #   output.puts([0x90, 60, 100])
    #   output.puts('903C64')
    def puts(*args)
      case args.first
      when Array then args.each { |argument| puts(*argument) }
      when Integer then puts_bytes(*args)
      when String then puts_s(*args)
      end

      true
    end
    alias write puts

    # Sends a MIDI message given as a hex string.
    #
    # @param data [String] hex, two characters per byte, e.g. `'903C64'`
    # @return [Boolean] true
    # @raise [Error] if WinMM refuses the message
    def puts_s(data)
      puts_bytes(*data.scan(/../).map(&:hex))
    end
    alias puts_bytestr puts_s
    alias puts_hex puts_s

    # Sends a MIDI message given as numeric bytes.
    #
    # System Exclusive takes a different route through WinMM than everything
    # else, and this is where the two part company.
    #
    # @param data [Array<Integer>] the message, status byte first
    # @return [Boolean] true
    # @raise [Error] if WinMM refuses the message
    def puts_bytes(*data)
      Message.sysex?(data) ? send_sysex(data) : send_short(data)

      true
    end

    private

    # Opens the port.
    #
    # `CALLBACK_NULL` asks WinMM for no notifications at all. The only event an
    # output can raise is `MM_MOM_DONE`, saying a System Exclusive buffer has
    # finished, and {#send_sysex} learns that from the buffer's own flags
    # instead. Asking for no callback keeps the driver from ever calling into
    # Ruby, which is one whole class of threading problem that then cannot
    # occur on the sending side.
    #
    # @return [void]
    # @raise [Error]
    # @api private
    def connect
      handle_pointer = FFI::MemoryPointer.new(:uintptr_t)

      API.check!(API.midiOutOpen(handle_pointer, @id, 0, 0, API::CALLBACK_NULL),
                 :midiOutOpen, :output)

      @handle = handle_pointer.read(:uintptr_t)
    end

    # Closes the port.
    #
    # `midiOutReset` first, and not only for tidiness: it turns off every note
    # the port has left sounding and releases any buffer still queued. Closing
    # without it can leave a synthesiser holding notes with nothing left to
    # send it a Note Off.
    #
    # @return [void]
    # @raise [Error]
    # @api private
    def disconnect
      API.check!(API.midiOutReset(@handle), :midiOutReset, :output)
      API.check!(API.midiOutClose(@handle), :midiOutClose, :output)

      @handle = nil
    end

    # Sends a message of three bytes or fewer.
    #
    # @param data [Array<Integer>]
    # @return [void]
    # @raise [Error]
    # @api private
    def send_short(data)
      API.check!(API.midiOutShortMsg(@handle, Message.pack(data)), :midiOutShortMsg, :output)
    end

    # Sends a System Exclusive message.
    #
    # WinMM wants such a message in a buffer it has been told about, and the
    # sequence is fixed: prepare the header, send it, wait for the driver to
    # finish with it, then unprepare. Unpreparing early fails with
    # `MIDIERR_STILLPLAYING`, and freeing the buffer early is worse than that.
    #
    # The wait is a real one. MIDI runs at 31250 baud, so a byte takes about
    # 320 microseconds and a 200-byte dump takes something like 64 milliseconds
    # during which this method does not return. That is a property of the wire,
    # not of this implementation, but a caller sending System Exclusive from a
    # sequencer thread should know it is there.
    #
    # @param data [Array<Integer>] the whole message, 0xF0 through 0xF7
    # @return [void]
    # @raise [Error]
    # @api private
    def send_sysex(data)
      buffer = FFI::MemoryPointer.new(:uint8, data.size)
      buffer.write_array_of_uint8(data)

      header = API::MIDIHdr.new
      header[:lpData] = buffer
      header[:dwBufferLength] = data.size
      header[:dwBytesRecorded] = data.size

      API.check!(API.midiOutPrepareHeader(@handle, header, API::MIDIHdr.size),
                 :midiOutPrepareHeader, :output)

      begin
        API.check!(API.midiOutLongMsg(@handle, header, API::MIDIHdr.size), :midiOutLongMsg, :output)
        wait_until_sent(header)
      rescue Error
        # The driver still owns the buffer. Unpreparing it now would fail with
        # MIDIERR_STILLPLAYING and the memory would be freed underneath a device
        # that is still reading it; midiOutReset takes it back first.
        API.midiOutReset(@handle)
        raise
      ensure
        API.midiOutUnprepareHeader(@handle, header, API::MIDIHdr.size)
      end
    end

    # Blocks until the driver marks the buffer done, or gives up.
    #
    # There is no blocking WinMM call to wait on, so this polls the flag the
    # driver sets. The interval is short enough not to add meaningfully to a
    # transfer measured in tens of milliseconds, and long enough not to spin.
    #
    # The wait is bounded because the flag is set by a device that can go away:
    # unplug an interface in the middle of a dump and it is never set at all.
    # Without a limit this would spin for the life of the process, on whichever
    # thread happened to be sending — in MusaDSL, the sequencer's.
    #
    # @param header [API::MIDIHdr]
    # @return [void]
    # @raise [Error] if the device has not finished within {SYSEX_TIMEOUT}
    # @api private
    def wait_until_sent(header)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + SYSEX_TIMEOUT

      until (header[:dwFlags] & API::MHDR_DONE) != 0
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          raise Error.new(:midiOutLongMsg, nil,
                          "the device did not finish sending a #{header[:dwBufferLength]}-byte " \
                          "System Exclusive message within #{SYSEX_TIMEOUT} s")
        end

        sleep SYSEX_POLL_INTERVAL
      end
    end

    # How often to look at a System Exclusive buffer's done flag, in seconds.
    SYSEX_POLL_INTERVAL = 0.001

    # How long to wait for a System Exclusive message to go out, in seconds.
    # MIDI runs at 31250 baud, so this is room for roughly 3 kB — far more than
    # any message, and short enough that a vanished device is noticed.
    SYSEX_TIMEOUT = 1.0
  end
end
