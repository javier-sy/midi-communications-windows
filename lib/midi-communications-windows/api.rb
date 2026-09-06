module MIDICommunicationsWindows
  # Raised when a WinMM call reports a failure.
  #
  # WinMM reports errors as `MMRESULT` codes rather than by any out-of-band
  # mechanism, so every call is checked and a failure becomes an exception at
  # the point of the call, carrying the text WinMM itself gives for the code.
  #
  # @api public
  class Error < StandardError
    # @!attribute [r] code
    #   @return [Integer, nil] the `MMRESULT` WinMM returned, or nil for a
    #     failure WinMM did not report as a code — a call that never completed,
    #     for instance
    # @!attribute [r] operation
    #   @return [Symbol] the WinMM function that failed, e.g. `:midiInOpen`
    attr_reader :code, :operation

    # @param operation [Symbol] the WinMM function that failed
    # @param code [Integer, nil] the `MMRESULT` code, if there was one
    # @param text [String, nil] a description of the failure
    # @api private
    def initialize(operation, code, text = nil)
      @operation = operation
      @code = code

      super(build_message(operation, code, text))
    end

    private

    # @api private
    def build_message(operation, code, text)
      return "#{operation}: #{text}" unless text.nil? || text.empty?

      code.nil? ? "#{operation} failed" : "#{operation} failed with MMRESULT #{code}"
    end
  end

  # Low-level FFI bindings to the Windows Multimedia (WinMM) MIDI API.
  #
  # This module binds `winmm.dll` directly. Most users should use the
  # higher-level {Input}, {Output} and {Device} instead.
  #
  # ## Why the bindings look the way they do
  #
  # **Pointer-sized types are never `:ulong`.** Windows is LLP64: `long` stays
  # 32 bits on 64-bit Windows while `HANDLE`, `DWORD_PTR` and `UINT_PTR` are
  # pointer-sized. Measured from inside FFI on Windows 11 x64:
  # `FFI::Pointer.size` is 8 and `FFI.type_size(:ulong)` is 4. Declaring a
  # handle as `:ulong` truncates it — silently, because the low half of a
  # handle often looks plausible. Every pointer-sized parameter here is
  # `:uintptr_t`.
  #
  # **The `W` variants, never the `A` ones.** `midiInGetDevCapsA` returns the
  # port name in the machine's ANSI code page, which mangles any name that is
  # not ASCII. A user-created loopback called "Reloj Bitwig" is a realistic
  # port name, so the wide-character functions are the only correct choice.
  #
  # **`dwCallback` is `:uintptr_t`, not a callback type.** WinMM overloads that
  # parameter by the flags in `dwFlags`: it holds a function pointer under
  # `CALLBACK_FUNCTION`, a thread id under `CALLBACK_THREAD`, a window handle
  # under `CALLBACK_WINDOW`, and nothing under `CALLBACK_NULL`. Typing it as a
  # callback would make the binding lie about three of those four.
  #
  # These bindings were written from Microsoft's Win32 documentation. They are
  # not derived from any existing Ruby binding.
  #
  # @api private
  module API
    extend FFI::Library

    # user32 and kernel32 come in for the thread message queue, which is how
    # input is delivered; see {Input}. FFI searches all three for each function.
    ffi_lib 'winmm', 'user32', 'kernel32'
    # Ignored on x64, where there is a single calling convention; required on
    # 32-bit Windows, where WinMM is stdcall.
    ffi_convention :stdcall

    typedef :uint8, :BYTE
    typedef :uint16, :WORD
    typedef :uint32, :DWORD
    typedef :uint32, :MMRESULT
    typedef :uintptr_t, :DWORD_PTR
    typedef :uintptr_t, :UINT_PTR
    # Handles are opaque and pointer-sized. See the note above on LLP64.
    typedef :uintptr_t, :HMIDIIN
    typedef :uintptr_t, :HMIDIOUT

    # Length of a port name in `MIDIINCAPSW`/`MIDIOUTCAPSW`, in characters,
    # including the terminating NUL. This is the origin of WinMM's 31-character
    # limit on port names.
    MAXPNAMELEN = 32

    # `MMRESULT` value meaning success.
    MMSYSERR_NOERROR = 0

    # Characters reserved for an error description. WinMM truncates to fit.
    MAX_ERROR_TEXT_LENGTH = 256

    # How WinMM should notify a client of input. Passed in `dwFlags`; decides
    # how `dwCallback` is interpreted.
    CALLBACK_NULL     = 0x0000_0000
    CALLBACK_WINDOW   = 0x0001_0000
    CALLBACK_THREAD   = 0x0002_0000
    CALLBACK_FUNCTION = 0x0003_0000

    # Notification messages delivered for an input device.
    MM_MIM_OPEN      = 0x3C1
    MM_MIM_CLOSE     = 0x3C2
    MM_MIM_DATA      = 0x3C3
    MM_MIM_LONGDATA  = 0x3C4
    MM_MIM_ERROR     = 0x3C5
    MM_MIM_LONGERROR = 0x3C6

    # Notification messages delivered for an output device.
    MM_MOM_OPEN  = 0x3C7
    MM_MOM_CLOSE = 0x3C8
    MM_MOM_DONE  = 0x3C9

    # `MIDIHDR#dwFlags` bits.
    MHDR_DONE     = 0x0000_0001
    MHDR_PREPARED = 0x0000_0002
    MHDR_INQUEUE  = 0x0000_0004

    # Thread message queue.
    WM_QUIT     = 0x0012
    PM_NOREMOVE = 0x0000

    # Windows posts messages of its own to the same queue WinMM uses. Measured:
    # a `WM_USER` with both parameters zero follows every WinMM notification,
    # including those after the port opens and closes. Nothing here emits them
    # and nothing here knows what does, so the reader dispatches on the message
    # id and ignores everything it did not ask for.
    WM_USER = 0x0400

    # Capabilities of a MIDI input device, as `midiInGetDevCapsW` fills it.
    #
    # `szPname` is an array of UTF-16 code units, not of bytes: the field is
    # declared as `:uint16` so that reading it cannot split a character in half.
    class MIDIInCaps < FFI::Struct
      layout :wMid, :uint16,
             :wPid, :uint16,
             :vDriverVersion, :uint32,
             :szPname, [:uint16, MAXPNAMELEN],
             :dwSupport, :uint32
    end

    # Capabilities of a MIDI output device, as `midiOutGetDevCapsW` fills it.
    class MIDIOutCaps < FFI::Struct
      layout :wMid, :uint16,
             :wPid, :uint16,
             :vDriverVersion, :uint32,
             :szPname, [:uint16, MAXPNAMELEN],
             :wTechnology, :uint16,
             :wVoices, :uint16,
             :wNotes, :uint16,
             :wChannelMask, :uint16,
             :dwSupport, :uint32
    end

    # Both capability structures have a size fixed by the Win32 headers, and
    # WinMM rejects a call whose `cbSize` disagrees with what it expects. A
    # mismatch here means the layout above is wrong, and every field read from
    # it afterwards would be garbage that still looks like data — so it is
    # checked once, at load, rather than discovered as a puzzling device name
    # much later.
    #
    # Verified against Windows 11 25H2 (build 26200), winmm.dll 10.0.26100.
    raise "MIDIINCAPSW is #{MIDIInCaps.size} bytes, expected 76" unless MIDIInCaps.size == 76
    raise "MIDIOUTCAPSW is #{MIDIOutCaps.size} bytes, expected 84" unless MIDIOutCaps.size == 84

    # A buffer handed to WinMM, used for System Exclusive in both directions.
    #
    # `dwReserved` really is an array of eight pointer-sized words. Declaring it
    # as a single word makes the structure too short, and WinMM writes past the
    # end of it. This layout measures 120 bytes on 64-bit Windows, which is what
    # WinMM there expects.
    class MIDIHdr < FFI::Struct
      layout :lpData, :pointer,
             :dwBufferLength, :uint32,
             :dwBytesRecorded, :uint32,
             :dwUser, :uintptr_t,
             :dwFlags, :uint32,
             :lpNext, :pointer,
             :reserved, :uintptr_t,
             :dwOffset, :uint32,
             :dwReserved, [:uintptr_t, 8]
    end

    # Measured against winmm on 64-bit Windows 11. Checked only there, because
    # the layout's size follows the pointer size and 32-bit Windows produces a
    # different, equally correct, number.
    if FFI::Pointer.size == 8 && MIDIHdr.size != 120
      raise "MIDIHDR is #{MIDIHdr.size} bytes on 64-bit Windows, expected 120"
    end

    # Enumeration. These touch no device and can fire no callback, so they are
    # the only calls here that keep the GVL.
    attach_function :midiInGetNumDevs, [], :uint32
    attach_function :midiOutGetNumDevs, [], :uint32
    attach_function :midiInGetDevCapsW, %i[UINT_PTR pointer uint32], :MMRESULT
    attach_function :midiOutGetDevCapsW, %i[UINT_PTR pointer uint32], :MMRESULT

    # EVERY CALL BELOW RELEASES THE GVL, and that is not an optimisation.
    #
    # Measured on Windows 11 25H2 against a system loopback: with an input open
    # and a Ruby callback attached to it, a `midiOutShortMsg` that holds the GVL
    # deadlocks against the driver thread waiting for that same GVL to enter the
    # callback. The shim eventually gives up, the send returns MMSYSERR_ERROR,
    # and — this is the part that matters — the message is then delivered
    # TWICE, a second or two later. Three sends produced five, four and five
    # deliveries across three runs. System Exclusive behaved the same way: 400
    # bytes received for a 200-byte message.
    #
    # Two controls place the cause: sending with no input open succeeds, and so
    # does sending with an input open under CALLBACK_NULL. It is not the send,
    # and it is not having an input open. It is a Ruby callback waiting for the
    # GVL held by the thread that is sending.
    #
    # The failure is quiet. Nothing raises; the port simply emits notes nobody
    # asked for. So the rule is structural rather than case by case: anything
    # that can reach a device is declared blocking, and a function added here
    # later should be too.
    attach_function :midiInOpen, %i[pointer uint32 DWORD_PTR DWORD_PTR DWORD], :MMRESULT, blocking: true
    attach_function :midiInClose, [:HMIDIIN], :MMRESULT, blocking: true
    attach_function :midiInStart, [:HMIDIIN], :MMRESULT, blocking: true
    attach_function :midiInStop, [:HMIDIIN], :MMRESULT, blocking: true
    attach_function :midiInReset, [:HMIDIIN], :MMRESULT, blocking: true

    attach_function :midiOutOpen, %i[pointer uint32 DWORD_PTR DWORD_PTR DWORD], :MMRESULT, blocking: true
    attach_function :midiOutClose, [:HMIDIOUT], :MMRESULT, blocking: true
    attach_function :midiOutReset, [:HMIDIOUT], :MMRESULT, blocking: true

    # Sending
    attach_function :midiOutShortMsg, %i[HMIDIOUT DWORD], :MMRESULT, blocking: true
    attach_function :midiOutLongMsg, %i[HMIDIOUT pointer uint32], :MMRESULT, blocking: true
    attach_function :midiOutPrepareHeader, %i[HMIDIOUT pointer uint32], :MMRESULT, blocking: true
    attach_function :midiOutUnprepareHeader, %i[HMIDIOUT pointer uint32], :MMRESULT, blocking: true

    # Receiving System Exclusive
    attach_function :midiInPrepareHeader, %i[HMIDIIN pointer uint32], :MMRESULT, blocking: true
    attach_function :midiInUnprepareHeader, %i[HMIDIIN pointer uint32], :MMRESULT, blocking: true
    attach_function :midiInAddBuffer, %i[HMIDIIN pointer uint32], :MMRESULT, blocking: true

    # Diagnostics
    attach_function :midiInGetErrorTextW, %i[MMRESULT pointer uint32], :MMRESULT
    attach_function :midiOutGetErrorTextW, %i[MMRESULT pointer uint32], :MMRESULT

    # A message waiting in a thread's queue.
    #
    # `POINT pt` is spelled out as two fields because nothing here reads it and
    # a nested structure would earn its keep only in a mouse handler. The size
    # is 48 bytes on 64-bit Windows, which is what the queue functions expect.
    class MSG < FFI::Struct
      layout :hwnd, :pointer,
             :message, :uint32,
             :wParam, :uintptr_t,
             # LPARAM is a signed LONG_PTR in the headers. It is read unsigned
             # here because every value this library takes from it is either a
             # packed MIDI word or a pointer, and a high address arriving as a
             # negative number would not survive being turned back into one.
             :lParam, :uintptr_t,
             :time, :uint32,
             :pt_x, :int32,
             :pt_y, :int32
    end

    raise "MSG is #{MSG.size} bytes on 64-bit Windows, expected 48" if FFI::Pointer.size == 8 && MSG.size != 48

    # The thread message queue.
    #
    # `GetMessageW` blocks, so it releases the GVL like everything else that can
    # wait. It returns an int and not a boolean: above zero for a message, zero
    # for `WM_QUIT`, and -1 for an error — which is why `BOOL` is bound as `:int`
    # throughout. FFI's `:bool` is one byte and would read only the low half of
    # a `BOOL` that Windows defines as a four-byte int.
    attach_function :GetCurrentThreadId, [], :uint32
    attach_function :GetMessageW, %i[pointer pointer uint32 uint32], :int, blocking: true
    attach_function :PeekMessageW, %i[pointer pointer uint32 uint32 uint32], :int
    attach_function :PostThreadMessageW, %i[uint32 uint32 uintptr_t uintptr_t], :int

    module_function

    # Raises unless the call succeeded.
    #
    # @param code [Integer] the `MMRESULT` a WinMM call returned
    # @param operation [Symbol] the function that returned it, for the message
    # @param direction [Symbol] `:input` or `:output`, to pick the error table
    # @return [void]
    # @raise [Error] when `code` is anything but `MMSYSERR_NOERROR`
    def check!(code, operation, direction)
      return if code == MMSYSERR_NOERROR

      raise Error.new(operation, code, error_text(code, direction))
    end

    # WinMM's own description of an error code.
    #
    # The two error tables are not the same, which is why the direction has to
    # be known: the same numeric code can mean different things for input and
    # for output.
    #
    # @param code [Integer] an `MMRESULT`
    # @param direction [Symbol] `:input` or `:output`
    # @return [String, nil] the description, or nil if WinMM has none
    def error_text(code, direction)
      buffer = FFI::MemoryPointer.new(:uint16, MAX_ERROR_TEXT_LENGTH)

      result = case direction
               when :input then midiInGetErrorTextW(code, buffer, MAX_ERROR_TEXT_LENGTH)
               when :output then midiOutGetErrorTextW(code, buffer, MAX_ERROR_TEXT_LENGTH)
               end

      read_wide_string(buffer, MAX_ERROR_TEXT_LENGTH) if result == MMSYSERR_NOERROR
    end

    # Reads a NUL-terminated UTF-16LE string out of native memory.
    #
    # Reading is done in code units rather than bytes on purpose: a byte-wise
    # search for a NUL pair would stop in the middle of a pair such as
    # `'A' 'Ā'` (`41 00 00 01`) and return a truncated name.
    #
    # A name that does not decode is repaired rather than raised on: a port
    # whose name arrives mangled is still a port the caller may want to open,
    # and losing the whole enumeration over one bad character would be worse
    # than showing a replacement character.
    #
    # @param pointer [FFI::Pointer] memory holding the string
    # @param max_characters [Integer] capacity of the field, in characters
    # @return [String] the decoded string, in UTF-8
    def read_wide_string(pointer, max_characters)
      units = pointer.read_array_of_uint16(max_characters)
      units = units.take_while { |unit| !unit.zero? }

      units.pack('S<*')
           .force_encoding(Encoding::UTF_16LE)
           .encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    end
  end
end
