;==================================================================================
; SBIOS SHIM v14-DIAG = v10 EXACTLY, plus ONE line: outgoing ESC prints as '~'.
; Not a production shim.
;
; v13-DIAG was built on v12, which had never run on hardware, so when it hung
; it told us nothing about the question being asked. This is built on v10 --
; the build whose misbehaviour we are actually chasing, and which boots.
;
; Everything below is v10 byte for byte. The only change is in RAWOUT: an
; outgoing ESC is printed as '~' rather than sent. The screen therefore shows
; the literal byte stream MultiComp is being handed. Nothing positions or
; erases, so it scrolls like a teletype.
;
; EXPECTED, if my simulation of v10 is right, the ctrl-C redraw reads:
;   ~[3;1HGJD~[3;1H~[0J~[3;1HGJD~[1;1H~[1;1H~[0K)Edit: ...~[3;4H
; -- every sequence with explicit parameters, and the menu emitted straight
; after a home. If that is what appears, the shim is doing its job and
; MultiComp is mishandling a form it accepted when probed in isolation.
; If anything else appears, the bug is mine and it will be on the screen.
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
		JP	Z,VTDONE	;NUL: discard IN EVERY STATE. See (1) in the header --
					;a pad byte landing here in state 1 was being taken
					;as the command letter and wrecking the sequence.
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
		CP	0Ch		;form feed = erase screen
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
		LD	A,C
		CALL	RAWOUT
		JP	VTDONE
VT0C:
		CP	0Ah		;LF
		JR	NZ,VT0D
		CALL	ROWINC
		LD	A,C
		CALL	RAWOUT
		JP	VTDONE
VT0D:
		CP	08h		;BS = cursor left, works natively
		JR	NZ,VT0E
		CALL	COLDEC
		LD	A,C
		CALL	RAWOUT
		JP	VTDONE
VT0E:
		CP	20h		;other control codes: pass, no tracking
		JR	C,VT0PASS
		CALL	COLINC		;printable: advances the cursor
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
		CP	'Y'		;VT52 absolute addressing
		JR	NZ,VT1A
		LD	A,2
		LD	(VTSTATE),A
		JP	VTDONE
VT1A:
		CP	'H'		;home
		JR	NZ,VT1B
		LD	HL,HOMESTR
		CALL	EMIT0
		JP	SETHOME
VT1B:
		CP	'J'		;erase to end of screen
		JR	NZ,VT1C
		LD	HL,EOSSTR
		CALL	EMIT0
		JP	VTDONE
VT1C:
		CP	'K'		;erase to end of line
		JR	NZ,VT1D
		LD	HL,EOLSTR
		CALL	EMIT0
		JP	VTDONE
VT1D:
		CP	'A'		;cursor up -- ESC[1A works
		JR	NZ,VT1E
		LD	HL,UPSTR
		CALL	EMIT0
		LD	A,(CURROW)
		CP	2
		JP	C,VTDONE	;JP, not JR -- VTDONE is out of JR range
		DEC	A
		LD	(CURROW),A
		JP	VTDONE
VT1E:
		CP	'B'		;cursor down
		JR	NZ,VT1F
		LD	HL,DOWNSTR
		CALL	EMIT0
		CALL	ROWINC
		JP	VTDONE
VT1F:
		CP	'C'		;cursor right: MultiComp cannot do it, so
		JR	NZ,VT1G		;synthesise from absolute positioning
		CALL	COLINC
		JP	GOABS
VT1G:
		CP	'D'		;cursor left: likewise
		JR	NZ,VT1H
		CALL	COLDEC
		JP	GOABS
VT1H:
		CP	'I'		;VT52 reverse line feed -> ANSI RI
		JR	NZ,VT1J
		LD	A,ESC
		CALL	RAWOUT
		LD	A,'M'
		CALL	RAWOUT
		JP	VTDONE
VT1J:
		CP	'0'		;a digit: the ANSI GOTOXY, ESC <row> ; <col> H.
		JR	C,VT1K		;Emit ESC [ and parse so tracking stays right.
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
		LD	A,ESC		;anything else: ESC x -> ESC [ x
		CALL	RAWOUT
		LD	A,'['
		CALL	RAWOUT
		LD	A,C
		CALL	RAWOUT
		JP	VTDONE
;
VTS2:
		CP	2
		JR	NZ,VTS3
		LD	A,C		;ESC Y: row byte, biased by 32
		SUB	32
		LD	(VTROW),A
		LD	A,3
		LD	(VTSTATE),A
		JP	VTDONE
VTS3:
		CP	3
		JR	NZ,VTS4
		XOR	A		;ESC Y: column byte
		LD	(VTSTATE),A
		LD	A,(VTROW)
		INC	A
		LD	(CURROW),A
		LD	A,C
		SUB	32
		INC	A
		LD	(CURCOL),A
		JP	GOABS
;
VTS4:
		CP	4
		JR	NZ,VTS5
		LD	A,C		;GOTOXY: gathering row digits
		CP	'0'
		JR	C,VTS4A
		CP	'9'+1
		JR	NC,VTS4A
		CALL	ACC10		;ACCUM = ACCUM*10 + digit
		LD	A,C
		CALL	RAWOUT
		JP	VTDONE
VTS4A:
		LD	A,(ACCUM)	;a non-digit ends the row field
		LD	(CURROW),A
		LD	A,C
		CALL	RAWOUT
		LD	A,C
		CP	';'
		JR	NZ,VTS4B
		XOR	A
		LD	(ACCUM),A
		LD	A,5
		LD	(VTSTATE),A
		JP	VTDONE
VTS4B:
		XOR	A
		LD	(VTSTATE),A
		JP	VTDONE
;
VTS5:
		LD	A,C		;GOTOXY: gathering column digits
		CP	'0'
		JR	C,VTS5A
		CP	'9'+1
		JR	NC,VTS5A
		CALL	ACC10
		LD	A,C
		CALL	RAWOUT
		JP	VTDONE
VTS5A:
		LD	A,(ACCUM)	;a non-digit ends it: position now known
		LD	(CURCOL),A
		XOR	A
		LD	(VTSTATE),A
		LD	A,C
		CALL	RAWOUT
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
; ACC10 -- ACCUM = ACCUM*10 + (C - '0'). Preserves BC.
;----------------------------------------------------------------------------
ACC10:
		PUSH	BC
		LD	A,(ACCUM)
		ADD	A,A		;x2
		LD	B,A
		ADD	A,A		;x4
		ADD	A,A		;x8
		ADD	A,B		;x10
		LD	B,A
		LD	A,C
		SUB	'0'
		ADD	A,B
		LD	(ACCUM),A
		POP	BC
		RET

;----------------------------------------------------------------------------
; GOABS -- emit ESC [ CURROW ; CURCOL H, for the moves MultiComp cannot do.
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
; Cursor bookkeeping. All clamp rather than wrap.
;----------------------------------------------------------------------------
COLINC:
		LD	A,(CURCOL)
		CP	SCRCOLS
		JR	NC,COLWRAP	;at the margin: MultiComp wraps, so we must too
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

;----------------------------------------------------------------------------
; VTNUM -- print A (0..99) as decimal, no leading zero. Preserves BC.
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

;==================================================================================
; RAWOUT / MYCIN / MYCST -- direct ACIA. Channel from the captured iobyte:
; (iobyte AND 3) == 1 selects channel A, else channel B.
; Status bits: D0 = RX ready, D1 = TX empty.
;==================================================================================
RAWOUT:
		PUSH	AF
		PUSH	BC
		CP	ESC		;*** v14-DIAG ONLY: render outgoing ESC as '~' ***
		JR	NZ,RWVIS
		LD	A,'~'
RWVIS:
		LD	C,A
		LD	A,(SAVEIOB)
		AND	3
		CP	1
		JR	Z,RAWA
RAWB:
		IN	A,(ACIA1_C)
		BIT	1,A
		JR	Z,RAWB
		LD	A,C
		OUT	(ACIA1_D),A
		JR	RAWDN
RAWA:
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
SHIMEND:
