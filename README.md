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

**Early.** Enumeration, sending, receiving and System Exclusive in both
directions all work, and have been exercised on Windows 11 25H2.

Not yet exercised, all of it for want of a physical MIDI interface:

* the timeout on a System Exclusive send that never completes;
* the timeout on closing a port whose device has gone away;
* ports being renumbered when one is plugged in or unplugged;
* whether an input and an output of the same device report the same name;
* the handling of a device error during System Exclusive input.

It is in the 0.0.x series for that reason, not because anything is known to be
missing.

## Requirements

* [ffi](http://github.com/ffi/ffi)

Nothing else. `winmm.dll` is part of Windows, so this gem binds a library that is
already on the machine and ships no compiled artifact of its own.

It has only been run on Windows 11. Nothing in it needs Windows 11 — it calls no
API newer than WinMM — but older versions are untested.

## Installation

If you're using Bundler, add this line to your application's Gemfile:

`gem "midi-communications-windows"`

Otherwise

`gem install midi-communications-windows`

## Usage

You will usually not use this gem directly.
[MIDI Communications](https://github.com/javier-sy/midi-communications) depends
on it and selects it on Windows, so code written against that gem runs unchanged
on macOS and Windows.

Used directly, it looks like this.

### Listing ports

```ruby
require 'midi-communications-windows'

MIDICommunicationsWindows::Device.all_by_type[:output].each do |port|
  puts "#{port.id}: #{port.name}"
end
```

### Sending

```ruby
output = MIDICommunicationsWindows::Output.first

output.open do |port|
  port.puts(0x90, 60, 100)   # Note On, middle C
  sleep 0.5
  port.puts(0x80, 60, 0)     # Note Off
end
```

`puts` also takes an array of bytes, a hex string, or a System Exclusive message:

```ruby
output.puts([0x90, 60, 100])
output.puts('903C64')
output.puts([0xF0, 0x41, 0x10, 0x42, 0x12, 0xF7])
```

### Receiving

```ruby
input = MIDICommunicationsWindows::Input.first.open

loop do
  input.gets.each do |message|
    puts message.inspect
    # => {:data=>[144, 60, 100], :timestamp=>1789123456.789}
  end
end
```

**`gets` waits.** It does not return an empty array when nothing has arrived; it
blocks until something does, and then returns every message that accumulated. On
a quiet port that looks exactly like a hung program. It is deliberate — a reader
loop needs no delay of its own, and adding one only delays messages that are
already waiting — but it will surprise anyone arriving from an API that polls.

More in [`examples/`](examples).

## What MIDI on Windows will not give you

Behaviour that differs from the macOS layer, and that you may run into:

* **`manufacturer` and `model` are always `nil`.** Windows reports numeric codes
  rather than names, and no honest string can be derived from them. Code that
  filters on either will match nothing.
* **A port's `id` is unique within its direction, not across both.** Input 0 and
  output 0 are different ports and both are valid.
* **Port names are truncated to 31 characters, and do not identify a port.**
  Windows stores no more and drops the rest silently, so two ports whose names
  differ only past that point arrive indistinguishable in everything Windows
  reports about them except their index. Where it matters, select by `id`:
  `find_by_name` can only answer with the first match.
* **Whether two programs can open the same port depends on the port**, not on
  this library. Under Windows MIDI Services, on Windows 11, ports carried by the
  new transports are shared; ports still on the older drivers are exclusive, as
  they always were, and so is everything on Windows 10.
* **Routing MIDI between applications on one machine has to be set up.** Windows
  has no equivalent of the IAC bus macOS provides. On Windows 11 the Windows MIDI
  Services tools — a separate download — can create loopback endpoints, which
  this library then sees as ordinary ports; otherwise a third-party driver such
  as loopMIDI does the same job.

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
direct binding rather than a wrapper around an existing C library, and what each
of those choices cost, are in
[`dev/design-notes.md`](https://github.com/javier-sy/midi-communications-windows/blob/master/dev/design-notes.md).

How the measurements above were taken, and how to rebuild the environment they
were taken in, are in
[`dev/testing-on-windows.md`](https://github.com/javier-sy/midi-communications-windows/blob/master/dev/testing-on-windows.md).

Neither is part of the published gem, which is why those are links and not paths.

## Author

* [Javier Sánchez Yeste](https://github.com/javier-sy)

## License

[MIDI Communications Windows Layer](https://github.com/javier-sy/midi-communications-windows) Copyright (c) 2026 [Javier Sánchez Yeste](https://yeste.studio), licensed under LGPL 3.0 License
