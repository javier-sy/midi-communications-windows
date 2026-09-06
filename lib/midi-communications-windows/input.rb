module MIDICommunicationsWindows
  # A MIDI input port: somewhere messages arrive from.
  #
  # @example Read from the first input
  #   input = MIDICommunicationsWindows::Input.first
  #   input.open
  #   input.gets
  #   # => [{ data: [144, 60, 100], timestamp: 1789123456.789 }]
  #
  # ## `gets` blocks, and that is part of the contract
  #
  # {#gets} waits until at least one message has arrived and then returns
  # everything that accumulated. It does not return an empty array.
  #
  # This is not an incidental property. `Musa::Clock::InputMidiClock` reads its
  # MIDI Clock in a loop with no delay of its own, relying on `gets` to be where
  # the thread waits. An implementation that returned immediately would turn
  # that loop into a spin on a full core, and would do it silently — the notes
  # would still play.
  #
  # @see Output for sending
  #
  # @api public
  class Input
    extend Device::ClassMethods
    include Device::InstanceMethods

    # @return [Symbol] `:input`
    def self.direction
      :input
    end

    # @param id [Integer] the port's WinMM index among inputs
    # @param name [String] the port's name as reported by WinMM
    # @api private
    def initialize(id, name)
      super

      @queue = Queue.new
      @sysex = []
    end

    # Reads the messages that have arrived.
    #
    # Blocks until there is at least one. See the note on the class.
    #
    # @return [Array<Hash>] each with `:data`, an array of numeric bytes, and
    #   `:timestamp`, a Float of seconds
    #
    # @example
    #   input.gets
    #   # => [{ data: [248], timestamp: 1789123456.789 },
    #   #     { data: [144, 60, 100], timestamp: 1789123456.812 }]
    def gets
      # Queue#pop is where the thread waits, and it is the whole of the waiting
      # mechanism on purpose. The obvious alternative — test whether the queue
      # is empty, then sleep, and have the producer Thread#run the sleeper — has
      # a window between the test and the sleep in which a message can arrive
      # and its wake-up be delivered to a thread that is not sleeping yet. The
      # reader then sleeps forever, and the thread it happens on is the one
      # carrying the MIDI clock. Queue does the same job with no such window.
      messages = [@queue.pop]
      messages << @queue.pop until @queue.empty?

      messages
    end
    alias read gets

    # Reads the messages that have arrived, with their data as hex strings.
    #
    # @return [Array<Hash>] as {#gets}, but `:data` is a String
    #
    # @example
    #   input.gets_s
    #   # => [{ data: 'F8', timestamp: 1789123456.789 }]
    def gets_s
      gets.each do |message|
        message[:data] = TypeConversion.numeric_bytes_to_hex_string(message[:data])
      end
    end
    alias gets_bytestr gets_s

    private

    # Accepts one message from whichever mechanism is delivering them, waking
    # whatever thread is waiting in {#gets}.
    #
    # Both candidate delivery mechanisms end here, which is the point: they
    # differ only in how bytes reach this method.
    #
    # @param bytes [Array<Integer>] one complete message
    # @param timestamp [Float] seconds, as `Time.now.to_f`
    # @return [void]
    # @api private
    def enqueue(bytes, timestamp)
      @queue << { data: bytes, timestamp: timestamp }
    end

    # Accepts a fragment of System Exclusive, emitting the message once it ends.
    #
    # WinMM fills a buffer at a time, so a System Exclusive message longer than
    # the buffer arrives in pieces. They are collected until the 0xF7 that ends
    # the message, and only then handed on: a caller asking for messages should
    # get messages, not the arbitrary lengths a buffer size happened to impose.
    #
    # Measured: a 200-byte message through 128-byte buffers arrives as 128 then
    # 72, contiguous and exact. WinMM does not require a buffer large enough for
    # the whole message.
    #
    # Empty fragments must never reach here. Closing a port makes `midiInReset`
    # hand back every buffer that was queued and unused, each reported with
    # `dwBytesRecorded` of zero; passing those on would emit a stray empty
    # message, or worse, terminate a partial one.
    #
    # @param bytes [Array<Integer>] one buffer's worth
    # @param timestamp [Float] seconds
    # @return [void]
    # @api private
    def enqueue_sysex(bytes, timestamp)
      @sysex.concat(bytes)

      return unless @sysex.last == 0xF7

      enqueue(@sysex.dup, timestamp)
      @sysex.clear
    end

    # Opens the port and starts delivery.
    #
    # @return [void]
    # @raise [Error]
    # @api private
    def connect
      start_receiving
    end

    # Stops delivery and closes the port.
    #
    # @return [void]
    # @raise [Error]
    # @api private
    def disconnect
      stop_receiving

      # A System Exclusive message interrupted by the close is not going to be
      # completed by anything, and leaving its bytes in the buffer would prepend
      # them to the first message of the next session.
      @sysex.clear
    end

    # ------------------------------------------------------------------
    # Delivery: CALLBACK_THREAD
    # ------------------------------------------------------------------
    #
    # WinMM offers two ways to hand a client its input, and both were measured
    # working against a system loopback on Windows 11 25H2. This is the one that
    # was chosen, and why.
    #
    # Under `CALLBACK_FUNCTION` the driver calls an FFI function pointer from a
    # thread of its own. It is what RtMidi, PortMidi and midi-winmm all do. But
    # a callback arriving on a thread Ruby does not own runs on a thread FFI
    # supplies while the driver's thread waits inside the callback, and if
    # anything else in the process is holding the GVL inside a winmm call, the
    # two deadlock. What that produces is not an exception: it is duplicate
    # deliveries, a second or two late, with the send reporting an error. See
    # the note in {API} for the measurement and its controls. Declaring every
    # winmm call `blocking: true` avoids it — but that is a rule someone has to
    # keep obeying, and the failure it prevents is silent.
    #
    # Under `CALLBACK_THREAD` WinMM posts to the message queue of a thread this
    # library owns. The driver's thread never enters Ruby, so a Ruby callback
    # can never be waiting on a GVL that a sending thread holds: the failure
    # above stops being something to guard against and becomes something that
    # cannot happen. The reader thread owns the port and may call winmm freely,
    # which is what makes {#requeue} ordinary code rather than the thing
    # Microsoft's documentation prohibits inside `midiInProc`.
    #
    # The price is `dwParam2`, the driver's own millisecond count, which is not
    # delivered this way. Nothing consumes it: `InputMidiClock` reads only
    # `message[:data]`, `MIDIRecorder` stamps with the sequencer's position, and
    # the macOS layer already takes `Time.now.to_f` from inside its own callback
    # — arrival at Ruby, not a driver stamp. So the timestamp is taken here the
    # same way, and both platforms mean the same thing by it.

    # How many buffers to keep queued for System Exclusive, and how large.
    #
    # WinMM fills whatever it is given and splits a message across buffers, so
    # the size is not a limit on message length; it only decides how often the
    # reader is woken. Keeping several queued means the next fragment has
    # somewhere to go while this one is being copied out.
    BUFFER_COUNT = 4
    BUFFER_SIZE = 1024

    # How long to wait for `midiInReset` to hand the buffers back, in seconds.
    RESET_TIMEOUT = 1.0

    # Opens the port and starts delivering, from a thread of our own.
    #
    # The port is opened *inside* the reader thread because `midiInOpen` is
    # given that thread's id and posts to that thread's queue. The caller waits
    # here until the thread reports that it opened, so that a failure to open
    # reaches whoever called {#open} instead of disappearing into a thread.
    #
    # @return [void]
    # @raise [Error]
    # @api private
    def start_receiving
      @returned = Queue.new
      @started = Queue.new

      @reader = Thread.new { receive_loop }

      failure = @started.pop
      raise failure if failure
    end

    # Stops delivery and closes the port.
    #
    # The order matters, and one step is easy to leave out. `midiInReset` hands
    # every queued buffer back **as messages in the reader thread's queue**, so
    # the thread has to keep pumping until they arrive. Posting `WM_QUIT` first
    # loses them, and then `midiInUnprepareHeader` is called on buffers the
    # driver has not released.
    #
    # A thread blocked in a `blocking: true` call cannot be interrupted by
    # `Thread#raise`, so `WM_QUIT` is the only way to end the loop.
    #
    # @return [void]
    # @raise [Error]
    # @api private
    def stop_receiving
      API.check!(API.midiInStop(@handle), :midiInStop, :input)
      API.check!(API.midiInReset(@handle), :midiInReset, :input)

      await_returned_buffers

      API.PostThreadMessageW(@thread_id, API::WM_QUIT, 0, 0)
      @reader.join
      @reader = nil

      release_buffers

      API.check!(API.midiInClose(@handle), :midiInClose, :input)
      @handle = nil
    end

    # The reader thread: owns the port, and is the only thread that touches it
    # while it is open.
    #
    # @return [void]
    # @api private
    def receive_loop
      message = API::MSG.new

      # A thread has no message queue until it asks for one, and WinMM cannot
      # post to a queue that does not exist: without this, `midiInOpen` is given
      # a thread id that rejects messages and the first notifications are lost.
      API.PeekMessageW(message, nil, 0, 0, API::PM_NOREMOVE)

      begin
        open_port
        prepare_buffers
        API.check!(API.midiInStart(@handle), :midiInStart, :input)
      rescue StandardError => e
        # Whatever was opened before the failure has to be given back here:
        # nobody else can, because {#open} will not mark the port enabled and
        # so {#close} will never run.
        abandon_port
        @started << e
        return
      end

      @started << nil

      pump(message)
    end

    # Releases whatever an interrupted {#receive_loop} had managed to take.
    #
    # @return [void]
    # @api private
    def abandon_port
      return if @handle.nil?

      API.midiInReset(@handle)
      @buffers&.each { |buffer| API.midiInUnprepareHeader(@handle, buffer[:header], API::MIDIHdr.size) }
      API.midiInClose(@handle)

      @buffers = nil
      @handle = nil
    end

    # @return [void]
    # @raise [Error]
    # @api private
    def open_port
      @thread_id = API.GetCurrentThreadId

      handle_pointer = FFI::MemoryPointer.new(:uintptr_t)

      API.check!(API.midiInOpen(handle_pointer, @id, @thread_id, 0, API::CALLBACK_THREAD),
                 :midiInOpen, :input)

      @handle = handle_pointer.read(:uintptr_t)
    end

    # Hands WinMM the buffers it will fill with System Exclusive.
    #
    # Both the header and the memory it points at are kept, because letting
    # either be collected while the driver still holds a pointer to it is not a
    # Ruby error but a corrupted process.
    #
    # @return [void]
    # @raise [Error]
    # @api private
    def prepare_buffers
      @buffers = Array.new(BUFFER_COUNT) do
        memory = FFI::MemoryPointer.new(:uint8, BUFFER_SIZE)

        header = API::MIDIHdr.new
        header[:lpData] = memory
        header[:dwBufferLength] = BUFFER_SIZE

        API.check!(API.midiInPrepareHeader(@handle, header, API::MIDIHdr.size),
                   :midiInPrepareHeader, :input)
        API.check!(API.midiInAddBuffer(@handle, header, API::MIDIHdr.size),
                   :midiInAddBuffer, :input)

        { header: header, memory: memory }
      end
    end

    # Reads the thread's queue until `WM_QUIT`.
    #
    # `GetMessageW` returns above zero for a message, zero for `WM_QUIT` and -1
    # for an error, so the loop ends on anything that is not positive.
    #
    # Only the two MIDI notifications are acted on. The queue carries other
    # traffic — see {API::WM_USER} — and treating everything that arrives as
    # MIDI would read those as messages.
    #
    # @param message [API::MSG] reused for every read
    # @return [void]
    # @api private
    def pump(message)
      loop do
        break unless API.GetMessageW(message, nil, 0, 0).positive?

        begin
          case message[:message]
          when API::MM_MIM_DATA then deliver_short(message[:lParam])
          when API::MM_MIM_LONGDATA then deliver_long(message[:lParam])
          end
        rescue StandardError => e
          # One bad message must not end the loop. A reader thread that dies
          # here takes every later message with it, and leaves gets blocked
          # forever on a queue nothing will ever fill again -- which looks like
          # a hung program, not like an error.
          warn "[midi-communications-windows] #{@name}: #{e.class}: #{e.message}"
        end
      end
    end

    # A short message: `lParam` is the message itself, packed into a word.
    #
    # @param word [Integer]
    # @return [void]
    # @api private
    def deliver_short(word)
      enqueue(Message.unpack(word & 0xFFFF_FFFF), Time.now.to_f)
    rescue ArgumentError => e
      # WinMM should never deliver a word this cannot size. If it does, the
      # port keeps working: one message nobody can read is a smaller loss than
      # a reader thread that dies and takes every later message with it.
      warn "[midi-communications-windows] ignoring an unreadable message on #{@name}: #{e.message}"
    end

    # A System Exclusive fragment: `lParam` points at the buffer WinMM filled.
    #
    # @param header_pointer [Integer] address of a `MIDIHDR`
    # @return [void]
    # @api private
    def deliver_long(header_pointer)
      header = API::MIDIHdr.new(FFI::Pointer.new(header_pointer))
      recorded = header[:dwBytesRecorded]

      # An empty one is a buffer coming back from midiInReset, not a fragment.
      # The two are indistinguishable except by this field, and passing one on
      # would either emit a message of nothing or truncate a partial one.
      if recorded.zero?
        @returned << header_pointer
        return
      end

      enqueue_sysex(header[:lpData].read_array_of_uint8(recorded), Time.now.to_f)

      requeue(header)
    end

    # Gives a buffer back to WinMM so it can be filled again.
    #
    # This is the call that decided the delivery mechanism: it happens on the
    # reader thread, inside its own message loop, which is legal here and is
    # what Microsoft's documentation forbids inside `midiInProc`. The queue is
    # first in, first out, so a recycled buffer goes to the back and is used
    # again once the ones ahead of it have been.
    #
    # @param header [API::MIDIHdr]
    # @return [void]
    # @raise [Error]
    # @api private
    def requeue(header)
      header[:dwBytesRecorded] = 0
      header[:dwFlags] &= ~API::MHDR_DONE & 0xFFFF_FFFF

      API.check!(API.midiInAddBuffer(@handle, header, API::MIDIHdr.size), :midiInAddBuffer, :input)
    end

    # Waits for `midiInReset` to return the queued buffers.
    #
    # Bounded, because closing a port must end whether or not the driver plays
    # its part; a device that has been unplugged will not return anything.
    #
    # @return [void]
    # @api private
    def await_returned_buffers
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + RESET_TIMEOUT

      while @returned.size < @buffers.size &&
            Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        sleep 0.001
      end
    end

    # @return [void]
    # @api private
    def release_buffers
      @buffers.each do |buffer|
        API.midiInUnprepareHeader(@handle, buffer[:header], API::MIDIHdr.size)
      end

      @buffers = nil
    end
  end
end
