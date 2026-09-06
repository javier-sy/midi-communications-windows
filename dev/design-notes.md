# Why this library is the way it is

*Written 2026-09-06.*

Decisions that shaped the whole library, and that therefore live in no single
file. The reasoning behind each individual mechanism is in the comment beside it
— why `dwCallback` is typed `:uintptr_t`, why every call that can reach a device
releases the GVL, why a short message's length has to come from its status byte
— and is not repeated here.

None of this is documentation for someone using the gem. It is the record of
what was decided and what the alternatives cost.

## Why WinMM, and not one of the newer Windows MIDI APIs

Windows offers three, and as of February 2026 the oldest is the right one for
Ruby.

**Windows MIDI Services** became generally available in Windows 11 that month,
replacing the MIDI stack underneath. Rather than retiring the older APIs,
Microsoft reconnected them to the new service: `wdmaud2.drv`, registered as
`midi1` in `Drivers32`, is the shim that lets a WinMM client reach endpoints the
new stack owns. That is what makes WinMM a first-class target in 2026 rather
than a legacy one, and it is also what made the test environment possible — the
loopback endpoints used throughout were created by the new stack and read
through WinMM without this library knowing.

Two things about it are easy to state too broadly, and the README used to:

* The service is in the box on Windows 11 25H2. **The MIDI 1.0 loopback
  transport and the console tools are not** — they came from a preview release
  of `microsoft/MIDI`, installed by hand. See `testing-on-windows.md` §1.
* Loopback endpoints are not created by the system. A person creates them, with
  `midi basic-loopback create`.

**The Windows MIDI Services App SDK** offers MIDI 2.0 and UMP, neither of which
this library needs: `midi-communications` and MusaDSL are MIDI 1.0 throughout.
It is published only as WinRT, and Microsoft's guidance is that other languages
obtain a WinRT projection from their toolchain. Ruby has none.

**WinRT `Windows.Devices.Midi`** is, under the new stack, another compatibility
layer onto the same service. It offers what WinMM offers, in exchange for
hand-written COM.

## Why a direct binding, and not RtMidi or PortMidi

Wrapping an existing C library would have meant shipping a compiled artifact per
platform, and that is precisely where installations break. The gem's siblings
had just spent several days on `sqlite-vec` publishing binaries under platform
names no Windows Ruby resolves, which also prevented the lockfile from naming
`x64-mingw-ucrt` at all.

`winmm.dll` is on every Windows machine. Binding it directly means the only
compiled dependency is `ffi`, which its maintainers publish correctly for every
Windows platform including ARM64 — so `midi-communications` can declare both
platform layers as unconditional runtime dependencies, RubyGems having no
conditional ones, and each simply goes unused where it does not apply.

The cost is that Linux gains nothing from this work. A third adapter over ALSA
would be a third piece of FFI. That is the price of not depending on a
cross-platform C library, and it was judged worth paying.

## Why it is not derived from midi-winmm

[midi-winmm](http://github.com/arirusso/midi-winmm) is Apache 2.0 — the RubyGems
page says otherwise, but the repository carries a LICENSE — so reuse was legally
open. It was rejected on technical grounds.

It was written in 2011 for a 32-bit Ruby, and declares

```ruby
typedef :ulong, :HANDLE
typedef :ulong, :DWORD_PTR
```

Windows is LLP64: `unsigned long` stays 32 bits on 64-bit Windows while `HANDLE`
and `DWORD_PTR` are pointer-sized. Measured from inside FFI on Windows 11 x64,
`FFI::Pointer.size` is 8 and `FFI.type_size(:ulong)` is 4, so every handle it
obtains is truncated — silently, because the low half of a handle often looks
plausible. It also reads port names through the ANSI entry points, which mangle
anything not ASCII, and declares `MIDIHDR`'s `dwReserved` as one word where the
header has eight, leaving the structure short enough for WinMM to write past.

It was read, and it was useful: as a list of which WinMM functions are needed.
Nothing was copied.

## Why the model has holes where macOS does not

The portable contract in `midi-communications` is satisfied differently here,
and in each case the difference is the platform's, not a shortcut.

**`manufacturer` and `model` are `nil`.** WinMM reports `wMid` and `wPid`,
numeric codes from the MMSYSTEM registry, unmaintained since the 1990s. Measured
across every port on a Windows 11 machine — a software synthesiser and two
loopback endpoints — `wMid` was 1, Microsoft, every time; `wPid` was 25 for every
input and 26 for every output, the same for two different devices, so it names a
class and a direction rather than a model. Deriving text from those would
describe the code table and present it as a fact about the hardware. Returning
nil lets a consumer tell "does not match" from "not known here".

**`display_name` is the port name.** The macOS layer composes
`"#{manufacturer} #{model} (#{name})"`, which here would render as a name wrapped
in the punctuation of two absent fields.

**Ids are unique within a direction.** A WinMM port is identified by its index
among inputs or among outputs, and that index is the handle passed to
`midiInOpen`: it is the platform's real identity. Core MIDI numbers endpoints of
both directions from one counter, but nothing in `midi-communications` compares
an id across directions, and shifting the output indices to imitate Core MIDI
would replace a real identity with an invented one.

**Names identify nothing.** WinMM stores 31 characters and drops the rest in
silence. Two loopback endpoints created deliberately to collide came back
identical in every field of `MIDIINCAPSW` — same name, `wMid`, `wPid`,
`vDriverVersion` and `wTechnology` — separable only by index. Windows does hold
a stable unique identifier for each endpoint, the device interface id, but
`midiInGetDevCapsW` does not carry it: it is reachable only from the newer APIs.
This is why `PhysicalLayer` in `midi-communications` now states that a name is a
label rather than an identifier.

**There is no packet-list parsing.** Core MIDI delivers a list of packets that
has to be walked, with running status to resolve; WinMM delivers one complete
short message at a time, already resolved by the driver. The whole
`find_next_length_index` layer of the macOS `Source` has no counterpart here.

**Enumeration asks WinMM every time.** The macOS layer keeps its own device
list, and `midi-communications` memoises on top of both until `Loader.refresh`
is called (added in 0.7.1 for exactly this reason). Here the platform is asked
on every call, and a port that is still present comes back as the same wrapper
object it was before — compared by index *and* name, since Windows renumbers.
Without that, `Input.first.open` followed by `Input.first.gets` would be two
different objects and the second would not be open.

## Multi-client, measured

Whether a port can be opened by more than one program follows the endpoint, not
the API. On one Windows 11 25H2 machine, through this library: two clients
opened the same loopback input and both received every message, while a second
open of the classic `wdmaud` software synthesiser was refused with *"The
specified device is already in use."*

So shareable and exclusive ports coexist on the same machine, behind the same
API. Anything that needs to share a port — `musalce-server` needs to share the
one carrying MIDI clock — cannot assume either.

## An expectation that has never been tested

The library should work on a 32-bit Ruby: the two structure-size checks that only
hold on 64-bit Windows are guarded, the two checked unconditionally describe
layouts independent of word size, and `ffi_convention :stdcall` is declared,
which matters only there. Nobody has run it. It is recorded as an expectation
because the code was written with it in mind, not as a claim.
