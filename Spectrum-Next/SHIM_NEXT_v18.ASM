;==================================================================================
; SBIOS SHIM for the ZX Spectrum Next -- v18 -- READ THE KEYBOARD OURSELVES
;
; The BIOS console cannot give us input: it fills its buffer from the NextZXOS
; interrupt chain, and that chain cannot run once the interpreter owns low
; memory (proved by SECBOOT_NEXT_v14DIAG -- one star, then nothing). A PS/2
; keyboard fails identically, which is the clue that matters: on the Next the
; FPGA merges PS/2 into the ordinary Spectrum key matrix, so both keyboards
; arrive by the same route, and that route is software, not hardware.
;
; The matrix itself is readable by polling. IN A,(0FEh) with the row select in
; B returns key states straight from the ULA, and AllRam mode remaps memory,
; not I/O, so it works normally under CP/M. So CONST and CONIN are implemented
; here in hardware terms and the BIOS console is bypassed for input entirely.
; Output still goes through CONOUT, which works perfectly.
;
; This is the same approach the MultiComp shim takes with that machine's ACIA:
; drive the hardware, do not rely on the OS.
;
;----------------------------------------------------------------------------
; KEY MAP
;
; Letters produce UPPER CASE, because UCSD's command line and its Pascal are
; conventionally upper case. Lower case is not reachable in this version; if it
; turns out to matter, swap the plain and CAPS letter cases over.
;
;   CAPS SHIFT + letter    control code (CTRL-A is 01, CTRL-Z is 1A)
;   CAPS SHIFT + SPACE     ESC (1Bh)
;   CAPS SHIFT + 0         backspace (08h)
;   SYMBOL SHIFT + key     punctuation, per the table at the end
;
; The punctuation layout follows the Spectrum's printed legends where they
; exist -- SS+Z is ':', SS+M is '.', SS+N is ',', SS+J is '-' and so on -- and
; fills the gaps with what Pascal needs: brackets and braces on SS+Q/W and
; SS+D/F, which the Spectrum has no legends for.
;
;----------------------------------------------------------------------------
; NO AUTO-REPEAT
;
; A key must be released before the same key registers again. That is a
; deliberate simplification: without an interrupt there is no timebase to
; measure a repeat delay against, and a bare "still pressed" test would flood
; the p-System. Holding a key does nothing; press it again.
;
; -- original v17 header follows --
;
; SBIOS SHIM for the ZX Spectrum Next -- v17 -- PRODUCTION, MARKERS OUT
;
; The p-System boots and the display is correct. Swapping in the stock
; SYSTEM.PASCAL and the VT52 SYSTEM.MISCINFO from SYSCPM1_VT52.VOL fixed the
; ANSI cursor sequences -- which also proves cursor addressing on this system
; is driven from MISCINFO rather than a compiled-in GOTOXY.
;
; The stray dot under the date line was ours: the SELDSK marker, printed on
; every disk operation. All the diagnostic markers come out here.
;
; What remains is the keyboard. CONST is live and honest, but the BIOS fills
; its key buffer from the NextZXOS interrupt chain, and our IM 2 vector sends
; the 50Hz interrupt to an EI/RETI stub instead. Nothing scans the keys, so
; CONST correctly reports that none are waiting.
;
; That is not fixable from this file. See the notes in SECBOOT: the chain has
; to run, and it crashed when tried, because the interpreter owns the low
; memory CP/M's handler expects.
;
; -- original v16 header follows --
;
; SBIOS SHIM for the ZX Spectrum Next -- v16 -- CONST LIVE ON A STABLE MACHINE
;
; v15 booted. UCSD p-System IV.0 came up to its main menu on the Spectrum Next.
;
; That also settles what "Exec err # 6" was, and it was not BYTES=512. It was a
; garbage CONST: with no valid interrupt vector the console reported nonsense,
; the p-System acted on it, and the arithmetic fell over. Once interrupts were
; absorbed safely by the IM 2 stub and CONST answered a flat "no key", the boot
; completed. The 512-byte sector geometry is fine and the planned deblocking
; rework is not needed.
;
; The keyboard does not work because CONST is stubbed -- by design, for
; determinism. This build takes the stub out again.
;
; The open question is whether the BIOS's CONST polls the keyboard hardware
; itself, or relies on the NextZXOS interrupt chain that our EI/RETI stub has
; replaced. If it polls, this is all that is needed. If it depends on the
; chain, expect the old symptoms back -- err 13, or a hang -- in which case the
; next step is SECBOOT chaining the IM 2 vector to CP/M's own handler at FE0Ah
; rather than absorbing the interrupt, possibly with USERF function 4 used to
; control what that handler does.
;
; Nothing else changes, so if this misbehaves the previous image is a known-good
; fallback.
;
; -- original v15 header follows --
;
; SBIOS SHIM for the ZX Spectrum Next -- v15 -- DETERMINISTIC PLATFORM
;
; Paired with SECBOOT v13, which installs an IM 2 vector pointing at EI/RETI so
; that interrupts are absorbed harmlessly wherever they are enabled. No DI is
; needed here any more -- and none would help, since the point is that the BIOS
; may enable interrupts behind our backs.
;
; CONST goes back to the stub. Not as a fix, but for determinism: with no ISR
; the keyboard is never scanned, so a live CONST reports garbage, and garbage
; from CONST is what produced err 6, err 13 and a hang from three builds that
; differed only in instrumentation. Answering a flat "no key" makes the machine
; repeatable, which is what is needed to attack Exec err #6.
;
; The K marker goes with it -- there is nothing left for it to measure.
;
; -- original v14 header follows --
;
; SBIOS SHIM for the ZX Spectrum Next -- v14 -- LET INTERRUPTS RUN
;
; Paired with SECBOOT v10, which restores CP/M's interrupt vector at 0038h and
; EIs before handing over. Every DI here is therefore removed: they existed
; only to undo an EI inside the BIOS console, and that EI is now what we want.
; Leaving them would switch interrupts off on the first console call and put us
; straight back where we started.
;
; The K marker stays. If CONST now tells the truth it should fall silent.
;
; -- original v13 header follows --
;
; SBIOS SHIM for the ZX Spectrum Next -- v13 -- IS CONST TELLING THE TRUTH?
;
; Restoring CONST changed the failure from "Exec err # 6" to "Exec err # 13",
; and space still does nothing. 13 is string overflow.
;
; The obvious reading is that CONST is lying: with interrupts off, Garry's BIOS
; never gets to scan the keyboard, so whatever CONST reports is stale or
; garbage. If it keeps saying "key ready", the p-System keeps calling CONIN,
; and a stream of phantom characters overflows an input buffer -- which is
; exactly error 13, and also why a real keypress appears to do nothing.
;
; That is a good story, and stories have been wrong twice today. So measure it
; instead:
;
;       K   printed ONLY when CONST returns non-zero, i.e. claims a key is
;           waiting. Nothing is printed on the normal "no key" path, so a
;           quiet screen means CONST is behaving.
;       ?   CONIN, as before.
;
; Reading it:
;   a flood of K (and ?)   CONST is inventing keypresses. The console genuinely
;                          needs the 50Hz ISR, and the interrupt work can no
;                          longer be deferred.
;   no K at all            CONST is honest and says "no key" -- so err 13 comes
;                          from somewhere else entirely, and the keyboard is
;                          not the problem. Look at the handoff again.
;   a few K, then err 13   something in between; the counts will say what.
;
; SHFWD already CALLs and re-asserts DI, so A comes back intact and interrupts
; stay off while we test the marker.
;
; -- original v12 header follows --
;
; SBIOS SHIM for the ZX Spectrum Next -- v12 -- CONST RESTORED
;
; v11 reached "!" and then "Exec err #6" -- SYSTEM.PASCAL loaded, executing
; p-code, and reporting through its own error handler. The bootstrap, the
; banking, the geometry and the console all work. What is left is a fault
; inside the p-System, not underneath it.
;
; CONST has been stubbed since v5, answering "no character ready" without
; calling the BIOS, to keep one variable pinned while the disk side was in
; doubt. It is not in doubt any more, and the stub now actively prevents
; progress: UCSD follows an execution error with "Type <space> to continue",
; which the p-System can never see.
;
; So CONST forwards for real again. The reason it was suspect in the first
; place -- that Garry's BIOS may scan the keyboard from its 50Hz ISR, and we
; run with interrupts off -- is still a live possibility. But SHFWD now CALLs
; and then DIs rather than tail-jumping, so if CONST does return sensibly this
; is safe; and if it hangs, we will see it hang here rather than guess.
;
; Watch for:
;   the error, then the system continuing   CONST works; chase err #6
;   the error, then a freeze                CONST needs interrupts after all,
;                                           and the IM 2 / 0038h work in
;                                           STATUS.md becomes the next job
;
; -- original v11 header follows --
;
; SBIOS SHIM for the ZX Spectrum Next -- v11 -- RELOCATED TO F000h
;
; Same as v10, but ORG'd at F000h to match SECBOOT v9. C000h-F1FFh turned out
; to be ordinary TPA RAM, not forbidden common memory, so the shim and TOPRAM
; both move up and the p-System gets back 12.5K it never should have lost.
; See the PASBOOT v8 header.
;
; F000h is in bank 3, common to both memory configurations, so unlike BE00h
; this address stays mapped even while the BIOS has the system bank paged in.
;
; The light markers stay, because the failure they need to catch -- silence
; after the load, no CONOUT, white border -- is still unexplained.
;
; -- original v10 header follows --
;
; SBIOS SHIM for the ZX Spectrum Next -- v10 -- LIGHT MARKERS
;
; v9 froze at C with no output. But v9 was also the first run with no markers,
; and v8 never actually FINISHED in front of us -- the photo showed it mid-load
; with most of SYSTEM.PASCAL's 104 blocks still to go. Removing the markers
; assumed the rest of the boot was sound. That was never measured. v9 may
; simply be dying where v8 would have, invisibly, in territory we have never
; had eyes on.
;
; So: markers that cost one character per OPERATION, not five per sector.
; v8's full tracing spent five characters on every 512 bytes; loading
; SYSTEM.PASCAL that way is ~530 characters through a banked CONOUT. This
; build prints:
;
;       .   SELDSK -- one per unitread/unitwrite/unitclear (one per 2KB read)
;       h   HOME   -- only reached by the read-retry loop, so any h after the
;                     first few means a read failed and is being retried
;       #   WRITE
;       ?   CONIN  -- the p-System wants input; with CONST stubbed and
;                     interrupts off this is where it would wedge
;       !   printed ONCE, immediately before the p-System's first character
;                     goes to the real CONOUT. If ! appears and nothing after
;                     it, the BIOS CONOUT itself is what dies under DI.
;
; Reading the result:
;   dots then silence      count them; ~30 means it died at the end of the
;                          SYSTEM.PASCAL load, fewer means mid-load
;   dots then ! then text  IT BOOTS.
;   dots then ! then stop  console output is the problem, not the disk
;   dots then ?            it is waiting for a key it can never see
;
; All markers go through SHMARK, which ends in DI, as does every forward.
;
; -- original v9 header follows --
;
; SBIOS SHIM for the ZX Spectrum Next -- v9 -- MARKERS OUT, TAIL-JUMPS FIXED
;
; v8 worked. The p-System read the disk:
;
;       s00042h  s00040 dter dter dter dter  s00040 dter dter ...
;
; SELDSK on unit 4 for unitclear, then HOME, then unitread after unitread, each
; one SELDSK followed by four SETDMA/SETTRK/SETSEC/READ groups -- exactly
; 2048 bytes at 512 bytes a sector. No 'h' after the first, so nothing was
; failing and retrying. It was loading SYSTEM.PASCAL, 104 blocks of it, one
; marker character at a time through CONOUT.
;
; So the markers come out. This build is v2 -- the clean shim from before any
; instrumentation -- with two changes.
;
; 1. EVERY forwarded call now returns through a DI.
;
;    This is the same fault SECBOOT v8 fixed, and it is not merely a diagnostic
;    concern. SHFWD and SHWRAP were tail-jumps: they left the real BIOS routine
;    to return directly to the interpreter. If a BIOS console routine does EI on
;    its way out -- and the evidence of the last five runs says one of them does
;    -- then interrupts come back on and stay on, with 0038h full of the
;    interpreter's pointer table.
;
;    That did not matter while the shim was only being called for disk work.
;    It matters enormously now, because the moment the p-System starts printing
;    it will be going through SH_CONOUT on every single character.
;
;    So both now CALL and then DI before returning. DI affects no registers, so
;    A survives for the status and HL survives for SECTRAN.
;
; 2. CONST stays stubbed, returning "no character ready".
;
;    Not a fix -- the p-System cannot see the keyboard like this -- but it keeps
;    one variable pinned while we find out whether the boot completes. Undo it
;    once it does, and expect to have to solve the interrupt question properly:
;    see STATUS.md for the IM 2 and 0038h options.
;
; -- original v2 header follows --
;
; SBIOS SHIM for the ZX Spectrum Next -- v2 -- runs at 0F000h, ABOVE TOPRAM
;
; v2 routes READ and WRITE through the BIOS's banking wrapper. v1 called them
; directly, which cannot work and would have hung on the interpreter's very
; first directory read -- the same wall PASBOOT hit. Disassembling nextbios.prl
; shows why:
;
;   READ   base+01A5h  PUSH IX / LD IX,7C98h / CALL tail / POP IX / RET
;   WRITE  base+019Dh  PUSH IX / LD IX,7CC8h / JR  tail
;   tail   base+01B1h  PUSH IX / load trk,sec,drv,DMA,bank / RET
;
; The closing RET is a tail-jump to the pushed IX. 7C98h and 7CC8h only exist
; with the system bank paged in, and nothing on that path pages it in, because
; the BIOS's normal caller is the banked BDOS. The wrapper at base+00FFh does
; it for us and preserves the status in A.
;
;   base    = REALBIOS - 3          (REALBIOS is the BIOS's WBOOT entry)
;   wrapper = REALBIOS + 00FCh
;   READ    = REALBIOS + 01A2h
;   WRITE   = REALBIOS + 019Ah
;
; Everything else is unchanged. Two further findings from the same disassembly,
; both reassuring:
;
; * SETTRK (base+016Fh) is LD (02E1h),BC and SETSEC (base+0174h) is
;   LD (02E3h),BC -- both store the FULL BC, so zeroing B here is genuinely
;   required and not superstition.
;
; * SETDMA (base+0179h) also copies the current bank configuration into the
;   DMA bank variable at 02E7h. So the DMA bank looks after itself as long as
;   SETDMA is called while our own bank is paged in, which it always is. No
;   SETBNK call is needed here.
;
; Sits between the p-System's SBIOS calls and CP/M 3's BIOS, translating the
; handful of places where the two disagree.
;
; It is a QUARTER the size of the MultiComp shim, because the console needs no
; translation at all. The Next's CP/M terminal emulates a Zenith Z-19 -- a VT52
; family terminal with single-character escape sequences -- which is exactly
; what UCSD's SYSTEM.MISCINFO was designed to describe. So ESC H, ESC J, ESC K,
; ESC A, ESC C and backspace all go straight through untouched.
;
; On MultiComp the console translator was about 600 of the shim's 972 bytes and
; accounted for nearly all the debugging: parameters had to be added to every
; sequence, a '[' inserted after every ESC, and an ESC[0K that silently homed
; the cursor had to be undone. None of that applies here.
;
;----------------------------------------------------------------------------------
; WHAT IS STILL NEEDED, AND WHY (all four proven on MultiComp)
;
; 1. SELDSK must return HL=0. The p-System's convention is HL=0 for SUCCESS;
;    CP/M returns a DPH pointer, which the interpreter reads as failure and
;    abandons the read. The drive is also forced to P: here, since the p-System
;    has no notion of our drive letters.
;
; 2. SETTRK/SETSEC must zero B. The p-System passes an 8-bit value in C alone;
;    the Next's BIOS stores the full BC (verified by disassembling
;    nextbios.prl: LD (trk),BC).
;
; 3. SETSEC must decrement. The interpreter emits 1-based sector numbers; CP/M
;    sectors are 0-based.
;
; 4. WRITE must set a valid CP/M write type. The p-System does not set one and
;    the BIOS stores whatever is in C.
;
;----------------------------------------------------------------------------------
; WHAT IS NOT NEEDED HERE
;
; * No console translation -- see above.
; * No direct hardware console driver. MultiComp needed one because the
;   interpreter overwrites the iobyte at 0003h when it loads at 0000h, making
;   Grant's console routines unusable. CP/M 3's BIOS keeps its state in the
;   common area at C000h and up, which the load never touches.
; * No keyboard ring buffer, PROBABLY. MultiComp lost keystrokes because its
;   ACIA has a one-byte receive register and nothing captured characters while
;   the screen was being painted. The Next's BIOS may well buffer input itself.
;   If characters go missing when typing quickly, port the ring buffer from
;   SHIM_MULTICOMP_v17.ASM -- there is room.
; * No deblocking. BYTES=512 in the handoff means one p-System sector is one
;   physical sector. If the interpreter rejects that, this is where the
;   read-modify-write logic would go, and there would not be room at 384 bytes.
;
;----------------------------------------------------------------------------------
; SIZE LIMIT
;
; This must assemble to 384 bytes or fewer. It is copied from the loaded window
; at 8480h, and the p-System volume's directory starts immediately after the
; two reserved blocks that hold the secondary stage.
;==================================================================================

SHIMBASE	EQU	0F000h
PSYSDRV		EQU	15

		ORG	SHIMBASE

SHIM:
		JP	SH_BOOT		;bios+0
		JP	SH_WBOOT	;bios+3   <-- handed over as the SBIOS address
		JP	SH_CONST	;bios+6
		JP	SH_CONIN	;bios+9
		JP	SH_CONOUT	;bios+12
		JP	SH_LIST		;bios+15
		JP	SH_PUNCH	;bios+18
		JP	SH_READER	;bios+21
		JP	SH_HOME		;bios+24
		JP	SH_SELDSK	;bios+27
		JP	SH_SETTRK	;bios+30
		JP	SH_SETSEC	;bios+33
		JP	SH_SETDMA	;bios+36
		JP	SH_READ		;bios+39
		JP	SH_WRITE	;bios+42
		JP	SH_LISTST	;bios+45
		JP	SH_SECTRAN	;bios+48

;----------------------------------------------------------------------------
; Variable at a FIXED offset -- SECBOOT pokes it before handoff.
;   REALBIOS = SHIM+51 = 0F033h
;----------------------------------------------------------------------------
REALBIOS:	DW	0000h

;----------------------------------------------------------------------------
; Straight pass-throughs. DE holds the offset from the real BIOS's base.
;----------------------------------------------------------------------------
SH_BOOT:
		LD	DE,-3
		JP	SHFWD
SH_WBOOT:
		LD	DE,0
		JP	SHFWD
SH_CONST:
		LD	A,(KPEND)	;already have one waiting?
		OR	A
		JR	NZ,KRDY
		CALL	KSCAN
		OR	A
		JR	Z,KNONE
		LD	(KPEND),A
KRDY:
		LD	A,0FFh		;CP/M convention: FFh = character ready
		RET
KNONE:
		XOR	A
		RET
SH_CONIN:
		LD	A,(KPEND)	;take the one CONST found, if any
		OR	A
		JR	NZ,KTAKE
KWAIT:
		CALL	KSCAN
		OR	A
		JR	Z,KWAIT
		RET
KTAKE:
		PUSH	AF
		XOR	A
		LD	(KPEND),A
		POP	AF
		RET
SH_CONOUT:
		LD	DE,9		;the Z-19 needs no translation
		JP	SHFWD
SH_LIST:
		LD	DE,12
		JP	SHFWD
SH_PUNCH:
		LD	DE,15
		JP	SHFWD
SH_READER:
		LD	DE,18
		JP	SHFWD
SH_HOME:
		LD	DE,21
		JP	SHFWD
SH_SETDMA:
		LD	DE,33		;also sets the DMA bank from the current
		JP	SHFWD		;configuration -- see the header
SH_SECTRAN:
		LD	DE,45
		JP	SHFWD
SH_LISTST:
		LD	A,0FFh
		RET

;----------------------------------------------------------------------------
; The four that need translating.
;----------------------------------------------------------------------------
SH_SELDSK:
		LD	C,PSYSDRV	;force drive P -- the p-System has no
		LD	DE,24		;notion of our drive letters
		LD	HL,(REALBIOS)
		ADD	HL,DE
		CALL	SHCALL
		LD	HL,0000h	;p-System success convention, NOT a DPH
		RET
SH_SETTRK:
		LD	B,0		;p-System passes 8 bits in C; the BIOS
		LD	DE,27		;stores the full BC
		JP	SHFWD
SH_SETSEC:
		LD	B,0
		DEC	C		;1-based (p-System) -> 0-based (CP/M)
		LD	DE,30
		JP	SHFWD

;----------------------------------------------------------------------------
; READ and WRITE -- through the banking wrapper, never directly.
;----------------------------------------------------------------------------
SH_READ:
		LD	DE,01A2h
		JR	SHWRAP
SH_WRITE:
		LD	C,1		;nominal CP/M write type. This BIOS reloads
		LD	DE,019Ah	;BC from its own variables, so it is inert
		JR	SHWRAP		;here -- kept for correctness elsewhere.
SHWRAP:
		LD	HL,(REALBIOS)
		ADD	HL,DE		;HL = the real entry point
		PUSH	HL
		LD	HL,(REALBIOS)
		LD	DE,00FCh
		ADD	HL,DE		;HL = the wrapper
		EX	DE,HL		;DE = wrapper
		POP	HL		;HL = the real entry point
		CALL	SHJPDE		;call the wrapper with HL set
		RET			;no DI -- interrupts are wanted now
SHJPDE:
		PUSH	DE		;jump to DE, leaving HL alone; the wrapper's
		RET			;RET lands on the DI above
;
;============================================================================
; KSCAN -- one ASCII character, or 0 for nothing new.
;
; Returns 0 while a key is held, so one press yields exactly one character.
;============================================================================
KSCAN:
		CALL	KRAW
		OR	A
		JR	NZ,KS1
		LD	(KLAST),A	;nothing down -- arm the next press
		RET
KS1:
		LD	HL,KLAST
		CP	(HL)
		JR	Z,KS2		;same key still down: report nothing
		LD	(HL),A
		RET
KS2:
		XOR	A
		RET
;
;============================================================================
; KRAW -- scan the matrix, return ASCII for the first key found, or 0.
;============================================================================
KRAW:
		LD	BC,0FEFEh	;CAPS SHIFT is row FEFEh bit 0
		IN	A,(C)
		CPL
		AND	01h
		LD	(KCAPS),A
		LD	BC,07FFEh	;SYMBOL SHIFT is row 7FFEh bit 1
		IN	A,(C)
		CPL
		AND	02h
		LD	(KSYM),A
;
		LD	HL,KROWS
		LD	D,0		;row counter
KRLOOP:
		LD	B,(HL)		;row select
		INC	HL
		LD	C,0FEh
		IN	A,(C)
		CPL			;now 1 = pressed
		LD	C,(HL)		;mask off this row's shift key, if any
		INC	HL
		AND	C
		JR	NZ,KRGOT
		INC	D
		LD	A,D
		CP	8
		JR	NZ,KRLOOP
		XOR	A		;nothing pressed
		RET
KRGOT:
		OR	A		;clear carry before rotating
		LD	E,0FFh
KRBIT:
		INC	E		;E = index of the lowest set bit
		RRA
		JR	NC,KRBIT
;
		LD	A,D		;index = row*5 + bit
		ADD	A,A
		ADD	A,A
		ADD	A,D
		ADD	A,E
		LD	L,A
		LD	H,0
;
		LD	A,(KSYM)
		OR	A
		JR	NZ,KRSYM
		LD	DE,KPLAIN
		ADD	HL,DE
		LD	A,(HL)
		LD	E,A
		LD	A,(KCAPS)
		OR	A
		LD	A,E
		RET	Z		;no shift: the plain character
;
		CP	' '		;CAPS SHIFT + SPACE = ESC
		JR	NZ,KRC1
		LD	A,1Bh
		RET
KRC1:
		CP	'0'		;CAPS SHIFT + 0 = backspace
		JR	NZ,KRC2
		LD	A,08h
		RET
KRC2:
		CP	'A'		;CAPS SHIFT + letter = control code
		RET	C
		CP	'Z'+1
		RET	NC
		AND	1Fh
		RET
KRSYM:
		LD	DE,KSYMTB
		ADD	HL,DE
		LD	A,(HL)
		RET
;
;----------------------------------------------------------------------------
; Row select bytes and the mask that removes each row's shift key.
;----------------------------------------------------------------------------
KROWS:
		DB	0FEh,1Eh	;CAPS,Z,X,C,V   -- bit 0 is CAPS SHIFT
		DB	0FDh,1Fh	;A,S,D,F,G
		DB	0FBh,1Fh	;Q,W,E,R,T
		DB	0F7h,1Fh	;1,2,3,4,5
		DB	0EFh,1Fh	;0,9,8,7,6
		DB	0DFh,1Fh	;P,O,I,U,Y
		DB	0BFh,1Fh	;ENTER,L,K,J,H
		DB	07Fh,1Dh	;SPACE,SYM,M,N,B -- bit 1 is SYMBOL SHIFT
;
KPLAIN:
		DB	0,'Z','X','C','V'
		DB	'A','S','D','F','G'
		DB	'Q','W','E','R','T'
		DB	'1','2','3','4','5'
		DB	'0','9','8','7','6'
		DB	'P','O','I','U','Y'
		DB	0Dh,'L','K','J','H'
		DB	' ',0,'M','N','B'
;
KSYMTB:
		DB	0,3Ah,5Ch,3Fh,2Fh	;  : \ ? /
		DB	7Eh,7Ch,7Bh,7Dh,60h	;  ~ | { } `
		DB	5Bh,5Dh,5Eh,3Ch,3Eh	;  [ ] ^ < >
		DB	21h,40h,23h,24h,25h	;  ! @ # $ %
		DB	5Fh,29h,28h,27h,26h	;  _ ) ( ' &
		DB	22h,3Bh,0,0,0		;  " ;
		DB	0Dh,3Dh,2Bh,2Dh,0	;  CR = + -
		DB	' ',0,2Eh,2Ch,2Ah	;  space . , *
;
KPEND:		DB	0		;character found by CONST, not yet taken
KLAST:		DB	0		;key currently held, for repeat suppression
KCAPS:		DB	0
KSYM:		DB	0
;
;
; SHFWD -- forward to REALBIOS+DE, then re-assert DI. NOT a tail-jump: the
; BIOS may EI on its way out, and the interpreter cannot survive that.
SHFWD:
		LD	HL,(REALBIOS)
		ADD	HL,DE
		CALL	SHCALL
		RET			;no DI -- interrupts are wanted now
SHCALL:
		JP	(HL)
;
SHIMEND:
