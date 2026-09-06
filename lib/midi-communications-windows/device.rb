module MIDICommunicationsWindows
  # Enumeration of the MIDI ports WinMM offers, and the attributes every port
  # has whichever direction it runs in.
  #
  # ## What a port's identity is here, and what it is not
  #
  # WinMM identifies a port by its **index within its direction**: the same
  # integer is passed to `midiInGetDevCapsW` and to `midiInOpen`, and there is
  # nothing else to identify a port by. So the index is the identity, and
  # {InstanceMethods#id} is that index, unmodified.
  #
  # This differs from Core MIDI, where endpoints are numbered from a single
  # counter shared by sources and destinations, and an input and an output
  # therefore never share an id. Here they do: input 0 and output 0 are both
  # valid and unrelated. Nothing in `midi-communications` compares an id across
  # directions — `Input.all` and `Output.all` each search their own list — and
  # shifting the output indices to imitate Core MIDI would replace the real
  # identity with an invented one.
  #
  # ## A port's name does not identify it
  #
  # WinMM stores 31 characters of a name and silently drops the rest, so two
  # ports whose names differ only past that point arrive with the same name.
  # Measured: two loopback endpoints created as "Reloj Bitwig ñ prueba de
  # longitud" and "Reloj Bitwig ñ prueba de longitud DOS" come back through
  # `midiInGetDevCapsW` identical in every field — same name, same `wMid`, same
  # `wPid`, same `vDriverVersion`, same `wTechnology`. Nothing in the structure
  # tells them apart. Only the index does.
  #
  # This is not a contrived case: two ports of one interface whose long names
  # differ at the end collapse the same way. Windows does have a stable unique
  # identifier for each endpoint — the device interface id, which the newer APIs
  # expose — but `midiInGetDevCapsW` does not carry it, so it is not reachable
  # from here.
  #
  # A consumer matching ports by name should know it may be matching the wrong
  # one.
  #
  # ## Manufacturer and model are nil, deliberately
  #
  # WinMM reports `wMid` and `wPid`: numeric codes from the MMSYSTEM
  # manufacturer registry, which stopped being maintained in the 1990s.
  # Measured across every port on a Windows 11 machine — a software synth and
  # two loopback endpoints — `wMid` was 1, Microsoft, every time. `wPid` was no
  # better: 25 for every input and 26 for every output, the same for two
  # different devices, so it names a generic class and a direction rather than a
  # model. Turning those into text would label every controller on the machine
  # as made by Microsoft — a fact about the code table, presented as a fact
  # about the hardware.
  #
  # So both are nil. A caller filtering by manufacturer finds nothing and can
  # see that it found nothing, which is the truthful outcome; a caller offered
  # an empty string or an invented name would match, or not match, for reasons
  # that are not real.
  #
  # @api public
  module Device
    # Methods on {Input} and {Output} themselves.
    #
    # @api public
    module ClassMethods
      # Every port of this direction.
      #
      # WinMM is asked afresh on every call, so a port that appeared or went
      # away since the last one is reflected. A port that is still there comes
      # back as the same object as before; see {Device.enumerate}.
      #
      # @return [Array<Input>, Array<Output>]
      def all
        Device.all_by_type[direction]
      end

      # The first port of this direction, or nil if there are none.
      # @return [Input, Output, nil]
      def first
        all.first
      end

      # The last port of this direction, or nil if there are none.
      # @return [Input, Output, nil]
      def last
        all.last
      end
    end

    # Methods on an individual port.
    #
    # @api public
    module InstanceMethods
      # @!attribute [r] id
      #   @return [Integer] the port's WinMM index **within its direction**;
      #     see the note on identity in {Device}
      # @!attribute [r] name
      #   @return [String] the port's name, as WinMM reports it, truncated to
      #     31 characters. **Not unique**: see the note on names in {Device}.
      # @!attribute [r] enabled
      #   @return [Boolean] whether the port is currently open
      attr_reader :id, :name, :enabled

      # @!method enabled?
      #   @return [Boolean] alias for {#enabled}
      alias enabled? enabled

      # @param id [Integer] the port's WinMM index within its direction
      # @param name [String] the port's name as reported by WinMM
      # @api private
      def initialize(id, name)
        @id = id
        @name = name
        @enabled = false
      end

      # The port's direction.
      #
      # @return [Symbol] `:input` or `:output`
      def type
        self.class.direction
      end

      # Who made the device.
      #
      # Always nil on Windows. See the note in {Device} for why this is not
      # derived from `wMid`.
      #
      # @return [nil]
      def manufacturer
        nil
      end

      # The device model.
      #
      # Always nil on Windows, for the same reason as {#manufacturer}.
      #
      # @return [nil]
      def model
        nil
      end

      # The name to show a person choosing a port.
      #
      # This is the port name unchanged. On macOS the display name is built as
      # "manufacturer model (name)", which here would render as a name wrapped
      # in the punctuation of two absent fields.
      #
      # @return [String]
      def display_name
        @name
      end

      # Opens the port.
      #
      # Opening twice is not an error and does nothing the second time, which
      # is what `midi-communications` relies on when it opens a port a caller
      # may already hold.
      #
      # @yield [self] if a block is given, the port is closed when it returns
      # @return [self]
      # @raise [Error] if WinMM refuses to open the port
      def open
        unless @enabled
          connect
          @enabled = true
        end

        if block_given?
          begin
            yield self
          ensure
            close
          end
        end

        self
      end
      alias enable open
      alias start open

      # Closes the port.
      #
      # @return [Boolean] true if it was open, false if it already was not
      def close
        return false unless @enabled

        disconnect
        @enabled = false

        true
      end

      # @return [String]
      def to_s
        "#{self.class.name.split('::').last} #{@id}: #{@name}"
      end
    end

    # Wrappers already handed out, so that a port that is still there is still
    # the same object. See {Device.enumerate}.
    @ports = { input: [], output: [] }
    @ports_semaphore = Mutex.new

    module_function

    # Every port, grouped by direction.
    #
    # This is the shape `midi-communications` asks its platform adapters for.
    #
    # @return [Hash{Symbol => Array<Input>, Array<Output>}] with `:input` and
    #   `:output` keys
    #
    # @example
    #   MIDICommunicationsWindows::Device.all_by_type[:output].each { |o| puts o.name }
    def all_by_type
      { input: inputs, output: outputs }
    end

    # Every port, of both directions.
    # @return [Array<Input, Output>]
    def all
      all_by_type.values.flatten
    end

    # Every input port WinMM offers.
    # @return [Array<Input>]
    # @raise [Error] if WinMM refuses to describe a port it has just counted
    def inputs
      enumerate(:input, API.midiInGetNumDevs, Input)
    end

    # Every output port WinMM offers.
    #
    # Note that this does not include the MIDI Mapper, which WinMM addresses by
    # the reserved id `-1` and does not count among its devices.
    #
    # @return [Array<Output>]
    # @raise [Error] if WinMM refuses to describe a port it has just counted
    def outputs
      enumerate(:output, API.midiOutGetNumDevs, Output)
    end

    # Asks WinMM what ports exist, reusing the wrapper for each one that was
    # already there.
    #
    # The list is read afresh every time, so a port that appeared or went away
    # is reflected — but a port that is still present comes back as the object
    # it came back as last time. Otherwise `Input.first.open` and
    # `Input.first.gets` would be two different objects, and the second would
    # not be open.
    #
    # "Still present" means the same index reporting the same name. The index
    # alone is not enough: WinMM renumbers, so index 1 after a device is
    # unplugged may be a different port than index 1 before, and handing back a
    # wrapper holding a handle to the old one would be worse than making a new
    # object.
    #
    # @param direction [Symbol] `:input` or `:output`
    # @param count [Integer] how many ports WinMM reports for that direction
    # @param klass [Class] {Input} or {Output}
    # @return [Array<Input>, Array<Output>]
    # @api private
    def enumerate(direction, count, klass)
      @ports_semaphore.synchronize do
        known = @ports[direction].to_h { |port| [port.id, port] }

        @ports[direction] = Array.new(count) do |id|
          name = direction == :input ? input_name(id) : output_name(id)
          previous = known[id]

          previous && previous.name == name ? previous : klass.new(id, name)
        end
      end
    end

    # The name of an input port.
    #
    # @param id [Integer] the port's WinMM index
    # @return [String]
    # @api private
    def input_name(id)
      capabilities = API::MIDIInCaps.new

      API.check!(API.midiInGetDevCapsW(id, capabilities, API::MIDIInCaps.size),
                 :midiInGetDevCapsW, :input)

      port_name(capabilities)
    end

    # The name of an output port.
    #
    # @param id [Integer] the port's WinMM index
    # @return [String]
    # @api private
    def output_name(id)
      capabilities = API::MIDIOutCaps.new

      API.check!(API.midiOutGetDevCapsW(id, capabilities, API::MIDIOutCaps.size),
                 :midiOutGetDevCapsW, :output)

      port_name(capabilities)
    end

    # Reads `szPname` out of a capabilities structure.
    #
    # @param capabilities [API::MIDIInCaps, API::MIDIOutCaps]
    # @return [String]
    # @api private
    def port_name(capabilities)
      API.read_wide_string(capabilities.to_ptr + capabilities.offset_of(:szPname), API::MAXPNAMELEN)
    end
  end
end
