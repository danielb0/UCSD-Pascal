# Diagnostic builds

None of these are production. They exist because this port has no emulator: the
only way to learn anything is to put a question on the screen and photograph it.
Several are worth keeping, because the technique they embody solved the problem
where reasoning repeatedly failed.

## The lesson worth keeping

The bug that took two sessions to find was not a sequence that failed. It was
`ESC[0K`, which erases perfectly **and then moves the cursor to home**. No
amount of looking at whether the screen "looked right" would have caught it. It
was found by issuing the sequence and then writing a single character with no
positioning at all, so that where the character landed *was* the answer.

Two rules came out of this:

1. **Test the side effects, not just the effect.** For every sequence, ask both
   "did it do the right thing" and "where did it leave the cursor".
2. **Make the answer unmissable.** Label each row with its own number; use
   markers that cannot be confused. Two rounds were lost to an `H` being read
   as an `A` off a photograph.

## Shim diagnostics — replace the shim, real SECBOOT, system boots

| Build | What it does |
|-------|--------------|
| `SHIM_MULTICOMP_v11DIAG.ASM` | Shows the p-System's **input** stream as text: ESC prints as `~`, NUL as `.`. No translation, no positioning — scrolls like a teletype. Answers "what is the p-System actually sending, and where does the NUL padding fall". |
| `SHIM_MULTICOMP_v14DIAG.ASM` | Shows the shim's **output** stream — v10's full translation with outgoing ESC printed as `~`. Answers "what is MultiComp actually being handed". Built on v10. |
| `SHIM_MULTICOMP_v19DIAG.ASM` | Same idea, built on v18. Use this one; v14DIAG is kept only because its transcript is quoted in NOTES. |
| `SHIM_MULTICOMP_v20ALARM.ASM` | v18 with **normal** positioning and erasing, so the editor is usable, except an unrecognised `ESC x` — normally dropped silently — prints as `!x`. Answers "are we filtering out something the editor needs". Result: no `!` ever appeared, so we are not. |

The output diagnostics have a blind spot worth remembering: they render what
*leaves* the shim, so anything the shim discards is invisible in them by
construction. That is what v20ALARM exists to cover.

## Terminal probes — replace SECBOOT, do NOT boot the p-System

Each paints a labelled screen, waits for a key, then hangs. The p-System is
never loaded, so nothing else can be blamed. **SECBOOT must fit in 1024 bytes**;
two of these were built over the limit and had to be redone.

| Build | Question | Answer obtained |
|-------|----------|-----------------|
| `SECBOOT_MULTICOMP_v22.ASM` | Does a position survive immediately after an erase? | Yes, all four cases. |
| `SECBOOT_MULTICOMP_v23.ASM` | Is `ESC[1B` (cursor down) implemented? Does a bare LF move down? Does a bare CR reset the column? | All yes. LF is a true line feed — the column is preserved, so it is not CR+LF. |
| `SECBOOT_MULTICOMP_v24.ASM` | Are `ESC[nC` and `ESC[nD` implemented? | Right works, including the single-step `ESC[1C`. The earlier "not implemented" finding was wrong. Left misbehaves — use plain BS. |
| `SECBOOT_MULTICOMP_v25.ASM` | Is row addressing off by one? Do the erases erase? | Addressing correct and 1-based; rows 1-10 each showed their own number. Erases appeared to work — but this test never checked the cursor, which is how the real bug slipped through. |
| `SECBOOT_MULTICOMP_v27.ASM` | Replays the exact Edit→Insert banner byte sequence. | Reproduced the fault with no shim and no p-System. First time it was isolated. |
| `SECBOOT_MULTICOMP_v30.ASM` | **The one that found it.** For `ESC[0K`, `ESC[2K` and `ESC[1K` in turn: fill five rows, put the cursor mid-line on row 3, erase, then write a bare `@`. | `ESC[0K` erases correctly but **homes the cursor** — the `@` appeared at row 1 column 1. `ESC[2K` does nothing. `ESC[1K` prints a literal `K`. |

`v30` is the template to copy for any future terminal question: identical setup
repeated per variant, a keypress between screens so a destructive variant cannot
corrupt the next test, and a bare marker to expose the cursor.

## Still unexamined

`ESC M` (reverse line feed, what `ESC I` becomes) has never been tested in any
form. `ESC[0J`'s cursor side-effect is also unmeasured, though v21 restores the
cursor after it regardless, so it is covered either way.
