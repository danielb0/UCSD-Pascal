;==================================================================================
; SECBOOT for the ZX Spectrum Next -- v18 -- ROOM FOR THE KEYBOARD SHIM
;
; The shim assembled to 453 bytes, so the split of the two reserved blocks
; moves again. Final arrangement:
;
;       SECBOOT   8200h .. 8200h+544   (uses 540 -- only 4 spare, do not grow)
;       shim      8200h+544 .. +1024   (480 available, uses 453)
;
; Copied to F000h, 480 bytes reaches F1DFh, still clear of the F200h ceiling.
;
; -- superseded v17 header follows --
;
; SECBOOT for the ZX Spectrum Next -- v17 -- ROOM FOR THE KEYBOARD SHIM
;
; Identical to v16 except for the split of the two reserved blocks. The shim now
; reads the Spectrum key matrix itself and no longer fits in 384 bytes, so:
;
;       SECBOOT   8200h .. 8200h+576   (uses 540)
;       shim      8200h+576 .. +1024   (448 available)
;
; The two blocks are all there is: block 0 and block 1 of the p-System volume
; are reserved for the bootstrap, and block 2 is the directory, so a third
; sector cannot be taken without moving the whole volume.
;
; The disk image must match: SECBOOT at file offset 66048, shim at 66048+576.
;
; -- original v16 header follows --
;
; SECBOOT for the ZX Spectrum Next -- v16 -- ASK THE BIOS TO STOP USING THE
;                                            INTERRUPT CHAIN
;
; v14DIAG proved CP/M's own interrupt handler cannot run once the interpreter
; owns low memory: one star, then nothing. Both the IM 1 route (restoring the
; JP at 0038h) and the IM 2 route (chaining to FE0Ah) died the same way.
;
; The SpecNext wiki explains part of the picture. CP/M runs the Next in
; "special paging mode", which the wiki calls AllRam or CP/M mode -- and in
; that mode the Next MMU is overridden by the AllRam bank table, so a handler
; has very little freedom to page anything in. It also warns outright that with
; ROM paged out and IM 1 selected, "DI is your friend".
;
; But the BIOS API document offers a documented way out that I passed over
; earlier. USERF function 4 sets BIOS features, and bit 7 is "enable
; interrupt-driven NextZXOS devices", default $80. The Next's CP/M devices are
; CRT, LPT and XDEV -- the terminal is one of them. So that bit may well be the
; switch between an interrupt-driven console and a polled one, which is exactly
; the choice we need.
;
; So: call USERF with C=4, A=0 before doing anything else, while CP/M is still
; entirely intact. If the BIOS then polls the keyboard in CONST, the keyboard
; works with interrupts merely absorbed, as they are here.
;
;       USERF = (0001h) + 3*(30-1) = (0001h) + 87
;
; It self-banks through the same wrapper as everything else, so it can be
; called directly. A=$FF back means the function failed or is unsupported,
; which older BIOS builds may well do -- harmless either way, we simply carry
; on with no keyboard as before.
;
; The IM 2 table and its EI/RETI stub stay exactly as in v15. They are what
; makes the machine deterministic, and that is not up for negotiation.
;
; -- original v15 header follows --
;
; SECBOOT for the ZX Spectrum Next -- v15 -- PRODUCTION, MARKERS OUT
;
; Functionally identical to v13, which boots. The progress markers 5..C and the
; MARK routine that printed them are removed, so the boot is silent.
;
; v14DIAG settled the keyboard question. It loaded the interpreter normally,
; chained the IM 2 vector to CP/M's own handler at FE0Ah, enabled interrupts
; and printed stars in a loop. Exactly one star appeared. So the handler is
; entered on the first tick and never returns: it cannot run once the
; interpreter owns low memory.
;
; That is why the vector here points at EI/RETI instead. The 50Hz interrupt is
; acknowledged and discarded, which keeps the machine deterministic but leaves
; nothing scanning the keyboard, so CONST truthfully reports no key.
;
; Making the keyboard work means making CP/M's handler survivable. The obvious
; approach -- save CP/M's page zero at boot and swap it in around each ISR call
; -- is complicated by the BIOS's own banking: the wrapper switches to the
; system bank without disabling interrupts, so the handler can be entered under
; either memory configuration, and in the system configuration neither CP/M's
; page zero nor the interpreter's is at 0000h. Any fix has to cope with both.
;
; -- original v13 header follows --
;
; SECBOOT for the ZX Spectrum Next -- v13 -- INTERRUPTS ABSORBED, NOT SERVED
;
; v12 built a correct IM 2 table and chained it to CP/M's own handler at FE0Ah.
; It hung the instant control reached the interpreter -- before the first
; SELDSK, i.e. within one interrupt period of the handover.
;
; The vectoring was right; the table is uniform so every data-bus value leads to
; the same stub. What failed is CP/M's handler itself. It lives in the common
; bank and survives the load, but it evidently relies on page-zero or TPA-bank
; state that is now p-code. Entered once, it never came back.
;
; So the keyboard is not reachable this way, and chasing it further is not worth
; the rounds. What IS worth keeping is the table, pointing at a handler that
; does nothing:
;
;       EE00h..EF00h   257 bytes, every one EFh
;       EFEFh          EI / RETI
;       I = EEh, IM 2, EI
;
; That absorbs the 50Hz interrupt harmlessly for ever. It sounds like an
; elaborate way to achieve DI, and it is not: with DI, anything inside the BIOS
; that re-enables interrupts -- and the evidence of five runs says something
; does -- immediately turns a working machine into a crashing one, because the
; vector points into interpreter data. That is what produced three different
; failures from three shim builds that differed only in instrumentation.
;
; With a safe vector installed, an EI anywhere in the BIOS is a non-event. The
; machine becomes deterministic, which is the precondition for debugging the
; actual boot failure rather than chasing ghosts.
;
; The cost is the keyboard, which does not work anyway. Exec err #6 is what
; stands between here and a booting p-System, and that is a geometry problem.
;
; Reading CP/M's handler address is no longer needed, so that capture goes too.
;
; -- original v12 header follows --
;
; SECBOOT for the ZX Spectrum Next -- v12 -- OUR OWN IM 2 VECTOR TABLE
;
; v11 answered it: I = 09, and the word at (I<<8)|FFh = FE0Ah -- an address in
; the common bank, next door to the BIOS variables at FE22h/FE24h.
;
; So CP/M 3 on the Next runs in IM 2. Its vector table sits at 0900h..09FFh,
; INSIDE THE TPA, and its handler is at FE0Ah. The interpreter loads over
; 0000h..35FFh and destroys that table on every boot, so the moment interrupts
; were enabled the CPU fetched a vector out of interpreter data and jumped into
; nowhere. Four dots, then silence.
;
; The JP at 0038h was vestigial. Poking it back was damage to the p-code
; dispatch table for no benefit, so that is removed along with the diagnostics
; that earned their keep and are now just costing bytes.
;
; What replaces it: our own vector table, above TOPRAM where the interpreter
; can never reach.
;
;       EE00h..EF00h   257 bytes, every one EFh
;       EFEFh          JP FE0Ah   (three bytes: the address EFEFh is exactly
;                                  what a uniform table of EFh points at)
;       I = EEh, IM 2, EI
;
; The table is uniform so it does not matter what the data bus supplies during
; the interrupt acknowledge cycle -- every entry leads to the same stub. The
; stub's target is read from the machine at boot rather than hard-coded, so a
; different BIOS build with a different handler still works.
;
; NEWTOP therefore drops from F000h to EE00h, putting TOPRAM at EB80h after the
; carve. That costs the p-System about 4.5K, leaving roughly 60,000 bytes --
; still comfortably more than MultiComp's 57,600.
;
; Whether CP/M's handler can actually run with the interpreter occupying low
; memory is the remaining unknown. It lives in the common bank so it survives,
; but if it touches page-zero scratch it will misbehave. That is now a question
; we can ask, which it was not before.
;
; -- original v11 header follows --
;
; SECBOOT for the ZX Spectrum Next -- v11 -- IM 1 OR IM 2?
;
; v10 read back  II=09  VV=C3  AAAA=F8AA.
;
; So 0038h genuinely held a JP, CP/M's ISR is at F8AAh in the common bank where
; the interpreter can never reach it, and the vector was restored correctly.
; And it still hung four dots in. The simple story is dead.
;
; What is left is the odd one: I = 09h. The I register does nothing in IM 1, so
; there is no reason for it to hold a specific low value -- unless CP/M is in
; IM 2, in which case its vector table is at 0900h..09FFh. That is inside the
; TPA, which the interpreter overwrites wholesale. Enabling interrupts would
; then fetch a vector out of interpreter data and jump into nowhere, which is
; exactly what we see, and the 0038h poke would be beside the point.
;
; The JP at 0038h would then be vestigial -- left over from before CP/M
; switched modes, or simply belt and braces.
;
; So read the word at (I<<8)|FFh while page zero is still CP/M's, and print it
; in place of VV and AAAA, which are now known:
;
;       an address in the common bank (F8xx, or near F8AAh)
;               CP/M is in IM 2 and that is the real handler. The fix is our
;               own 257-byte table above TOPRAM with a handler chaining to it,
;               and 0038h stops mattering.
;       anything random-looking
;               IM 1 after all, and the fault is that CP/M's ISR cannot run
;               with the interpreter occupying low memory -- a much harder
;               problem, and the point at which running without a keyboard
;               starts to look like the sensible trade.
;
; Same size as v10: the two prints removed pay for the one added.
;
; -- original v10 header follows --
;
; SECBOOT for the ZX Spectrum Next -- v10 -- GIVE THE INTERPRETER AN ISR
;
; Three shim builds differing only in console instrumentation gave three
; different failures -- err 6 with CONST stubbed, err 13 with CONST live, a
; hang with CONST live plus one marker -- each repeatable on its own. That is
; not a p-System fault; it is the BIOS console behaving undefinedly because we
; run with interrupts off and its 50Hz ISR never gets to scan the keyboard.
;
; The obstacle has always been that the interpreter's p-code dispatch table
; occupies 0000h..01FFh, which includes 0038h, the IM 1 vector. Turning
; interrupts on without a handler there sends the CPU into "SBC A,B / INC B"
; fifty times a second.
;
; But 0038h only matters in IM 1. So this build measures first and acts second.
; Immediately after the DI, with page zero still CP/M's, it saves:
;
;       I           the interrupt vector page. A high value means IM 2 and a
;                   table in CP/M's own memory, in which case 0038h is
;                   irrelevant and interrupts can simply be enabled.
;       (0038h)     C3 means CP/M put a JP there, i.e. IM 1
;       (0039h)     and this is CP/M's real ISR address
;
; and prints them after marker 5 as II VV AAAA.
;
; Then, once the interpreter is loaded and page zero belongs to it, it puts
; CP/M's vector BACK at 0038h and EIs before handing over. That costs three
; bytes of the dispatch table -- two opcodes' entries -- which is a real risk,
; but a bounded and testable one. The alternative is a 257-byte IM 2 table and
; about 5K of p-System memory.
;
; If (0038h) does not read C3 the poke is skipped and we stay with DI, because
; then CP/M's handler is inline code rather than a jump, which is a different
; job.
;
; -- original v9 header follows --
;
; SECBOOT for the ZX Spectrum Next -- v9 -- SHIM AND TOPRAM MOVED UP
;
; Paired with PASBOOT v8. The shim moves from BE00h to F000h and the carve
; follows it up, because C000h-F1FFh turned out to be ordinary TPA RAM rather
; than forbidden common memory. See the PASBOOT v8 header for the reasoning.
;
; New layout:
;
;       ED80h..EF7Fh   sector buffer (512, MAXBYTES)  ) carved from
;       EF80h..EFFFh   sector table  (128, MAXSECTORS) ) NEWTOP = F000h
;       F000h..F0FFh   the shim
;       F200h          the TPA ceiling, per CP/M's own 60.5K figure
;
; TOPRAM ends up at ED80h, so the p-System gets about 60,800 bytes against the
; 48,000 it had -- and against MultiComp's 57,600.
;
; A side benefit: F000h is in bank 3, which is common to BOTH memory
; configurations. The shim was at BE00h, in bank 2, which is swapped out
; whenever the BIOS pages in the system bank. That was safe only because the
; wrapper switches to its own stack before doing so; at F000h it is not a
; question at all.
;
; -- original v8 header follows --
;
; SECBOOT for the ZX Spectrum Next -- v8 -- INTERRUPTS, PROPERLY THIS TIME
;
; v7's single DI at entry is not enough, and the evidence is that the same
; binaries keep behaving differently between runs:
;
;   SECBOOT v5 + shim v3   steady border, no SBIOS calls
;   SECBOOT v6 + shim v4   FLASHING border, same handoff
;   SECBOOT v7 + shim v5   "ssss"      -- four SELDSK
;   SECBOOT v7 + shim v6   "sFsF..."   -- nine SELDSK
;   SECBOOT v7 + shim v7   nothing at all, frozen at C
;
; Deterministic code does not do that. The only thing on this machine that
; varies run to run is the 50Hz interrupt.
;
; DI is set once, at entry. But every marker goes through the BIOS CONOUT,
; which dispatches into the system bank -- and console drivers routinely EI on
; the way out. If CONOUT does, then the FIRST marker we print switches
; interrupts back on, and everything after it is racing the ULA again with
; 0038h full of the interpreter's pointer table.
;
; That fits every observation above, including why more instrumentation made
; things worse rather than clearer: each extra marker is another chance to have
; interrupts turned back on underneath us.
;
; So DI is now re-asserted where it can be undone:
;
;   * at the end of MARK, after CONOUT has returned
;   * immediately before the jump into the interpreter
;
; The shim needs the same treatment in SHMARK -- it prints while the
; interpreter is running, which is the worst possible time to hand interrupts
; back.
;
; -- original v7 header follows --
;
; SECBOOT for the ZX Spectrum Next -- v7 -- INTERRUPTS
;
; v6 proved the two things that were still assumptions. After marker A it
; printed 3BC3 C324 -- the words at 0200h and 0202h, little-endian for
; C3 3B 24 C3, "JP 243Bh" -- so SYSTEM.INTERP really is in memory, intact, and
; entered at the right address. After marker B it printed BB80 BD80 BB80, so
; the carve is right too. Both dumps are removed again here; they have done
; their job and the space is worth more.
;
; What v6 also showed was a FLASHING border where v5 gave a steady one, from
; the same handoff. Nothing in our parameters could do that. The only periodic
; thing on this machine is the 50Hz interrupt, and in IM 1 it vectors through
; 0038h -- which the interpreter load overwrites. The bytes there are part of a
; pointer table:
;
;       0038: 98 04 98 04 98 04 98 04    ->  SBC A,B / INC B / SBC A,B / ...
;
; so every interrupt executes its way forward through the table and off into
; whatever follows, fifty times a second, until it hits an OUT to an even port
; and paints the border. Worse, each one pushes a return address onto our stack
; on the way in and never comes back for it, so a single interrupt is enough to
; wreck the interpreter regardless of the border.
;
; That is also why the same binaries gave a steady border one run and a
; flashing one the next: where the interrupt lands is a matter of timing, not
; of anything we control.
;
; MultiComp never showed this because Grant's design has no interrupt source.
; Here CP/M 3 hands us the machine with interrupts enabled, and we then destroy
; the vector they point at.
;
; So: DI on entry, before the load. There is no EI anywhere in the interpreter's
; cold start (checked), so once off they stay off. It goes at ENTRY rather than
; just before the handover because page zero is destroyed DURING the load, not
; after it -- the window has been open all along.
;
; If console input later turns out to need interrupts, the answer is not to
; re-enable them but to give the p-System a real interrupt handler, which is a
; separate piece of work.
;
; -- original v5 header follows --
;
; SECBOOT for the ZX Spectrum Next -- v5 -- THE INTERPRETER'S STACK
;
; v4 reached marker C and entered the interpreter. The border went purple --
; nothing in this code touches port FEh, so that was the ULA being hit by wild
; OUTs, i.e. the interpreter running away.
;
; The cause was an omission of mine when porting from MultiComp. That version
; ends the carve with:
;
;       LD   A,L
;       AND  0FEh
;       LD   L,A
;       LD   (TOPRAMV),HL
;       LD   SP,HL
;
; and v1-v4 here had neither the alignment nor, far more importantly, the
; LD SP,HL. So the thirteen words were pushed on PASBOOT's stack at BE00h and
; the interpreter inherited that as ITS stack. But the carve had just placed:
;
;       BB80h   sector buffer (512 bytes, MAXBYTES)
;       BD80h   sector table  (128 bytes, MAXSECTORS)
;       BE00h   the shim
;
; which puts the handoff words at BDE6h..BDFFh -- inside the sector table --
; with the interpreter's stack then growing down through the table and into the
; buffer. It overwrites its own disk buffers with stack the moment it starts
; work, and vice versa.
;
; SP must be the FINAL TOPRAM, below both carved areas. That is the whole point
; of computing TOPRAM last.
;
; The AND 0FEh is a no-op with these numbers (BE00h - 128 - 512 = BB80h, already
; even) but it is in the original for a reason and costs three bytes.
;
; -- original v4 header follows --
;
; SECBOOT for the ZX Spectrum Next -- v4 -- THE BIOS ADDRESS MUST NOT COME
; FROM PAGE ZERO
;
; v3 reached marker 9: shim relocated, directory read, SYSTEM.INTERP found. It
; died during the load itself.
;
; SYSTEM.INTERP is 27 blocks, 13824 bytes, and loads to 0000h..35FFh. The first
; block of that load overwrites 0000h..01FFh -- including the two bytes at
; 0001h that hold the BIOS address. READ and BIOSJMP were still fetching it
; with LD HL,(BOOT+1) on every single call, so the second block's SELDSK read
; two bytes of freshly-loaded interpreter, treated them as an address, and
; jumped there.
;
; MARK already avoided this: it uses SBIOSADDRV at 9002h, which is why markers
; 5 through 9 all appeared. The fix is simply to be consistent -- READ and
; BIOSJMP now read SBIOSADDRV too. The value is identical (wboote, F803h on
; this machine), it just lives somewhere the load cannot reach.
;
; The seed at ENTRY still uses (BOOT+1), which is correct: it runs before
; anything has been loaded, and it is what puts the address in SBIOSADDRV in
; the first place.
;
; The load's extent is worth recording, because it is what makes the rest of
; the layout safe: 35FFh is comfortably below SCRATCH at 9000h, DIRBUF at
; 9800h and SECBOOT's own code at 8200h. Nothing else needs moving.
;
; -- original v3 header follows --
;
; SECBOOT for the ZX Spectrum Next -- v3 -- BANKING WRAPPER + MARKER FIX
;
; PASBOOT v4 reached marker 4: both sectors read, the C5 signature matched, and
; it jumped here. Marker 5 never appeared, for two reasons -- one a fault in the
; instrumentation, one fatal either way.
;
; 1. MARK read the BIOS address from SBIOSADDRV, but marker 5 fires BEFORE the
;    handoff parameters are popped, so it read uninitialised memory at 9002h
;    and jumped into it. Fixed by seeding SBIOSADDRV from (BOOT+1) on entry.
;    The value is the same one PASBOOT pushes, so the later pop is harmless.
;
; 2. READ was called directly, which cannot work: it dispatches to 7C98h, which
;    only exists with the system bank paged in. Same obstacle PASBOOT hit, and
;    the same way round -- go through the BIOS's own banking wrapper.
;
;      wrapper     PRL 01FFh -> base + 00FFh
;      READ entry  PRL 02A5h -> base + 01A5h
;      base = (0001h) - 3
;
; The wrapper saves SP, switches to a stack in common memory, pages in the
; system bank, calls whatever HL points at, pages back and restores SP. It
; preserves the routine's return value in A, so the read status survives.
;
; v1 got as far as PASBOOT's banner and locked up silently. These markers
; continue PASBOOT v2's sequence, so the last character on screen says exactly
; where it stopped:
;
;   5  entered, C5 gate passed
;   6  twelve handoff parameters popped
;   7  shim relocated to BE00h
;   8  directory read (blocks 2..5)
;   9  SYSTEM.INTERP found in the directory
;   A  interpreter loaded to 0000h  <-- page zero and BDOS are gone after this
;   B  TOPRAM forced down, buffers carved
;   C  13 words pushed, about to enter the interpreter
;
; MARK cannot use BDOS, because marker A destroys the vector at 0005h. It calls
; the real BIOS CONOUT directly through the address PASBOOT handed us, which is
; saved in SBIOSADDRV at 9002h and survives the load.
;
; If the last thing seen is C, the interpreter is being entered and refusing to
; run -- which would point at BYTES=512 or the handoff itself, not at the disk.
;
; Secondary bootstrap. Runs at 8200h, loaded there by PASBOOT along with the
; shim image. It relocates the shim above the p-System's memory, loads
; SYSTEM.INTERP to 0000h, carves the sector buffers, and hands over.
;
; Derived from SECBOOT_MULTICOMP_v21.ASM. The sequence is identical; what
; changed is the arithmetic and two things that are simply not needed here.
;
;----------------------------------------------------------------------------------
; DIFFERENCES FROM THE MULTICOMP VERSION
;
; 1. READBLOCK does ONE read, not four. On MultiComp a 512-byte p-System block
;    was four 128-byte CP/M sectors. Here a physical sector IS 512 bytes, so
;    block N maps to exactly one BIOS read.
;
; 2. No iobyte capture. MultiComp's shim had to drive the ACIA directly, because
;    the interpreter overwrites the iobyte at 0003h when it loads at 0000h.
;    Here the shim passes console calls straight to the real BIOS, which keeps
;    its own state in common memory at C000h and up -- untouched by the load.
;
; 3. The shim lives at BE00h, just under the CP/M 3 common area at C000h,
;    rather than at E200h under Grant's CBIOS at E600h.
;
;----------------------------------------------------------------------------------
; MEMORY MAP AFTER HANDOFF
;
;   0000h..35FFh   SYSTEM.INTERP        (owns page zero -- see MultiComp NOTES)
;   3600h..BB7Fh   p-System workspace   about 47K
;   BB80h..BD7Fh   sector buffer  ) carved by this code from NEWTOP = BE00h
;   BD80h..BDFFh   sector table   )
;   BE00h..BFFFh   the shim             above TOPRAM, so it survives
;   C000h..FFFFh   CP/M 3 common area   BIOS, resident BDOS -- must not be touched
;
;----------------------------------------------------------------------------------
; WHERE THIS CODE LIVES ON DISK
;
; PASBOOT loads 1024 bytes -- the p-System volume's reserved blocks 0 and 1 --
; to 8200h. Within that window:
;
;   8200h .. 847Fh   this code            (640 bytes available)
;   8480h .. 85FFh   the shim image       (384 bytes available)
;
; Both limits are hard. The p-System directory starts at block 2, so there is
; no room to grow without moving the secondary stage off the volume entirely.
;==================================================================================

FIRSTBLOCK	EQU	2		;p-System directory starts at block 2
DIRBLOCKS	EQU	4		;directory occupies blocks 2..5
ENTRYSIZE	EQU	26
NAMEOFFSET	EQU	6
NAMEFIELDLEN	EQU	14		;length byte + "SYSTEM.INTERP"
MAXENTRIES	EQU	77

PSYSDRV		EQU	15		;P: = unit 15
BOOTUNIT	EQU	4		;p-System boot unit

SHIMDEST	EQU	0F000h		;where the shim runs (above TOPRAM,
					;below the TPA ceiling near F200h)
SHIMSRC		EQU	8200h+544	;its image slot in the loaded window
SHIMLEN		EQU	480
SHIMREAL	EQU	SHIMDEST+51	;shim's REALBIOS word (0BE33h)
NEWTOP		EQU	IM2TAB		;TOPRAM before the carve -- BELOW the
					;IM 2 table, not just below the shim

DIRBUF		EQU	9800h		;scratch, used only before the handoff
SCRATCH		EQU	9000h

INTERPBASEV	EQU	SCRATCH+0
SBIOSADDRV	EQU	SCRATCH+2
IM2TAB		EQU	0EE00h		;257 bytes, every one IM2BYTE
IM2BYTE		EQU	0EFh
IM2STUB		EQU	0EFEFh		;= IM2BYTE * 0101h -- where a uniform
					;table of IM2BYTE always points
IM2PAGE		EQU	0EEh		;high byte of IM2TAB, goes into I
LOWMEMV		EQU	SCRATCH+4
TOPRAMV		EQU	SCRATCH+6
TRACKSV		EQU	SCRATCH+8
SECTORSV	EQU	SCRATCH+10
BYTESV		EQU	SCRATCH+12
INTERLEAVEV	EQU	SCRATCH+14
FIRSTTRACKV	EQU	SCRATCH+16
SKEWV		EQU	SCRATCH+18
MAXSECTORSV	EQU	SCRATCH+20
MAXBYTESV	EQU	SCRATCH+22
CURBLOCK	EQU	SCRATCH+24
CURDEST		EQU	SCRATCH+26
BLOCKSLEFT	EQU	SCRATCH+28
DESTPTR		EQU	SCRATCH+29
TRACKVAL	EQU	SCRATCH+31
CURSECTOR	EQU	SCRATCH+33
ENTRIESLEFT	EQU	SCRATCH+34
STARTBLOCK	EQU	SCRATCH+35

BOOT		EQU	0000h
BDOS		EQU	0005h
CR		EQU	0Dh
LF		EQU	0Ah
EOM		EQU	'$'
WRBUF		EQU	9

		ORG	8200h

ENTRY:
		PUSH	BC		;*** MUST STAY FIRST *** -- PASBOOT gates
		PUSH	DE		;its jump on this C5 byte. The pushes are
		PUSH	HL		;balanced immediately below.
		POP	HL
		POP	DE
		POP	BC
;
		DI			;the interpreter is about to overwrite the
					;IM 1 vector at 0038h. See the header.
;
		LD	HL,(BOOT+1)	;seed this NOW -- needed before the handoff
		LD	(SBIOSADDRV),HL	;parameters are popped
;
; Ask the BIOS to stop driving its devices from the interrupt chain, while CP/M
; is still completely intact. See the header.
		LD	HL,(BOOT+1)
		LD	BC,87		;3*(30-1): USERF, BIOS function 30
		ADD	HL,BC
		LD	C,4		;function 4: set BIOS features
		XOR	A		;bit 7 clear: no interrupt-driven devices
		CALL	USRCALL
;

;
		POP	HL
		LD	(INTERPBASEV),HL
		POP	HL
		LD	(SBIOSADDRV),HL
		POP	HL
		LD	(LOWMEMV),HL
		POP	HL
		LD	(TOPRAMV),HL
		POP	HL
		LD	(TRACKSV),HL
		POP	HL
		LD	(SECTORSV),HL
		POP	HL
		LD	(BYTESV),HL
		POP	HL
		LD	(INTERLEAVEV),HL
		POP	HL
		LD	(FIRSTTRACKV),HL
		POP	HL
		LD	(SKEWV),HL
		POP	HL
		LD	(MAXSECTORSV),HL
		POP	HL
		LD	(MAXBYTESV),HL
;
;
; --- relocate the shim and tell it where the real BIOS is ---
		LD	HL,SHIMSRC
		LD	DE,SHIMDEST
		LD	BC,SHIMLEN
SHCOPY:
		LD	A,(HL)
		LD	(DE),A
		INC	HL
		INC	DE
		DEC	BC
		LD	A,B
		OR	C
		JP	NZ,SHCOPY
;
		LD	HL,(SBIOSADDRV)
		LD	(SHIMREAL),HL
;
;
; --- read the directory, blocks 2..5 ---
		LD	HL,FIRSTBLOCK
		LD	(CURBLOCK),HL
		LD	HL,DIRBUF
		LD	(CURDEST),HL
		LD	A,DIRBLOCKS
		LD	(BLOCKSLEFT),A
		CALL	READMANY
;
;
; --- find SYSTEM.INTERP ---
		LD	HL,DIRBUF+ENTRYSIZE
		LD	A,MAXENTRIES
		LD	(ENTRIESLEFT),A
SCANLOOP:
		PUSH	HL
		LD	DE,NAMEOFFSET
		ADD	HL,DE
		LD	DE,TARGETNAME
		LD	B,NAMEFIELDLEN
CMPLOOP:
		LD	A,(DE)
		CP	(HL)
		JP	NZ,CMPFAIL
		INC	HL
		INC	DE
		DJNZ	CMPLOOP
		POP	HL
		JP	FOUND
CMPFAIL:
		POP	HL
		LD	DE,ENTRYSIZE
		ADD	HL,DE
		LD	A,(ENTRIESLEFT)
		DEC	A
		LD	(ENTRIESLEFT),A
		JP	NZ,SCANLOOP
		JP	NOTFOUND
;
FOUND:
		LD	E,(HL)
		INC	HL
		LD	D,(HL)		;DE = first_block
		INC	HL
		LD	C,(HL)
		INC	HL
		LD	B,(HL)		;BC = first_after_block
		LD	(STARTBLOCK),DE
		LD	H,B
		LD	L,C
		OR	A
		SBC	HL,DE
		LD	A,L
		LD	(BLOCKSLEFT),A
;
;
		LD	HL,(STARTBLOCK)
		LD	(CURBLOCK),HL
		LD	HL,(INTERPBASEV)
		LD	(CURDEST),HL
		CALL	READMANY	;<-- page zero dies here
;
;
;==================================================================================
; Force TOPRAM down to the shim's base, then carve the sector table and the
; sector buffer below it, exactly as the real tertbot does. Passing the raw
; counts instead of addresses points the interpreter's buffer at 0080h, inside
; its own code.
;==================================================================================
		LD	HL,NEWTOP
		LD	(TOPRAMV),HL
;
		LD	HL,(TOPRAMV)
		LD	DE,(MAXSECTORSV)
		OR	A
		SBC	HL,DE
		LD	(MAXSECTORSV),HL	;sector-table ADDRESS
;
		LD	DE,(MAXBYTESV)
		OR	A
		SBC	HL,DE
		LD	(MAXBYTESV),HL		;sector-buffer ADDRESS
;
		LD	A,L			;word-align, as the real tertbot does
		AND	0FEh
		LD	L,A
		LD	(TOPRAMV),HL		;TOPRAM ends up below both
		LD	SP,HL			;AND SO DOES THE STACK. Without this
					;the thirteen words are pushed into the
					;sector table and the interpreter runs
					;on a stack inside its own buffers.
;
;
;==================================================================================
; Push the 13 words and enter the interpreter. Twelve parameters, then the boot
; unit on top -- the cold start pops the unit FIRST, then exactly twelve. Push
; only twelve and everything is off by two bytes and it dies silently.
;==================================================================================
		LD	HL,(MAXBYTESV)
		PUSH	HL
		LD	HL,(MAXSECTORSV)
		PUSH	HL
		LD	HL,(SKEWV)
		PUSH	HL
		LD	HL,(FIRSTTRACKV)
		PUSH	HL
		LD	HL,(INTERLEAVEV)
		PUSH	HL
		LD	HL,(BYTESV)
		PUSH	HL
		LD	HL,(SECTORSV)
		PUSH	HL
		LD	HL,(TRACKSV)
		PUSH	HL
		LD	HL,(TOPRAMV)
		PUSH	HL
		LD	HL,(LOWMEMV)
		PUSH	HL
		LD	HL,SHIMDEST+3		;SBIOS = the shim's WBOOT entry
		PUSH	HL
		LD	HL,(INTERPBASEV)
		PUSH	HL
		LD	HL,BOOTUNIT
		PUSH	HL
;
;
		LD	HL,IM2TAB	;257 identical bytes, so the data bus value
		LD	(HL),IM2BYTE	;during the acknowledge cycle cannot matter
		LD	DE,IM2TAB+1
		LD	BC,256
		LDIR
		LD	A,0FBh		;IM2STUB: EI / RETI -- acknowledge the
		LD	(IM2STUB),A	;interrupt and return, doing nothing.
		LD	HL,04DEDh	;ED 4D little-endian: RETI
		LD	(IM2STUB+1),HL
		LD	A,IM2PAGE
		LD	I,A
		IM	2
		EI			;and let the console live again
;
		LD	HL,(INTERPBASEV)
		LD	DE,0200h
		ADD	HL,DE
		JP	(HL)			;INTERPBASE+0200h
;
NOTFOUND:
		LD	DE,NOTFOUNDMSG
		CALL	MESSAGEOUT	;BDOS is still valid -- nothing loaded yet
HANGLOOP:
		JP	HANGLOOP

;==================================================================================
; READMANY / READBLOCK
;
; A p-System block is 512 bytes and so is a physical sector, so one block is
; ONE read. On MultiComp this loop ran four times per block.
;==================================================================================
READMANY:
RM_LOOP:
		LD	HL,(CURBLOCK)
		LD	DE,(CURDEST)
		CALL	READBLOCK
		LD	HL,(CURBLOCK)
		INC	HL
		LD	(CURBLOCK),HL
		LD	HL,(CURDEST)
		LD	DE,512
		ADD	HL,DE
		LD	(CURDEST),HL
		LD	A,(BLOCKSLEFT)
		DEC	A
		LD	(BLOCKSLEFT),A
		JP	NZ,RM_LOOP
		RET
;
; HL = block number, DE = destination
READBLOCK:
		LD	(DESTPTR),DE
		LD	A,L
		AND	7Fh		;sector within track (SECTORS = 128)
		LD	(CURSECTOR),A
		LD	B,7
SHIFT7:
		SRL	H
		RR	L
		DJNZ	SHIFT7
		LD	DE,(FIRSTTRACKV)
		ADD	HL,DE
		LD	(TRACKVAL),HL
;
		LD	DE,(DESTPTR)
		LD	B,D
		LD	C,E
		CALL	SETDMA
		LD	HL,(TRACKVAL)
		LD	B,H
		LD	C,L
		CALL	SETTRK
		LD	A,(CURSECTOR)
		LD	C,A
		LD	B,0
		CALL	SETSEC
		LD	C,PSYSDRV
		CALL	SELDSK
		CALL	READ
		RET
;
; SECBOOT's own BIOS access -- straight to the real thing, never the shim.
SELDSK:
		LD	E,1Bh-03h
		JP	BIOSJMP
SETTRK:
		LD	E,1Eh-03h
		JP	BIOSJMP
SETSEC:
		LD	E,21h-03h
		JP	BIOSJMP
SETDMA:
		LD	E,24h-03h
		JP	BIOSJMP
; READ is NOT called directly -- it dispatches into the system bank. Go through
; the BIOS's own banking wrapper, exactly as PASBOOT v4 does.
READ:
		PUSH	BC
		LD	HL,(SBIOSADDRV)	;NOT (BOOT+1) -- page zero is destroyed
		DEC	HL		;partway through the interpreter load
		DEC	HL
		DEC	HL		;HL = BIOS base
		PUSH	HL
		LD	BC,01A5h	;READ entry, PRL 02A5h
		ADD	HL,BC
		POP	DE		;DE = base
		EX	DE,HL		;HL = base, DE = READ entry
		LD	BC,00FFh	;wrapper, PRL 01FFh
		ADD	HL,BC
		EX	DE,HL		;HL = READ entry, DE = wrapper
		POP	BC
		CALL	GOWRAP
		RET
GOWRAP:
		PUSH	DE		;tail-jump to the wrapper with HL set
		RET
USRCALL:
		JP	(HL)		;call the address in HL
;
BIOSJMP:
		LD	D,0
		LD	HL,(SBIOSADDRV)	;likewise -- SELDSK/SETTRK/SETSEC/SETDMA
		ADD	HL,DE		;are called for every block of the load
		JP	(HL)
;
MESSAGEOUT:
		LD	C,WRBUF
		JP	BDOS
;
;
TARGETNAME:	DB	13,"SYSTEM.INTERP"
NOTFOUNDMSG:	DB	CR,LF,"SYSTEM.INTERP not found",CR,LF,EOM
;
