# MultiComp's terminal: what it does, and what it should do

Everything below was measured on hardware, mostly by probes that wrote a single
character and observed where it landed. None of it is inferred from source.

It is written for one purpose: if MultiComp's terminal is ever reimplemented in
the FPGA core, this is what needs fixing and what to replace it with.

## The four faults

**1. `ESC[0K` erases correctly — and then homes the cursor.**

Found by the `SECBOOT_MULTICOMP_v30` probe: issue the erase at row 3 column 5,
then write a single `@` with no positioning. The `@` appeared at row 1 column 1.

This is the fault that dominated the whole port. Every editor redraw following
an erase landed on row 1, which presented as text one row too high, menus drawn
over text, and text vanishing on return. It was invisible to inspection because
the erase itself *works*.

**2. Backspace is destructive.**

The editor emits raw `08h` for cursor-left — confirmed in the `v22DIAG` capture,
which showed `^H^H^H` when three lefts were pressed — and it erases using the
backspace-space-backspace idiom. On a terminal whose backspace merely moves,
that erases exactly one character. On MultiComp it erases on the way in as well,
so every left-move eats a character and every erase happens twice.

**3. Parameterless forms are ignored.**

```
ESC [ H     ignored        ESC [ 1 ; 1 H   works
ESC [ K     ignored        ESC [ 0 K       works
ESC [ J     ignored        ESC [ 0 J       works
ESC [ 2 J   ignored
```

Explicit parameters are required on everything. Any software emitting the
standard short forms — which is most software — silently does nothing.

**4. `ESC[1C` and `ESC[1D` are unreliable.**

Two probes disagreed. The v9 series found cursor-right unimplemented, "the
cursor drifts by the sequence length". The v24 probe found it working, and the
earlier reading was traced to a garbled screen. `ESC[1D` was never satisfactorily
resolved: the marker landed to the *right* of where it started.

A residual artefact remains in the editor to this day: stepping the cursor
horizontally gives +1, +1, −1, +3 — the net movement correct, the intermediate
positions not. It is present in the earliest working shim, so it is not a
regression from anything in this repository.

## What this cost

`SHIM_MULTICOMP_v29.ASM` is 973 bytes and the great majority of it is console
workarounds: a VT52-to-ANSI translator, cursor tracking maintained solely so
that an absolute position can be re-issued after every erase to undo fault 1,
and fixed substitutions to guarantee explicit parameters for fault 3.

By comparison, `SHIM_NEXT_v18.ASM` is 453 bytes including a complete keyboard
matrix scanner, and does **no console translation at all** — because the
Spectrum Next's terminal is a Zenith Z-19 and UCSD's `SYSTEM.MISCINFO` was
designed to describe exactly that.

## What to implement instead: VT52

VT52 is far simpler than ANSI because **nothing takes parameters**. There is no
digit accumulation, no `;` separator, and no ambiguity between the
parameterless and parameterised forms — which is precisely where the current
terminal goes wrong.

The complete set UCSD needs:

| sequence | meaning |
|---|---|
| `ESC A` | cursor up |
| `ESC B` | cursor down |
| `ESC C` | cursor right |
| `ESC D` | cursor left |
| `ESC H` | home |
| `ESC I` | reverse line feed |
| `ESC J` | erase to end of screen |
| `ESC K` | erase to end of line |
| `ESC Y` *r* *c* | direct cursor address; both bytes biased by +32, so row 0 column 0 is `ESC Y` space space |

Nine sequences, one of which takes two literal bytes. Add `ESC E` (clear and
home) for Z-19 compatibility if convenient.

Three behaviours matter as much as the sequences:

- **backspace moves, it does not erase**
- **erasing does not move the cursor**
- **line feed moves down one row and preserves the column**

## What it would buy

- The shim's console layer disappears. MultiComp's shim becomes the Next's shim
  with CP/M 2.2 disk conventions — the two ports become one design instead of
  two sets of workarounds.
- The stock `SYSTEM.PASCAL` works. Its GOTOXY positions the cursor by homing and
  stepping right, which is why swapping it in over the ANSI build made things
  worse; with a real `ESC Y` it would address the cursor directly.
- Roughly 700 bytes of shim freed.
- **Most CP/M software benefits, not just UCSD.** VT52/H19/Z19 is among the most
  widely supported terminal types in CP/M software — WordStar, Turbo Pascal and
  dBASE all ship VT52 profiles.

Worth keeping the present behaviour reachable behind a mode switch while
testing, so existing setups that depend on today's quirks are not broken.

And if the core is open anyway: fault 1 is a one-line bug and worth killing
whichever route is taken.
