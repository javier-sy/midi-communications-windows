# Testing this gem on Windows without MIDI hardware

*Written 2026-09-06. Section 1 is the part with a shelf life: it describes
software that was in preview at the time, which Microsoft's release notes said
was headed for Windows 11 25H2 and later during the last week of November 2026.
If that has happened, most of section 1 collapses into "nothing to install" and
the rest still applies.*

This is **the procedure the library was measured with**, not a promise that it
works on another machine. All of it ran once, on one particular installation.
Where something was checked, it says so; where it was not, it says that too.

The machine was:

| | |
|---|---|
| Windows | 11 25H2, build **26200.9278** |
| CPU | ARM64 — a VMware VM on Apple silicon |
| Ruby | 3.4.10 `x64-mingw-ucrt`, **emulated** under Prism (no ARM64 Ruby present) |
| ffi | 1.17.4 `x64-mingw-ucrt`, precompiled binary |
| MIDI hardware | **none** — no USB device passed through to the guest |

That last row is why this document exists: with no hardware, a loopback pair is
the only way to exercise input and output at the same time.

Nothing measured on this setup says anything about **timing**. Emulation inside
a virtual machine; latency and jitter need real hardware and a native Ruby.

---

## 1. What has to be installed

Windows 11 25H2 ships **Windows MIDI Services** in the box: the `midisrv`
service (`C:\Windows\System32\midisrv.exe`) and the `wdmaud2.drv` shim,
registered as `midi1` under
`HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Drivers32`. That shim is what
makes endpoints from the new stack **visible to WinMM** without this gem doing
anything special, and therefore what makes this setup able to test a gem that
speaks only WinMM.

What is *not* in the box are the MIDI 1.0 loopback transport and the tools. Those
come from the [`microsoft/MIDI`] repository, release `inbox-dev-preview-6`:

- `Windows.MIDI.Services.Basic.MIDI.1.0.Loopback.Preview.1.0.18-preview.3-arm64.exe`
- `Windows.MIDI.Services.Tools.0.99.64-devpreview.6-arm64.exe`

There are `-x64` variants of both. The measuring machine used the **native ARM64**
ones (PE header `0xAA64`) even though the Ruby was emulated x64: the gem talks to
`winmm.dll`, and Windows handles the crossing.

The Network and Bluetooth transports from the same release are not needed.

[`microsoft/MIDI`]: https://github.com/microsoft/MIDI/releases

### Warnings that are not optional

- **These are unsigned preview binaries.** The release notes require Windows
  **Developer Mode**, and are explicit: *"There are almost certainly bugs and
  missing/incomplete features."* This is not production software.
- **Do not redistribute them.** The release's permitted-use table forbids it. A
  repository should link to the release and never host the installers.
- Minimum system version declared: **Windows 11 25H2**.
- Downloaded through a browser they carry Mark of the Web and SmartScreen will
  object; `Unblock-File` clears it. Fetched with `Invoke-WebRequest` they do not.

## 2. Installing

Both installers are **WiX bundles**, so they accept `/quiet`, `/norestart` and
`/log`. Both need **elevation**, and Developer Mode writes to `HKLM`, so it is
worth doing the whole thing in one elevated script and getting one UAC prompt.

The release notes fix the order: **loopback transport first, tools second.**

```powershell
# --- 1. Developer Mode (the key may not exist)
$k = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
Set-ItemProperty $k -Name AllowDevelopmentWithoutDevLicense -Value 1 -Type DWord
Set-ItemProperty $k -Name AllowAllTrustedApps -Value 1 -Type DWord

# --- 2. installers, in this order
Start-Process -Wait -FilePath '<...>Basic.MIDI.1.0.Loopback.Preview...-arm64.exe' `
  -ArgumentList '/quiet','/norestart','/log','loopback.log'
Start-Process -Wait -FilePath '<...>Tools.0.99.64-devpreview.6-arm64.exe' `
  -ArgumentList '/quiet','/norestart','/log','tools.log'
```

**Both return exit `3010`**, which is `ERROR_SUCCESS_REBOOT_REQUIRED`: installed
correctly, reboot pending. The measuring machine **was not rebooted**, and every
measurement was taken that way. If something behaves oddly, that reboot is the
first suspect.

To check the transport registered:

```powershell
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows MIDI Services\Transport Plugins'
# Midi2BasicLoopbackMidiTransport should appear, with Enabled = 1
```

### `midi.exe` and the PATH

The console lands at:

```
C:\Program Files\Windows MIDI Services\Tools\Console\midi.exe
```

The installer **does** add it to the machine PATH, but **a shell opened before
installing still has the old environment** and will say `midi` does not exist. In
a fresh shell, `midi` is enough; in the installing shell, use the full path. This
detail cost time and produced one wrong report before it was noticed.

## 3. Creating the loopback pair

```powershell
$midi = 'C:\Program Files\Windows MIDI Services\Tools\Console\midi.exe'

& $midi basic-loopback create --name "Reloj Bitwig ñ prueba de longitud"
& $midi basic-loopback list
```

Options for `create`:

| option | what it does |
|---|---|
| `-n`, `--name` | the endpoint's name |
| `-u`, `--unique-identifier` | an identifier of your own |
| `-s`, `--save-to-config` | **persists it in the system configuration** |

**Without `--save-to-config` a loopback is temporary**: it disappears when
`midisrv` or the machine restarts, and nothing is written to disk. Every
measurement was taken that way, deliberately. `--save-to-config` does modify the
user's system configuration — ask before using it.

A `create` returns an **Association Id**, a GUID. Keep it: it is the only thing
that will remove the loopback again.

### Checking through WinMM, which is what the gem sees

```
ruby -Ilib examples/list_ports.rb
```

One loopback shows up as **one input and one output with the same name, byte for
byte**. With two loopbacks created, enumeration gives 2 inputs and 3 outputs —
the third being the *Microsoft GS Wavetable Synth*, which is always there.

## 4. The name-collision recipe

WinMM stores **31 characters** of a name (`MAXPNAMELEN` is 32, less the NUL) and
drops the rest **silently**. To reproduce the case where two distinct ports are
indistinguishable, create two loopbacks whose **first 31 characters match**:

```powershell
& $midi basic-loopback create --name "Reloj Bitwig ñ prueba de longitud"
& $midi basic-loopback create --name "Reloj Bitwig ñ prueba de longitud DOS"
```

The first is 33 characters, the second 37; both truncate to
`Reloj Bitwig ñ prueba de longit`. In `MIDIINCAPSW`/`MIDIOUTCAPSW` they come back
**identical field by field**: same name, same `wMid` (1), same `wPid` (25 for
inputs, 26 for outputs), same `vDriverVersion`, same `wTechnology`. Only the
index separates them.

If you change the names, keep the character counts working — the recipe depends
on one being longer than 31 and both agreeing up to that point.

The truncation happens **upstream of WinMM**: `midi enumerate
midi-services-endpoints` shows the service already holding the 31-character name.
Whether the console or the service truncates was not determined; for the gem it
makes no difference.

The `ñ` survives intact (`U+00F1` in the UTF-16LE dump), which is what validates
the **W** entry points against a genuinely non-ASCII character.

## 5. Removing

```powershell
& $midi basic-loopback remove --association-id "{bfba125e-3aca-446c-9b94-692a70153034}"
```

**The braces around the GUID are required.** `list` prints the id without them;
they have to be added.

Afterwards, check the machine is back where it started — with `list`, and better
still by enumerating through WinMM: with no loopbacks there should be **0 inputs
and 1 output**.

## 6. What this setup can test, and what it cannot

Exercised with it, and working: enumeration with colliding names, short messages
in all three lengths (3, 2 and 1 bytes), accumulation in `gets`, System Exclusive
both ways at 200, 3000 and 5000 bytes, buffer recycling, closing and reopening,
and the propagation of an error from opening a port.

**Not testable with this setup:** anything needing a physical MIDI interface, and
any measurement of time. Some of it has since been closed elsewhere; see below.

## 6b. What a real machine closed, 2026-09-08

Windows 11 with real hardware — an Akai MPK mini Play mk3 alongside three
loopback ports — and a piece running under Bitwig's clock.

Closed:

- **Receiving from a real device, and the timings.** A piece followed the DAW's
  clock and played correctly. The earlier numbers were taken through emulation
  inside a virtual machine and meant nothing; these do.
- **An input and an output of the same device report the same name.** Previously
  established only for a loopback, where the two are literally one device. The
  MPK appears as input 3 and output 4 with names identical byte for byte —
  compared as bytes, not by eye. This is what `musalce-server` relies on when it
  pairs a clock input with an output by name.
- **A port that goes away stops being listed, and only it.** Unplugging the MPK
  removed its two entries and left the others untouched.

Still unexercised:

- **`SYSEX_TIMEOUT` / `Output#wait_until_sent`**, and **`MM_MIM_LONGERROR`**.
  Both need System Exclusive against a device slow enough to be caught mid-send.
  Sending System Exclusive works; what has never run is the path where the device
  stops responding.
- **Renumbering in `Device.enumerate`.** Unplugging the MPK did not test it: it
  was last in both lists, so nothing after it shifted. The case that matters is a
  port disappearing from the middle, which here would mean removing a loopback
  in use. The guard is that a wrapper is reused only when index *and* name match,
  so a renumbered index brings a different name and a new wrapper — reasoned, not
  observed.

## 7. One finding from here worth not forgetting

Multi-client access **follows the endpoint, not the API**. Two WinMM clients on
the same BLOOP input both work and **both receive every message**. The *GS
Wavetable Synth*, which belongs to the classic `wdmaud` stack, refuses the second
open with *"The specified device is already in use."* So on one machine, through
one API, shareable ports and exclusive ports coexist.
