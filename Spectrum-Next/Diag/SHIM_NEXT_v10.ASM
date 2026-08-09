;==================================================================================
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
; SBIOS SHIM for the ZX Spectrum Next -- v2 -- runs at 0BE00h, ABOVE TOPRAM
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

SHIMBASE	EQU	0BE00h
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
;   REALBIOS = SHIM+51 = 0BE33h
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
		XOR	A		;STUBBED: always "no character ready".
		RET			;See the header -- this must be undone.
SH_CONIN:
		LD	A,'?'		;the p-System wants a key. With CONST
		CALL	SHMARK		;stubbed this is where it would wedge.
		LD	DE,6
		JP	SHFWD
SH_CONOUT:
		LD	A,(FIRSTOUT)	;announce the p-System's FIRST character,
		OR	A		;so "reached CONOUT" and "CONOUT works"
		JR	NZ,SHCO1	;can be told apart
		LD	A,1
		LD	(FIRSTOUT),A
		LD	A,'!'
		CALL	SHMARK
SHCO1:
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
		LD	A,'h'		;reached by the read-retry loop
		CALL	SHMARK
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
		LD	A,'.'		;one per operation -- cheap enough to let
		CALL	SHMARK		;the whole boot run
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
		LD	A,'#'
		CALL	SHMARK
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
		DI			;and take interrupts back off it
		RET
SHJPDE:
		PUSH	DE		;jump to DE, leaving HL alone; the wrapper's
		RET			;RET lands on the DI above
;
; SHMARK -- print A via the real CONOUT, preserve everything, END IN DI.
SHMARK:
		PUSH	AF
		PUSH	BC
		PUSH	DE
		PUSH	HL
		LD	C,A
		LD	HL,(REALBIOS)
		LD	DE,9
		ADD	HL,DE
		CALL	SHMCALL
		POP	HL
		POP	DE
		POP	BC
		POP	AF
		DI
		RET
SHMCALL:
		JP	(HL)
;
FIRSTOUT:	DB	0		;inside the copied image: zero every boot
;
; SHFWD -- forward to REALBIOS+DE, then re-assert DI. NOT a tail-jump: the
; BIOS may EI on its way out, and the interpreter cannot survive that.
SHFWD:
		LD	HL,(REALBIOS)
		ADD	HL,DE
		CALL	SHCALL
		DI
		RET
SHCALL:
		JP	(HL)
;
SHIMEND:
