# UCSD p-System IV.0 on MultiComp and the ZX Spectrum Next

Boot chains that start **UCSD Pascal (p-System IV.0)** on two machines it was
never adapted for, in both cases from a `.COM` file typed at a CP/M prompt.

The Adaptable Z80 p-System distribution runs unmodified on top of each machine's
existing CP/M, with a small shim translating between the two systems'
incompatible conventions. Nothing in the p-System itself is patched.

Both ports were developed and debugged **entirely on real hardware** — no
emulator was available for either target — which is why the sources carry so
much commentary about *why* each piece is the way it is, and why the repository
keeps its diagnostic builds.

```
A>PASBOOT

UCSD p-System IV.0

Command: E(dit, R(un, F(ile, C(omp, L(ink, X(ecute, A(ssem, D(ebug,? [IV.0 B2r]
```

## The two ports

| | MultiComp | ZX Spectrum Next |
|---|---|---|
| Hardware | Grant Searle's design on MiSTer FPGA | ZX Spectrum Next |
| Host OS | CP/M 2.2, Grant's CBIOS 2.0 | CP/M 3, Garry Lancaster's BIOS v0.97 |
| Console | VGA/ANSI terminal | Zenith Z-19, 24×80 |
| Memory | flat 64K | banked, port 1FFDh, "AllRam" mode |
| Storage | 128MB SD image, 16 logical drives | `.p3d` disk images |
| Status | boots, edits, compiles, runs, saves | boots, displays, takes input |

Neither is a polished port. Several parts work for non-obvious reasons, all
documented.

### MultiComp — [MultiComp/](MultiComp/)

Working and usable. Boots, edits, compiles, runs and saves; inserts and deletes
land correctly.

**No floating point**: `REAL` arithmetic compiles but fails at runtime with
"Unimplemented Instruction", because our interpreter is one of the
distribution's non-floating-point builds — a documented build option, not
damage.

**One cosmetic artefact remains**: stepping the cursor horizontally gives
+1, +1, −1, +3 — the net movement correct, the intermediate positions not. It
lives in MultiComp's terminal rather than in this code, and is present in the
earliest working shim. Text also disappears during an insert; that happens on
the Spectrum Next too, so it is the editor's own behaviour and nothing is lost.

**[TERMINAL.md](MultiComp/TERMINAL.md) is the most useful thing here if you own
this machine.** It records four measured faults in MultiComp's terminal — the
`ESC[0K` that homes the cursor, the destructive backspace, the ignored
parameterless forms, the unreliable relative moves — and gives the complete VT52
command set that would replace them. Nearly all of this port's complexity exists
to work around those four things.

Most of the development went on a single bug. MultiComp's `ESC[0K` erases to end
of line correctly — and then silently moves the cursor to home. Every editor
redraw following an erase therefore landed on row 1. It was invisible to
inspection because the erase *worked*; it was found by issuing the sequence and
then writing one character with no positioning, so that where the character
landed was the answer.

### Spectrum Next — [Spectrum-Next/](Spectrum-Next/)

Boots cleanly, displays correctly, and takes keyboard input. Two problems
dominated, and neither was where the symptoms pointed.

**The interrupt vector.** CP/M 3 on the Next runs in IM 2 with its vector table
at `0900h` — inside the TPA — and the interpreter loads straight over it. With
interrupts enabled the CPU fetched a vector out of p-code; with them disabled,
anything inside the BIOS that re-enabled them did the same. This presented as
`Exec err #6`, a divide-by-zero, which sent us hunting through disk geometry for
a long time. The fix is a uniform 257-byte vector table above TOPRAM pointing at
an EI/RETI stub, so an interrupt is harmless wherever it is enabled.

**The keyboard.** The BIOS fills its key buffer from the NextZXOS interrupt
chain, and that chain cannot run once the interpreter owns low memory — proved
directly by `Spectrum-Next/Diag/SECBOOT_NEXT_v14DIAG.ASM`, which chains the vector to CP/M's own
handler and prints stars in a loop: exactly one star appears. The clue that
solved it was that **a PS/2 keyboard failed identically**. On the Next the FPGA
merges PS/2 into the ordinary Spectrum key matrix, so both keyboards arrive by
the same route — meaning the fault was never in either hardware path, and the
matrix must still be readable. The shim now polls it directly with
`IN A,(0FEh)`, bypassing the BIOS for input entirely.

## The three stages

Both ports use the same structure.

| stage | runs at | what it does |
|---|---|---|
| Primary bootstrap | 0100h, the CP/M TPA | a normal `.COM`; loads the secondary stage, checks a signature byte, builds the p-System's parameter block, jumps |
| Secondary bootstrap | 8200h | relocates the shim above the p-System's memory ceiling, finds `SYSTEM.INTERP` in the volume directory, loads it, hands over |
| SBIOS shim | above TOPRAM | stands in as the p-System's SBIOS for the rest of the session |

## Current builds

| | MultiComp | Next |
|---|---|---|
| Primary | `PASBOOT_MULTICOMP_Z80_v16.ASM` (354) | `PASBOOT_NEXT_v9.ASM` (376) |
| Secondary | `SECBOOT_MULTICOMP_v21.ASM` (517) | `SECBOOT_NEXT_v18.ASM` (540) |
| Shim | `SHIM_MULTICOMP_v29.ASM` (973) | `SHIM_NEXT_v18.ASM` (453) |

Size limits are tight and were hit repeatedly. On MultiComp the secondary stage
and the shim have 1024 bytes each. On the Next the two together share 1024 bytes
— currently 544 and 480 — because the p-System reserves only blocks 0 and 1 for
a bootstrap and block 2 is the directory.

**The `ORG` addresses matter** and must not be changed independently. The shim
is a separate file because its jump table is absolute: it must be assembled at
the address it will finally run at.

## Why a shim is needed

A CP/M BIOS and a p-System SBIOS share a jump table layout and disagree on the
details. Every disagreement below was found as a failure on hardware:

- `SELDSK` returns HL=0 for **success** in the p-System, and a DPH pointer for
  success in CP/M — the conventions are inverted
- `SETTRK`/`SETSEC` take 8-bit values in C alone; both CBIOSes read the full BC
- the p-System numbers sectors from 1, CP/M from 0
- the p-System's SBIOS entries are CP/M's offsets shifted by three, because the
  address handed over is the BIOS base **+3**

and then the machine-specific ones:

- *MultiComp*: the interpreter loads at 0000h and destroys `iobyte` at 0003h,
  which Grant's console routines depend on, so the shim drives the ACIA directly.
  MISCINFO cannot express ANSI escape sequences, so the shim rewrites VT52 to
  ANSI in flight.
- *Next*: the BIOS's disk entries dispatch into the system bank without paging
  it in — their normal caller is the banked BDOS — so `READ` and `WRITE` must go
  through the BIOS's own banking wrapper. The console needs no translation at
  all, the Z-19 being exactly what MISCINFO was designed to describe.

## Keyboards

**MultiComp.** p-System IV.0 cannot parse incoming escape sequences, so arrow
keys are not possible. Movement is bound WordStar-style: Ctrl-E/X for up/down,
Ctrl-S/D for left/right, Ctrl-C to accept, Ctrl-[ for ESC.

**Next.** The shim reads the key matrix itself, so the BIOS's own mappings do
not apply. Letters produce upper case. CAPS SHIFT + a letter gives its control
code, CAPS+SPACE is ESC, CAPS+0 is backspace, and SYMBOL SHIFT gives punctuation
following the Spectrum's printed legends where they exist. There is no
auto-repeat: without an interrupt there is no timebase to measure a repeat delay
against.

## Two things worth reading even if you have neither machine

**[MultiComp/DIAGNOSTICS.md](MultiComp/DIAGNOSTICS.md)** — how to find a bug on
hardware with no debugger, when the only output channel is the thing that is
broken.

**[Spectrum-Next/STATUS.md](Spectrum-Next/STATUS.md)** — includes the diagnostic
lesson from that port: three shim builds differing only in instrumentation
produced three different failures, each repeatable on its own. That pattern was
the real evidence, and it pointed at a race rather than any parameter. Adding
instrumentation was itself perturbing the system, so the measurements became
less trustworthy the more of them there were. The way out was to make the
machine deterministic first and only then debug it.

## Credits

- **Grant Searle** — MultiComp and its CP/M 2.2 CBIOS
- **Garry Lancaster** — the ZX Spectrum Next CP/M BIOS and NextZXOS
- **Udo Munk** — z80pack's UCSD p-System IV.0 port; its bootstrap was the
  reference for the parameter-block convention and the entry-point offset, and
  the ESC-insertion trick originates there
- **Wayne Warthen** — [RomWBW](https://github.com/wwarthen/RomWBW), whose
  p-System port supplied the ANSI GOTOXY and confirmed the console approach
- **SofTech Microsystems / UCSD** — the p-System itself
- The **[SpecNext wiki](https://wiki.specnext.dev/)**, whose memory map page
  confirmed the banking analysis

## What is in this repository

```
MultiComp/          the three production sources, NOTES.md, DIAGNOSTICS.md
MultiComp/Diag/     diagnostic builds, each written to answer one question
MultiComp/build/    assembled binaries, so no assembler is needed to install
Spectrum-Next/      as above, plus STATUS.md
docs/               SPECTRUM_NEXT_SCOPING.md, the pre-port survey
tools/z80dis.py     the Z80 disassembler written for this work
```

The `Diag/` builds are kept deliberately. Each was instrumented to answer one
specific question on hardware, and several headers explain a wrong turn in
detail. With no debugger and no emulator, they *are* the debugging method, and
they are the part most likely to be useful to someone porting to a third
machine.

## Licence and third-party material

**The assembly sources, documentation and tools in this repository are free to
use.**

The rest is other people's work, and is theirs:

| What | Whose |
|---|---|
| UCSD p-System IV.0, Adaptable Z80 distribution | SofTech Microsystems / UCSD |
| MultiComp and its CP/M 2.2 CBIOS (`cbios128.asm`) | Grant Searle |
| ZX Spectrum Next CP/M BIOS and NextZXOS | Garry Lancaster |
| CP/M 3 and its manuals | Digital Research / Caldera |

One explicit condition worth stating plainly: **Grant Searle's CBIOS is
non-commercial use only.**

## Ready-to-run images

Working disk images are attached to the [releases](../../releases) — a bootable
image for each machine, with the boot chain installed and a p-System volume in
place. That is the quickest way to see either port running.

The sources here are enough to rebuild them from scratch instead: both
`MultiComp/NOTES.md` and `Spectrum-Next/STATUS.md` document the volume layout
and the exact offsets each piece is written to.
