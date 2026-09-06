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

You will normally reach it through
[MIDI Communications](https://github.com/javier-sy/midi-communications), which
depends on it and selects it on Windows. It implements that gem's physical layer
contract; anything about how ports behave is documented there, in
`MIDICommunications::PhysicalLayer`.

## Features

* Simplified API
* Input and output on multiple devices concurrently
* Generalized handling of different MIDI Message types (including SysEx)
* Timestamped input events
* Patch MIDI via software to other programs using a loopback endpoint
* No compiled artifact: `winmm.dll` is part of Windows

Runnable examples of the API are in [`examples/`](examples).

## Status

**Early.** Enumeration, sending, receiving and System Exclusive in both
directions work, and were exercised on Windows 11 25H2. What has not been
exercised is anything needing a physical MIDI interface: the two timeouts, ports
being renumbered when one is plugged in or unplugged, whether an input and an
output of the same device report the same name, and the handling of a device
error during System Exclusive input.

It is in the 0.0.x series for that reason, not because anything is known to be
missing.

## Two things Windows does differently

* **Whether two programs can open the same port depends on the port.** Under
  Windows MIDI Services, on Windows 11, ports carried by the new transports are
  shared; ports still on the older drivers are exclusive, as they always were,
  and so is everything on Windows 10.
* **Routing MIDI between applications has to be set up.** Windows has no
  equivalent of the IAC bus macOS provides. On Windows 11 the Windows MIDI
  Services tools — a separate download — create loopback endpoints, which this
  library then sees as ordinary ports; otherwise a third-party driver such as
  loopMIDI does the same job.

## Requirements

* [ffi](http://github.com/ffi/ffi)

It has only been run on Windows 11. Nothing in it needs Windows 11 — it calls no
API newer than WinMM — but older versions are untested.

## Installation

If you're using Bundler, add this line to your application's Gemfile:

`gem "midi-communications-windows"`

Otherwise

`gem install midi-communications-windows`

## Documentation

[rdoc](https://www.rubydoc.info/gems/midi-communications-windows)

## Replaces midi-winmm

Until now [MIDI Communications](https://github.com/javier-sy/midi-communications)
reached Windows through [midi-winmm](http://github.com/arirusso/midi-winmm), last
released in 2011 and unusable on a 64-bit Ruby. This is a new implementation,
written from Microsoft's documentation rather than derived from that one, and it
is what `midi-communications` uses on Windows from version 0.7.1.

## Notes for contributors

Why this binds WinMM rather than one of the newer Windows MIDI APIs, why it is a
direct binding rather than a wrapper around an existing C library, and why the
model has holes where the macOS layer does not, are in
[`dev/design-notes.md`](https://github.com/javier-sy/midi-communications-windows/blob/master/dev/design-notes.md).

How the measurements above were taken, and how to rebuild the environment they
were taken in, are in
[`dev/testing-on-windows.md`](https://github.com/javier-sy/midi-communications-windows/blob/master/dev/testing-on-windows.md).

Neither is part of the published gem, which is why those are links and not paths.

## Author

* [Javier Sánchez Yeste](https://github.com/javier-sy)

## License

[MIDI Communications Windows Layer](https://github.com/javier-sy/midi-communications-windows) Copyright (c) 2026 [Javier Sánchez Yeste](https://yeste.studio), licensed under LGPL 3.0 License
