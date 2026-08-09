# MultiComp's ANSI terminal: located faults and proposed fixes

**Status: fixed and verified.** All fixes below were applied to
`Components/TERMINAL/SBCTextDisplayRGB.vhd` in the MultiComp MiSTer core
(a separate repository from this one —
[MiSTer-devel/MultiComp_MiSTer](https://github.com/MiSTer-devel/MultiComp_MiSTer))
and confirmed present by direct comparison against the file. The editor
issues this port worked around appear resolved on hardware, with further
testing ongoing.

A source-level follow-up to [TERMINAL.md](TERMINAL.md), which recorded four
faults measured on hardware. This document traces them to the VHDL and finds
that **two of the four are small omissions with one- and two-line fixes**, one
was a misdiagnosis on my part, and one is not visible in the source at all.

All references are to:

```
MultiComp_MiSTer/Components/TERMINAL/SBCTextDisplayRGB.vhd
```

Line numbers are from the version read on 2026-08-09. Relevant constants:

```vhdl
constant VERT_CHARS      : integer := 25;   -- line 26
constant HORIZ_CHARS     : integer := 80;   -- line 27
constant HORIZ_CHAR_MAX  : integer := HORIZ_CHARS-1;   -- 79
constant VERT_CHAR_MAX   : integer := VERT_CHARS-1;    -- 24
```

**Caveat before acting on any of this.** Fault 3 below suggests the synthesised
core may not match this source. Confirm the built bitstream comes from this
revision before concluding anything from the absence of a bug here.

---

## Fault 1 — `ESC[K` homes the cursor

**Confirmed. Cause found. Two lines.**

This is the fault that dominated the entire port: every editor redraw following
an erase landed on row 1, presenting as text one row too high, menus drawn over
text, and text vanishing on return.

### The mechanism

The terminal erases a line by entering the `clearLine` state, which walks the
cursor to the end of the line writing spaces, then hands to `clearL2`
(lines 1116–1128) to finish:

```vhdl
when clearL2 =>
    dispWR <= '0';
    if (cursorHoriz<HORIZ_CHAR_MAX) then
        cursorHoriz<=cursorHoriz+1;
        dispState <= clearLine;
    else
        cursorHoriz<=cursorHorizRestore;     -- restores from these
        cursorVert<=cursorVertRestore;       -- two registers
        dispState<=idle;
    end if;
```

So `clearLine` is a subroutine whose caller is expected to have deposited the
return position in `cursorHorizRestore` / `cursorVertRestore` first.

Every caller does this — **except `ESC[K`** (line 869):

```vhdl
elsif paramCount=1 and dispByteLatch=x"4B" and param1=0 then -- ESC[K - erase EOL
    dispState <= clearLine;
    paramCount<=0;
```

The restore registers are never written, so the cursor is restored to whatever
a *previous, unrelated* operation left in them.

### Why it looked like "home"

Two operations set the restore registers to 0,0:

- `ESC[2J` — clear screen, line 892
- form feed (0Ch) in `dispWrite`, line 1078

The editor clears the screen when it starts. From that moment every `ESC[K`
restores to 0,0. Hence the probe result: erase at row 3 column 5, write one `@`
with no positioning, and the `@` appears at row 1 column 1.

The staleness also explains why the behaviour never looked quite consistent
between sessions. It isn't a fixed destination — it is whatever the last
scroll, line feed at the bottom of the screen, or `ESC[0J` happened to leave
behind. Those all set the registers legitimately, so between clear-screens the
"home" position drifts.

### The fix

```vhdl
elsif paramCount=1 and dispByteLatch=x"4B" and param1=0 then -- ESC[K - erase EOL
    cursorHorizRestore <= cursorHoriz;      -- ADD
    cursorVertRestore  <= cursorVert;       -- ADD
    dispState <= clearLine;
    paramCount<=0;
```

**Applied as specified**, verbatim, at lines 870–871 of the current file.

For comparison, the adjacent `ESC[0J` handler (line 899) already does exactly
this:

```vhdl
elsif paramCount=1 and param1=0 and dispByteLatch=x"4A" then -- ESC[0J
    cursorVertRestore <= cursorVert;
    cursorHorizRestore <= cursorHoriz;
    dispState <= clearScreen;
    paramCount<=0;
```

which is why erase-to-end-of-screen always behaved correctly and erase-to-end-of-line
did not.

---

## Fault 2 — backspace is destructive

**Confirmed. One line.**

In `dispWrite`, line 1083:

```vhdl
elsif dispCharWRData=8 or dispCharWRData=127 then
    if cursorHoriz>0 then
        cursorHoriz <= cursorHoriz-1;
    elsif cursorHoriz=0 and cursorVert>0 then
        cursorHoriz <=HORIZ_CHAR_MAX;
        cursorVert <= cursorVert-1;
    end if;
    dispState<=clearChar;
```

`clearChar` (line 1130) writes a space at the new position. So backspace moves
left *and* erases.

This is what made the editor's cursor-left eat a character, and made its
backspace-space-backspace erase idiom destroy two characters instead of one.
It is also why `SHIM_MULTICOMP_v29` has to intercept 08h and never pass it
through.

### The fix

```vhdl
elsif dispCharWRData=8 or dispCharWRData=127 then
    ...
    dispState<=idle;                        -- was: clearChar
```

If DEL should keep erasing, split the two cases — 08h to `idle`, 127 to
`clearChar`. Erasing on DEL is defensible; erasing on BS is not, and no
terminal standard asks for it.

Note also that backspace at column 0 wraps to the end of the previous line.
That is unusual and arguably wrong, but it is a separate decision from the
erase and nothing here depends on it.

**Applied, and taken one step further than specified.** The cases are split
as suggested — 08h now goes to `idle` (move only), 127 to `clearChar` (move
and erase) — but 08h also clamps at column 0 instead of wrapping to the
previous line:

```vhdl
elsif dispCharWRData=8 then -- backspace - move only, no erase, clamp at column 0
    if cursorHoriz>0 then
        cursorHoriz <= cursorHoriz-1;
    end if;
    dispState<=idle;
elsif dispCharWRData=127 then -- DEL - move and erase
    if cursorHoriz>0 then
        cursorHoriz <= cursorHoriz-1;
    elsif cursorHoriz=0 and cursorVert>0 then
        cursorHoriz <=HORIZ_CHAR_MAX;
        cursorVert <= cursorVert-1;
    end if;
    dispState<=clearChar;
```

So BS at column 0 now does nothing, rather than wrapping to the end of the
previous line; DEL keeps the old wrap-and-erase behaviour. This resolves the
"separate decision" flagged above in BS's favour — reasonable, since the
editor's own backspace idiom (08h, space, 08h) has no use for line-wrap.

---

## Fault 3 — parameterless forms ignored

**Retracted. The source contradicts the measurement.**

`TERMINAL.md` records that `ESC[H`, `ESC[K`, `ESC[J` and `ESC[2J` are ignored
and only the explicitly parameterised forms work. The source does not support
this.

After `ESC[` the parser sets `paramCount=1` and leaves `param1=0`. The guards
are written as `paramCount=1 and ... and param1=0`, so:

| sequence | parser state at the final byte | matches |
|---|---|---|
| `ESC[K` | paramCount=1, param1=0 | yes — same branch as `ESC[0K` |
| `ESC[0K` | paramCount=1, param1=0 | yes — *identical state* |
| `ESC[H` | paramCount=1, param1=0 | yes, line 865 |
| `ESC[J` | paramCount=1, param1=0 | yes, line 899 |
| `ESC[2J` | paramCount=1, param1=2 | yes, line 892 |

`ESC[K` and `ESC[0K` are indistinguishable by the time the terminating byte
arrives. They cannot behave differently.

The cursor-movement handlers go further and explicitly implement the default:

```vhdl
if param1=0 and cursorHoriz<HORIZ_CHAR_MAX then -- no param to default to 1
    cursorHoriz<=cursorHoriz+1;
```

So the parameterless forms were deliberately supported.

**What probably happened.** Those probes ran while fault 1 was actively
corrupting the display. "Nothing happened" was read off a screen that was
already wrong for a different reason, and the wrong conclusion was drawn. The
shim's fixed substitutions guaranteeing explicit parameters are, on this
reading, unnecessary — though harmless, since both forms take the same path.

**Or** the synthesised core predates this source. That possibility has to be
eliminated before the shim's workarounds are removed.

---

## Fault 4 — `ESC[1C` / `ESC[1D` unreliable

**Not explained by this source.**

The handlers (lines 1019–1035) look correct, including bounds:

```vhdl
elsif paramCount=1 and dispByteLatch=x"43" then -- ESC[{param1}C - Cursor forward
    if  param1=0 and cursorHoriz<HORIZ_CHAR_MAX then
        cursorHoriz<=cursorHoriz+1;
    elsif (cursorHoriz+param1)<HORIZ_CHAR_MAX then
        cursorHoriz<=cursorHoriz+param1;
    else
        cursorHoriz<=HORIZ_CHAR_MAX;
    end if;
    paramCount<=0;
```

`ESC[1C` from column 5 gives column 6. `ESC[1D` from column 5 gives column 4.
Nothing here produces the observed `+1, +1, −1, +3` stepping.

That leaves three candidates, none yet tested:

1. **The shim's own cursor tracking.** `SHIM_MULTICOMP_v29` maintains a shadow
   position solely to re-issue an absolute address after every erase — a
   workaround for fault 1. If fault 1 is fixed at source, that machinery goes
   away and the wobble may go with it. **This should be tested before any other
   work on fault 4**, because it costs nothing and may dispose of the problem.
2. **The `dispByteWritten` / `dispByteSent` handshake** between the CPU write
   process and the display state machine. A missed or doubled byte would
   present as exactly this kind of net-correct, intermediate-wrong stepping.
3. **The measurement itself.** Fault 4 was contradictory from the start — the
   v9 probes found cursor-right unimplemented, the v24 probe found it working,
   and the discrepancy was traced to a garbled screen. Given fault 3 turned out
   to be an artefact of fault 1, fault 4 deserves re-measuring on a fixed core
   before it is treated as real.

**Update:** with faults 1 and 2 fixed at source, the user reports the editor
issues appear resolved on hardware — consistent with candidate 1 above: the
wobble was most likely downstream of fault 1, produced by the shim's own
workaround chasing a moving target, rather than a bug in the core's cursor
handlers. Testing is ongoing; this document will be updated again if further
use turns up a genuine residual case.

---

## Minor: latent out-of-range in `ESC[{row};{col}H`

Line 1037. `cursorHoriz` is declared `integer range 0 to HORIZ_CHAR_MAX`, and:

```vhdl
if param2<0 then
    cursorHoriz <= 0;
elsif param2>HORIZ_CHARS then
    cursorHoriz <= HORIZ_CHARS-1;
else
    cursorHoriz <= param2-1;
end if;
```

`param2` is accumulated from digits and can never be negative, so the first
branch is dead. `ESC[5;0H` therefore reaches `param2-1` = −1, which is outside
the signal's range. Not currently hit — the shim always emits 1-based columns —
but it would be triggered by any other software that emits a zero column, and
the guard was clearly meant to catch it. `param2<1` is the intended test.

**Applied.** The guard now reads `param2<1`.

---

## What this means for the VT52 question

The case for reimplementing the terminal as a VT52 rested largely on the four
faults above. Two of them are three lines of VHDL, one appears not to exist,
and the fourth may be a consequence of the first.

That substantially weakens the argument for a rewrite — but does not eliminate
it. The independent reasons in [TERMINAL.md](TERMINAL.md) still stand:

- the stock `SYSTEM.PASCAL` positions the cursor by homing and stepping right,
  which needs a real `ESC Y`; with it, the shim's console layer disappears
  entirely and the two ports become one design
- VT52/H19/Z19 is among the best-supported terminal types in CP/M software, so
  the benefit extends well beyond UCSD

The sensible order is now clear:

1. Confirm the built core matches this source.
2. Apply the three lines.
3. Re-measure. Specifically: does `+1 +1 −1 +3` survive, and can the shim shed
   its cursor-tracking workaround?
4. Decide on VT52 with that evidence in hand.

Step 2 is an afternoon. Step 4 was always going to be a project.
