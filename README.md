# MIDI Communications Windows Layer

[![Ruby Version](https://img.shields.io/badge/ruby-2.7+-red.svg)](https://www.ruby-lang.org/)
[![License](https://img.shields.io/badge/license-LGPL--3.0--or--later-blue.svg)](https://www.gnu.org/licenses/lgpl-3.0.html)

**Realtime MIDI IO with Ruby for Windows.**

Access the [Windows Multimedia (WinMM) MIDI API](https://learn.microsoft.com/en-us/windows/win32/multimedia/midi-reference) with Ruby.

This library is part of a suite of Ruby libraries for MIDI:

| Function | Library |
| --- | --- |
| MIDI Events representation | [MIDI Events](https://github.com/javier-sy/midi-events) |
| MIDI Data parsing | [MIDI Parser](https://github.com/javier-sy/midi-parser) |
| MIDI communication with Instruments and Control Surfaces | [MIDI Communications](https://github.com/javier-sy/midi-communications) |
| Low level MIDI interface to MacOS | [MIDI Communications MacOS Layer](https://github.com/javier-sy/midi-communications-macos) |
| Low level MIDI interface to Windows | [MIDI Communications Windows Layer](https://github.com/javier-sy/midi-communications-windows) (this library) |
| Low level MIDI interface to Linux | **TO DO** (by now [MIDI Communications](https://github.com/javier-sy/midi-communications) uses [alsa-rawmidi](http://github.com/arirusso/alsa-rawmidi)) |
| Low level MIDI interface to JRuby | **TO DO** (by now [MIDI Communications](https://github.com/javier-sy/midi-communications) uses [midi-jruby](http://github.com/arirusso/midi-jruby)) |

## Status

**Early.** Everything is written and has been exercised end to end on Windows 11
25H2 against system loopback endpoints: enumeration, short messages in both
directions, System Exclusive in both directions including a message larger than
the whole buffer queue, twenty open/close cycles, and the error path. What has
not been exercised is anything needing real hardware — a physical interface slow
enough to make `Output`'s System Exclusive wait mean something, and a port
appearing or disappearing while the program runs.

The version says 0.0.1 because that is a virtual machine with no MIDI hardware
in it, not because anything is known to be missing.

### One thing worth knowing before you use it

`Input#gets` **waits**. It does not return an empty array when nothing has
arrived; it blocks until something does, and then returns everything that
accumulated. Calling it on a quiet port looks exactly like a hung program. That
is deliberate — `Musa::Clock::InputMidiClock` reads in a loop with no delay of
its own and relies on it — but it will surprise anyone arriving from an API that
polls.

## Requirements

* [ffi](http://github.com/ffi/ffi)

Nothing else. `winmm.dll` is part of Windows, so this gem binds a library that
is already on the machine and ships no compiled artifact of its own.

## Installation

If you're using Bundler, add this line to your application's Gemfile:

`gem "midi-communications-windows"`

Otherwise

`gem install midi-communications-windows`

## Documentation

[rdoc](http://rubydoc.info/github/javier-sy/midi-communications-windows)

## Why WinMM and not one of the newer Windows MIDI APIs

Windows has three MIDI APIs a program could reach for, and as of February 2026
the oldest is the right one for Ruby.

**Windows MIDI Services** became generally available in Windows 11 in February
2026, replacing the MIDI stack underneath. Rather than retiring the older APIs,
Microsoft reconnected them to the new service, so a WinMM client needs nothing
installed to reach what the new stack provides — including the loopback
endpoints the system now creates itself, which is what previously required a
third-party driver.

Multi-client access arrives the same way, but **per endpoint, not per API**.
Measured on Windows 11 25H2 through this library: two clients opened the same
loopback input at once and both received every message, while a second open of
the classic `wdmaud` software synthesiser was refused with "The specified device
is already in use". Endpoints carried by the new transports are shared;
endpoints still on the old drivers are exclusive, as they always were. On
Windows 10 there is no Windows MIDI Services at all.

**The Windows MIDI Services App SDK** offers MIDI 2.0 and UMP, neither of which
this library needs: `midi-communications` and MusaDSL are MIDI 1.0 throughout.
It is published only as WinRT, and Microsoft's guidance is that other languages
obtain a WinRT projection from their toolchain. Ruby has none.

**WinRT `Windows.Devices.Midi`** is, under the new stack, another compatibility
layer onto the same service. It offers what WinMM offers, in exchange for
hand-written COM.

## Differences from the macOS layer

The two libraries implement the same contract over platforms that do not have
the same shape. Where they differ, they differ because the platforms do:

* **`manufacturer` and `model` are `nil`.** WinMM reports `wMid` and `wPid`,
  numeric codes from a manufacturer registry that stopped being maintained in
  the 1990s and that class-compliant USB devices almost all answer with
  Microsoft's. Core MIDI reports real strings. Inventing text from the codes
  would describe the code table, not the hardware.
* **`display_name` is the port name.** On macOS it is composed as
  "manufacturer model (name)", which here would be a name wrapped in the
  punctuation of two absent fields.
* **Port ids are unique within a direction, not across both.** A WinMM port is
  identified by its index among inputs or among outputs, and that index is what
  is passed to `midiInOpen`. Core MIDI numbers endpoints of both directions from
  one counter. Input 0 and output 0 are both valid here, and unrelated.
* **Port names are truncated to 31 characters, and do not identify a port.**
  That is all WinMM stores, and it drops the rest silently. Two loopback
  endpoints whose names differed only past character 31 came back identical in
  every field of `MIDIINCAPSW` — same name, same `wMid`, same `wPid`, same
  `wTechnology` — distinguishable only by index. Core MIDI names are neither
  truncated nor, in practice, ambiguous.
* **Enumeration is not cached, but wrappers are reused.** The macOS layer reads
  the device list once and keeps it, so a device plugged in later is never seen.
  Here WinMM is asked on every call, and a port still present comes back as the
  same object it was before, so opening a port and then reading from it works
  whether or not the caller kept the reference.
* **There is no packet-list parsing.** Core MIDI delivers a list of packets that
  has to be walked; WinMM delivers one complete short message at a time, with
  running status already resolved by the driver.

## Relationship to midi-winmm

This library is **not** derived from [midi-winmm](http://github.com/arirusso/midi-winmm),
which was written in 2011 for 32-bit Ruby. Windows is LLP64: on a 64-bit Ruby,
`unsigned long` is 32 bits while a `HANDLE` is 64, so that library's
`typedef :ulong, :HANDLE` truncates every handle it obtains. It also reads port
names through the ANSI entry points, which mangle any name that is not ASCII.
Both are addressed here by construction; see the notes in
`lib/midi-communications-windows/api.rb`.

## Author

* [Javier Sánchez Yeste](https://github.com/javier-sy)

## License

[MIDI Communications Windows Layer](https://github.com/javier-sy/midi-communications-windows) Copyright (c) 2026 [Javier Sánchez Yeste](https://yeste.studio), licensed under LGPL 3.0 License
