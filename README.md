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

**Early.** Tested on Windows 11 without external MIDI devices. Everything works
against loopback ports; running it against real hardware is still pending.

## Requirements

* [ffi](http://github.com/ffi/ffi)

## Installation

If you're using Bundler, add this line to your application's Gemfile:

`gem "midi-communications-windows"`

Otherwise

`gem install midi-communications-windows`

## Documentation

[rdoc](https://www.rubydoc.info/gems/midi-communications-windows)

## Author

* [Javier Sánchez Yeste](https://github.com/javier-sy)

## License

[MIDI Communications Windows Layer](https://github.com/javier-sy/midi-communications-windows) Copyright (c) 2026 [Javier Sánchez Yeste](https://yeste.studio), licensed under LGPL 3.0 License
