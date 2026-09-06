#
# midi-communications-windows
# Realtime MIDI IO with Ruby for Windows
#
# (c)2026 Javier Sánchez Yeste, licensed under LGPL 3.0 License
#

# Libs
require 'ffi'

# Modules with no platform binding of their own, so that they load anywhere
require 'midi-communications-windows/message'
require 'midi-communications-windows/type_conversion'

# Modules and classes that bind winmm.dll
require 'midi-communications-windows/api'
require 'midi-communications-windows/device'
require 'midi-communications-windows/input'
require 'midi-communications-windows/output'

require_relative 'midi-communications-windows/version'

# Windows-specific MIDI I/O through the Windows Multimedia (WinMM) API.
#
# This library gives low-level access to MIDI ports on Windows by binding
# `winmm.dll` with FFI. It is normally used through the higher-level
# {https://github.com/javier-sy/midi-communications midi-communications} gem,
# which selects it automatically on Windows.
#
# The classes are {Input}, for receiving, and {Output}, for sending. {Device}
# enumerates both.
#
# ## Why WinMM, and not one of the newer APIs
#
# Windows has three MIDI APIs a program could use. WinMM is the oldest, and as
# of February 2026 it is also the most sensible choice for Ruby.
#
# Windows MIDI Services, generally available in Windows 11 since then, replaced
# the MIDI stack underneath. The existing MIDI 1.0 APIs were reconnected to the
# new service rather than retired, so a WinMM client stopped holding ports
# exclusively, gained multi-client access, and can see the loopback endpoints
# the system now provides itself. It also needs nothing installed to get any of
# that. On Windows 10 WinMM behaves as it always did.
#
# The new App SDK offers MIDI 2.0 and UMP, which this library does not need —
# `midi-communications` and MusaDSL are MIDI 1.0 throughout — and it is
# published only as WinRT. Microsoft's own guidance is that other languages
# need a WinRT projection from their toolchain, and Ruby has none.
#
# ## Why no compiled artifact
#
# `winmm.dll` is present on every Windows installation, so this gem binds a
# library that is already there and ships no binary of its own. The only
# compiled dependency is `ffi` itself, which is published for every Windows
# platform including ARM64. Distributing platform-specific binaries through
# RubyGems is where installations break; there is nothing here to break.
#
# @example List the output ports
#   MIDICommunicationsWindows::Output.all.each do |output|
#     puts "#{output.id}: #{output.name}"
#   end
#
# @example Send a note
#   output = MIDICommunicationsWindows::Output.first
#   output.open
#   output.puts(0x90, 60, 100)
#
# @see https://learn.microsoft.com/en-us/windows/win32/multimedia/midi-reference Microsoft's MIDI reference
#
# @api public
module MIDICommunicationsWindows
end
