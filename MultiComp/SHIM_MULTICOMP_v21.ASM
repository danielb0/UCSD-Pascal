;==================================================================================
; SBIOS SHIM v21 for MultiComp UCSD p-System -- runs at 0E200h, ABOVE TOPRAM
;
; *** THE FAULT, FOUND BY THE v30 PROBE ***
;
; MultiComp's ESC[0K erases correctly -- and then MOVES THE CURSOR TO HOME.
; The probe wrote a single '@' with no positioning after an erase issued at
; row 3 column 5. The '@' appeared at ROW 1 COLUMN 1.
;
; So every erase-to-end-of-line silently teleports the cursor to the top left,
; and whatever the editor writes next lands on row 1. That single behaviour
; accounts for all of it: text a row too high, the menu drawn over the text,
; text vanishing when you press return, and the .7j] tail of the Edit prompt
; surviving under the Insert banner.
;
; The alternatives are no good: ESC[2K does nothing at all, and ESC[1K is not
; implemented -- it prints a literal 'K'. ESC[0K is the only erase that works,
; so the shim must use it and then put the cursor back.
;
; That means tracking the cursor again, which v18 deliberately deleted. The
; reason it was deleted no longer applies: it was being used to SYNTHESISE
; cursor-right, where drift accumulates and shows up as a wandering cursor.
; Here it is used only to restore position immediately after an erase, and the
; editor issues an absolute ESC[r;cH right before almost every erase, so the
; tracked value is freshly resynchronised at exactly the moment it is needed.
;
; ESC J is given the same treatment. Whether ESC[0J also homes was never
; measured, and restoring afterwards is harmless if it does not.
;
; Cursor right/left still go out as ESC[1C and 08h -- measured good, no
; synthesis, so no drift can creep in through them.
;
; v18 = v17 with ALL CURSOR TRACKING DELETED.
;
; The v24 probe showed MultiComp implements cursor right after all -- both
; ESC[10C and the single-step ESC[1C the shim emits. The original finding that
; it did not was read off a garbled screen and was wrong.
;
; Everything since v9 has been built on that mistake. Because the shim believed
; it had to fabricate cursor-right, it tracked the column itself and re-expressed
; the move as an absolute ESC[r;cH. Tracking drifts -- it can only count what it
; sees -- and a drifted column produces a cursor that jumps to the wrong place
; or backwards. That is the reported symptom, and it was self-inflicted.
;
; v18 therefore removes CURROW/CURCOL maintenance, COLINC, COLDEC, ROWINC and
; ACC10 entirely. Every translation is now a fixed substitution that cannot
; drift:
;     ESC H -> ESC[1;1H     ESC A -> ESC[1A      ESC C -> ESC[1C
;     ESC J -> ESC[0J       ESC B -> ESC[1B      ESC D -> 08h (backspace)
;     ESC K -> ESC[0K       ESC I -> ESC M       ESC <digits> passed through
;     0Ch   -> ESC[1;1H ESC[0J                   00h   -> discarded
;
; ESC D goes out as a plain backspace rather than ESC[1D: MISCINFO already uses
; 08h for cursor-left and it is known good, whereas ESC[1D behaved oddly on the
; v24 probe -- the marker landed to the RIGHT of where it started. Not worth
; relying on when a proven alternative exists.
;
; CURROW/CURCOL survive only as scratch for the VT52 ESC Y form, which the
; p-System does not appear to use but which costs almost nothing to keep.
;
; The keyboard ring buffer from v17 is unchanged -- it fixed the lost keystrokes
; on entering insert mode and is independent of all this.
;
; v17 = v10 + A KEYBOARD BUFFER. Built on v10, NOT v16: v16's NUL delay was
; aimed at a fault the SECBOOT v22 probe later disproved, and it actively makes
; the bug fixed here worse.
;
; THE BUG. Typing LINE<ret> three times in insert mode, the shim's own output
; transcript showed the p-System echoing:
;     ...~[0K N E ~[0J ~[3;1H LINE ~[0K ~[4;1H LINE ~[0K ~[5;1H
; The second and third lines are complete. The first is 'NE' -- the L and the I
; were never echoed, so they were never received. This is the long-standing
; 'you have to press <ret> before you can type' symptom.
;
; WHY. The ACIA has a one-byte receive register and no buffer. A keystroke
; survives only if the p-System is inside CONIN/CONST when it lands. On
; entering insert mode the editor paints its banner -- about 70 characters plus
; a dozen escape sequences -- and anything typed during that paint is
; overwritten and lost. Our translation makes the window three times wider than
; it need be, since every 2-byte control code leaves as a 6-byte ANSI one.
;
; THE FIX. The shim already sits in the transmit wait loop, doing nothing but
; spinning on the TX-empty flag. It now checks the RECEIVE flag on every pass
; of that loop and stashes any character into a 16-byte ring. CONIN drains the
; ring before touching the ACIA; CONST reports ready if the ring is non-empty.
; Keystrokes arriving mid-paint are therefore captured instead of dropped.
;
; A full ring discards the NEWEST character. Losing a keystroke is bad; losing
; sync between head and tail would be worse.
;
; v10 fixes two defects in v9:
;
;  (1) NUL IS NOW DISCARDED IN EVERY STATE, not just state 0. The p-System
;      pads control codes with five NULs. v9 stripped them only in normal
;      text, so a pad byte arriving straight after an ESC was taken as the
;      sequence's command character: it went out as ESC [ <NUL>, the state
;      machine reset, and the real command letter then printed as a literal.
;      That is precisely the 'stray H, K, I, R' symptom, and it would make
;      every home/erase/position silently do nothing -- which is what the
;      editor looked like. A simulation of v9 against the byte stream
;      captured from hardware showed its translation is otherwise exact,
;      so this is the remaining candidate.
;
;  (2) COLINC now WRAPS instead of clamping. MultiComp auto-wraps at the
;      right margin (confirmed by typing past it at the CP/M prompt), so
;      clamping made the tracked row lag by one on every full-width line.
;      SCRCOLS is 79 to match the width now set in SYSTEM.MISCINFO, so in
;      practice the editor should never reach the margin at all.
;
; Note the base moved from E300h to E200h: cursor tracking pushed this past
; the old 768-byte allowance, so the region is now 1024 bytes (E200h..E5FFh).
; That costs the p-System 256 bytes of workspace, which it has to spare --
; the highest address it was ever observed touching is DA32h.
;
; v9 REWRITES THE CONSOLE TRANSLATOR AROUND WHAT MULTICOMP ACTUALLY SUPPORTS.
; Three probes on real hardware established the following. None of it is
; guessed, and several earlier versions were wrong precisely because it was.
;
;   ESC [ r ; c H   WORKS
;   ESC [ 1 A       WORKS   (up: G landed exactly one row above F, same column)
;   ESC [ 0 K       WORKS   (erase to end of line: exactly 7 X's survived)
;   ESC [ 0 J       WORKS   (erase to end of screen)
;   ESC [ H         IGNORED (no parameter)
;   ESC [ K         IGNORED (no parameter)
;   ESC [ J         IGNORED (no parameter)
;   ESC [ 2 J       IGNORED
;   ESC [ 1 C       NOT IMPLEMENTED -- the cursor drifts by the sequence length
;   ESC [ 1 D       NOT IMPLEMENTED -- ditto
;
; MultiComp needs EXPLICIT PARAMETERS on everything, and has no cursor
; left/right at all. Until now this shim emitted ESC[J, ESC[K and ESC[A --
; all parameterless, all silently ignored -- so the editor could never erase
; anything, which is what made it appear to lose track of the cursor.
;
; SYSTEM.MISCINFO nominates exactly these screen codes:
;   lead-in ESC | home 'H' | erase-EOS 'J' | erase-EOL 'K'
;   cursor-right 'C' | cursor-up 'A' | left = plain backspace 08h
;
; TRANSLATION
;   ESC H        -> ESC [ 1 ; 1 H         and reset the tracked position
;   ESC J        -> ESC [ 0 J
;   ESC K        -> ESC [ 0 K
;   ESC A        -> ESC [ 1 A             row--
;   ESC B        -> ESC [ 1 B             row++
;   ESC C        -> ESC [ row ; col+1 H   SYNTHESISED -- see below
;   ESC D        -> ESC [ row ; col-1 H   synthesised (the p-System uses BS)
;   ESC I        -> ESC M
;   ESC Y r c    -> ESC [ r ; c H         (VT52 form, both biased by 32)
;   ESC <digit>  -> ESC [ <digit>...      the ANSI GOTOXY from SYSTEM.PASCAL;
;                                         its digits are parsed so the tracked
;                                         position stays correct
;   0Ch          -> ESC [ 1 ; 1 H + ESC [ 0 J    a clear that actually works
;   00h          -> discarded             the p-System pads every control code
;                                         with five NULs and MultiComp renders
;                                         each as a blank -- this was the ~5
;                                         column indent
;
; CURSOR TRACKING
; Cursor left/right do not exist on this display, so the shim keeps its own
; row/column and expresses those two moves as absolute positioning, which is
; reliable. Tracking is updated by printable characters, CR, LF, BS, the
; sequences above, and by parsing the row/column out of the ANSI GOTOXY. It
; resyncs on every absolute positioning, so drift cannot accumulate for long.
; All updates clamp rather than wrap, so an error cannot run away.
;
; MEMORY MAP (SECBOOT carves from NEWTOP = E200h)
;   0000h..35FFh   SYSTEM.INTERP
;   3600h..E0FFh   p-System workspace (43776 bytes)
;   E100h..E1FFh   sector buffer / sector table
;   E200h..E5FFh   THIS SHIM -- 1024 reserved; SECBOOT's SHIMLEN is 1024
;   E600h..        Grant's CBIOS
;==================================================================================

SHIMBASE	EQU	0E200h
PSYSDRV		EQU	15

ACIA0_C		EQU	80h
ACIA0_D		EQU	81h
ACIA1_C		EQU	82h
ACIA1_D		EQU	83h

ESC		EQU	1Bh
SCRROWS		EQU	24
SCRCOLS		EQU	79		;must match SYSTEM.MISCINFO's width

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
; Variables at FIXED offsets -- SECBOOT pokes the first two before handoff.
;   REALBIOS = SHIM+51 = 0E233h        SAVEIOB = SHIM+53 = 0E235h
;----------------------------------------------------------------------------
REALBIOS:	DW	0000h
SAVEIOB:	DB	00h
VTSTATE:	DB	00h		;0 normal, 1 after ESC, 2 ESC-Y row, 3 ESC-Y col,
					;4 GOTOXY row digits, 5 GOTOXY col digits
VTROW:		DB	00h		;scratch for ESC Y
CURROW:		DB	1		;tracked cursor row 1..24
CURCOL:		DB	1		;tracked cursor column 1..80
ACCUM:		DB	0		;digit accumulator while parsing GOTOXY
KBHEAD:		DB	0		;keyboard ring: read index
KBTAIL:		DB	0		;keyboard ring: write index
KBBUF:		DB	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

;----------------------------------------------------------------------------
; Disk and console entries -- all proven on hardware, unchanged.
;----------------------------------------------------------------------------
SH_BOOT:
		LD	DE,-3
		JP	SHFWD
SH_WBOOT:
		LD	DE,0
		JP	SHFWD
SH_HOME:
		LD	DE,21
		JP	SHFWD
SH_SETDMA:
		LD	DE,33
		JP	SHFWD
SH_WRITE:
		LD	C,1		;valid CP/M write type (write-through)
		LD	DE,39
		JP	SHFWD
SH_SECTRAN:
		LD	DE,45
		JP	SHFWD
SH_LISTST:
		LD	A,0FFh
		RET
SH_CONST:
		JP	MYCST
SH_CONIN:
		JP	MYCIN
SH_CONOUT:
		LD	A,C
		JP	MYCOUT
SH_LIST:
		LD	A,C
		JP	MYCOUT
SH_PUNCH:
		LD	A,C
		JP	MYCOUT
SH_READER:
		JP	MYCIN
;
SH_SELDSK:
		LD	C,PSYSDRV	;force drive P
		LD	DE,24
		LD	HL,(REALBIOS)
		ADD	HL,DE
		CALL	SHCALL
		LD	HL,0000h	;p-System success convention
		RET
SH_SETTRK:
		LD	B,0
		LD	DE,27
		JP	SHFWD
SH_SETSEC:
		LD	B,0
		DEC	C		;1-based (p-System) -> 0-based (Grant)
		LD	DE,30
		JP	SHFWD
SH_READ:
		LD	DE,36
		JP	SHFWD
;
SHFWD:
		LD	HL,(REALBIOS)
		ADD	HL,DE
		JP	(HL)
SHCALL:
		JP	(HL)

;==================================================================================
; MYCOUT -- character in A. Preserves all registers.
;==================================================================================
MYCOUT:
		PUSH	AF
		PUSH	BC
		PUSH	DE
		PUSH	HL
		LD	C,A
		OR	A
		JP	Z,VTDONE	;NUL padding: never reaches the screen
		LD	A,(VTSTATE)
		OR	A
		JP	NZ,VTNOT0
;
;--- state 0: normal text -------------------------------------------------
		LD	A,C
		CP	ESC
		JR	NZ,VT0A
		LD	A,1
		LD	(VTSTATE),A
		JP	VTDONE
VT0A:
		CP	0Ch		;form feed = clear the screen
		JR	NZ,VT0B
		LD	HL,HOMESTR
		CALL	EMIT0
		LD	HL,EOSSTR
		CALL	EMIT0
		JP	SETHOME
VT0B:
		CP	0Dh		;CR
		JR	NZ,VT0C
		LD	A,1
		LD	(CURCOL),A
		JR	VT0PASS
VT0C:
		CP	0Ah		;LF -- a true line feed here, column preserved
		JR	NZ,VT0D
		CALL	ROWINC
		JR	VT0PASS
VT0D:
		CP	08h		;BS
		JR	NZ,VT0E
		CALL	COLDEC
		JR	VT0PASS
VT0E:
		CP	20h
		JR	C,VT0PASS
		CALL	COLINC
VT0PASS:
		LD	A,C
		CALL	RAWOUT
		JP	VTDONE
;
VTNOT0:
		CP	1
		JP	NZ,VTS2
;
;--- state 1: the character after ESC -------------------------------------
		XOR	A
		LD	(VTSTATE),A
		LD	A,C
		CP	'Y'
		JR	NZ,VT1A
		LD	A,2
		LD	(VTSTATE),A
		JP	VTDONE
VT1A:
		CP	'H'
		JR	NZ,VT1B
		LD	HL,HOMESTR
		CALL	EMIT0
		JP	SETHOME
VT1B:
		CP	'J'		;erase to end of screen, then RESTORE the cursor
		JR	NZ,VT1C
		LD	HL,EOSSTR
		CALL	EMIT0
		JP	GOABS
VT1C:
		CP	'K'		;*** THE FIX *** erase to end of line, then put
		JR	NZ,VT1D		;the cursor back where MultiComp moved it from
		LD	HL,EOLSTR
		CALL	EMIT0
		JP	GOABS
VT1D:
		CP	'A'
		JR	NZ,VT1E
		LD	HL,UPSTR
		CALL	EMIT0
		CALL	ROWDEC
		JP	VTDONE
VT1E:
		CP	'B'
		JR	NZ,VT1F
		LD	HL,DOWNSTR
		CALL	EMIT0
		CALL	ROWINC
		JP	VTDONE
VT1F:
		CP	'C'		;cursor right -- measured good, sent as is
		JR	NZ,VT1G
		LD	HL,RIGHTSTR
		CALL	EMIT0
		CALL	COLINC
		JP	VTDONE
VT1G:
		CP	'D'		;cursor left as a plain backspace
		JR	NZ,VT1H
		LD	A,08h
		CALL	RAWOUT
		CALL	COLDEC
		JP	VTDONE
VT1H:
		CP	'I'
		JR	NZ,VT1J
		LD	A,ESC
		CALL	RAWOUT
		LD	A,'M'
		CALL	RAWOUT
		CALL	ROWDEC
		JP	VTDONE
VT1J:
		CP	'0'		;ANSI GOTOXY, ESC <row> ; <col> H
		JR	C,VT1K
		CP	'9'+1
		JR	NC,VT1K
		LD	A,ESC
		CALL	RAWOUT
		LD	A,'['
		CALL	RAWOUT
		LD	A,C
		CALL	RAWOUT
		LD	A,C
		SUB	'0'
		LD	(ACCUM),A
		LD	A,4
		LD	(VTSTATE),A
		JP	VTDONE
VT1K:
		JP	VTDONE		;unrecognised ESC x: drop it
;
VTS2:
		CP	2
		JR	NZ,VTS3
		LD	A,C		;ESC Y row byte, biased by 32
		SUB	32
		INC	A
		LD	(CURROW),A
		LD	A,3
		LD	(VTSTATE),A
		JP	VTDONE
VTS3:
		CP	3
		JR	NZ,VTS4
		XOR	A
		LD	(VTSTATE),A
		LD	A,C		;ESC Y column byte
		SUB	32
		INC	A
		LD	(CURCOL),A
		JP	GOABS
;
;--- states 4 and 5: pass the digits through AND record the position ------
VTS4:
		CP	4
		JR	NZ,VTS5
		LD	A,C
		CALL	RAWOUT
		CP	'0'
		JR	C,VTS4A
		CP	'9'+1
		JR	NC,VTS4A
		CALL	ACC10
		JP	VTDONE
VTS4A:
		LD	A,(ACCUM)	;the row field has ended
		LD	(CURROW),A
		LD	A,C
		CP	';'
		JR	NZ,VTS4B
		XOR	A
		LD	(ACCUM),A
		LD	A,1
		LD	(CURCOL),A	;ESC[r;...  -- column follows
		LD	A,5
		LD	(VTSTATE),A
		JP	VTDONE
VTS4B:
		XOR	A
		LD	(VTSTATE),A
		JP	VTDONE
;
VTS5:
		LD	A,C
		CALL	RAWOUT
		CP	'0'
		JR	C,VTS5A
		CP	'9'+1
		JR	NC,VTS5A
		CALL	ACC10
		JP	VTDONE
VTS5A:
		LD	A,(ACCUM)	;the column field has ended
		OR	A
		JR	NZ,VTS5B
		INC	A
VTS5B:
		LD	(CURCOL),A
		XOR	A
		LD	(VTSTATE),A
		JP	VTDONE
;
SETHOME:
		LD	A,1
		LD	(CURROW),A
		LD	(CURCOL),A
VTDONE:
		POP	HL
		POP	DE
		POP	BC
		POP	AF
		RET

;----------------------------------------------------------------------------
; GOABS -- emit ESC [ CURROW ; CURCOL H. This is what undoes MultiComp's
; unwanted homing after an erase, and serves the VT52 ESC Y form too.
;----------------------------------------------------------------------------
GOABS:
		LD	A,ESC
		CALL	RAWOUT
		LD	A,'['
		CALL	RAWOUT
		LD	A,(CURROW)
		CALL	VTNUM
		LD	A,';'
		CALL	RAWOUT
		LD	A,(CURCOL)
		CALL	VTNUM
		LD	A,'H'
		CALL	RAWOUT
		JP	VTDONE

;----------------------------------------------------------------------------
; cursor bookkeeping -- all clamp rather than wrap, except COLINC which wraps
;----------------------------------------------------------------------------
COLINC:
		LD	A,(CURCOL)
		CP	SCRCOLS
		JR	NC,COLWRAP
		INC	A
		LD	(CURCOL),A
		RET
COLWRAP:
		LD	A,1
		LD	(CURCOL),A
		JP	ROWINC
COLDEC:
		LD	A,(CURCOL)
		CP	2
		RET	C
		DEC	A
		LD	(CURCOL),A
		RET
ROWINC:
		LD	A,(CURROW)
		CP	SCRROWS
		RET	NC
		INC	A
		LD	(CURROW),A
		RET
ROWDEC:
		LD	A,(CURROW)
		CP	2
		RET	C
		DEC	A
		LD	(CURROW),A
		RET

;----------------------------------------------------------------------------
; ACC10 -- ACCUM = ACCUM*10 + (C - '0'). Preserves BC.
;----------------------------------------------------------------------------
ACC10:
		PUSH	BC
		LD	A,(ACCUM)
		ADD	A,A
		LD	B,A
		ADD	A,A
		ADD	A,A
		ADD	A,B
		LD	B,A
		LD	A,C
		SUB	'0'
		ADD	A,B
		LD	(ACCUM),A
		POP	BC
		RET

;----------------------------------------------------------------------------
; VTNUM -- print A (0..99) in decimal, no leading zero. Preserves BC.
;----------------------------------------------------------------------------
VTNUM:
		PUSH	BC
		LD	B,0
VTN1:
		CP	10
		JR	C,VTN2
		SUB	10
		INC	B
		JR	VTN1
VTN2:
		LD	C,A
		LD	A,B
		OR	A
		JR	Z,VTN3
		ADD	A,'0'
		CALL	RAWOUT
VTN3:
		LD	A,C
		ADD	A,'0'
		CALL	RAWOUT
		POP	BC
		RET

;----------------------------------------------------------------------------
; EMIT0 -- send the zero-terminated string at HL. RAWOUT preserves HL.
;----------------------------------------------------------------------------
EMIT0:
		LD	A,(HL)
		OR	A
		RET	Z
		CALL	RAWOUT
		INC	HL
		JR	EMIT0
;
HOMESTR:	DB	ESC,'[','1',';','1','H',0
EOSSTR:		DB	ESC,'[','0','J',0
EOLSTR:		DB	ESC,'[','0','K',0
UPSTR:		DB	ESC,'[','1','A',0
DOWNSTR:	DB	ESC,'[','1','B',0
RIGHTSTR:	DB	ESC,'[','1','C',0

RAWOUT:
		PUSH	AF
		PUSH	BC
		LD	C,A
		LD	A,(SAVEIOB)
		AND	3
		CP	1
		JR	Z,RAWA
RAWB:
		IN	A,(ACIA1_C)
		BIT	0,A		;a keystroke waiting? grab it rather than let
		CALL	NZ,KBGRAB	;the next one overwrite it
		IN	A,(ACIA1_C)
		BIT	1,A
		JR	Z,RAWB
		LD	A,C
		OUT	(ACIA1_D),A
		JR	RAWDN
RAWA:
		IN	A,(ACIA0_C)
		BIT	0,A		;same on channel A
		CALL	NZ,KBGRAB
		IN	A,(ACIA0_C)
		BIT	1,A
		JR	Z,RAWA
		LD	A,C
		OUT	(ACIA0_D),A
RAWDN:
		POP	BC
		POP	AF
		RET
;
MYCIN:
		LD	A,(KBTAIL)	;anything buffered? take that first
		LD	HL,KBHEAD
		CP	(HL)
		JR	NZ,KBPOP
		LD	A,(SAVEIOB)
		AND	3
		CP	1
		JR	Z,MYCIA
MYCIB:
		IN	A,(ACIA1_C)
		AND	1
		JR	Z,MYCIB
		IN	A,(ACIA1_D)
		RET
MYCIA:
		IN	A,(ACIA0_C)
		AND	1
		JR	Z,MYCIA
		IN	A,(ACIA0_D)
		RET
;
MYCST:
		LD	A,(KBTAIL)	;buffered input counts as ready
		LD	HL,KBHEAD
		CP	(HL)
		JR	Z,MYCST0
		LD	A,0FFh
		RET
MYCST0:
		LD	A,(SAVEIOB)
		AND	3
		CP	1
		JR	Z,MYCSA
MYCSB:
		IN	A,(ACIA1_C)
		AND	1
		RET	Z
		LD	A,0FFh
		RET
MYCSA:
		IN	A,(ACIA0_C)
		AND	1
		RET	Z
		LD	A,0FFh
		RET
;
;----------------------------------------------------------------------------
; KBGRAB -- a character is waiting: read it and ring-buffer it.
; Called from inside the TX wait loop, so it must preserve BC, DE and HL.
;----------------------------------------------------------------------------
KBGRAB:
		PUSH	BC
		PUSH	DE
		PUSH	HL
		LD	A,(SAVEIOB)
		AND	3
		CP	1
		JR	Z,KGA
		IN	A,(ACIA1_D)
		JR	KGST
KGA:
		IN	A,(ACIA0_D)
KGST:
		LD	C,A		;the character
		LD	A,(KBTAIL)
		LD	E,A		;E = slot to write
		INC	A
		AND	15
		LD	B,A		;B = tail after the write
		LD	A,(KBHEAD)
		CP	B
		JR	Z,KGDONE	;ring full: discard the newest
		LD	A,B
		LD	(KBTAIL),A
		LD	H,0
		LD	L,E
		LD	DE,KBBUF
		ADD	HL,DE
		LD	(HL),C
KGDONE:
		POP	HL
		POP	DE
		POP	BC
		RET
;
KBPOP:
		PUSH	DE
		PUSH	HL
		LD	A,(KBHEAD)
		LD	E,A
		INC	A
		AND	15
		LD	(KBHEAD),A
		LD	H,0
		LD	L,E
		LD	DE,KBBUF
		ADD	HL,DE
		LD	A,(HL)
		POP	HL
		POP	DE
		RET
;
SHIMEND:
