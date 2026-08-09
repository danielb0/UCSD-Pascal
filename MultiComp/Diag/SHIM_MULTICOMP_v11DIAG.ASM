;==================================================================================
; SBIOS SHIM v11-DIAG -- TRANSCRIPT MODE, WITH NULS VISIBLE. Not production.
;
; Purpose: show LITERALLY what the editor emits, with no translation and no
; positioning whatsoever, so we can read the byte stream off the screen instead
; of guessing at it. Everything flows down the screen like a teletype, so
; nothing is ever erased or overwritten.
;
;   ESC (1Bh)        -> '~'      so escape sequences become readable text
;   0Ch  (form feed) -> '@'      shown, NOT acted on
;   00h              -> '.'      *** THE POINT OF THIS BUILD ***
;                                v10-DIAG discarded these, which hid exactly
;                                the thing we need to see: WHERE the five pad
;                                bytes fall relative to the ESC. If they sit
;                                between ESC and its command letter we will
;                                see '~.....H'; if they follow the whole
;                                sequence we will see '~H.....'.
;   CR / LF          -> passed, so lines break naturally
;   other ctrl codes -> '^'      shown without side effects
;   printable        -> passed
;
; WHAT TO LOOK FOR, entering the editor:
;   ~.....H or ~.....1;1H   padding sits INSIDE the sequence
;   ~H..... or ~1;1H.....   padding follows the sequence
;
; Type only a few characters before <etx> so the whole exchange fits on one
; screen -- NULs are now printed, so the transcript is five times denser.
;
; The disk half below is byte-for-byte the proven v9 code. Only MYCOUT differs.
;==================================================================================

SHIMBASE	EQU	0E200h
PSYSDRV		EQU	15

ACIA0_C		EQU	80h
ACIA0_D		EQU	81h
ACIA1_C		EQU	82h
ACIA1_D		EQU	83h

ESC		EQU	1Bh
SCRROWS		EQU	24
SCRCOLS		EQU	80

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
; MYCOUT -- transcript mode. Character in A. Preserves all registers.
;==================================================================================
MYCOUT:
		PUSH	AF
		PUSH	BC
		PUSH	DE
		PUSH	HL
		LD	C,A
		OR	A
		JR	NZ,DG0
		LD	A,'.'		;NUL: SHOW it -- this is what v10-DIAG hid
		CALL	RAWOUT
		JP	DGDONE
DG0:
		LD	A,C
		CP	ESC
		JR	NZ,DG1
		LD	A,'~'
		CALL	RAWOUT
		JP	DGDONE
DG1:
		CP	0Ch
		JR	NZ,DG2
		LD	A,'@'		;show the clear, do not perform it
		CALL	RAWOUT
		JP	DGDONE
DG2:
		CP	0Dh
		JR	Z,DGPASS
		CP	0Ah
		JR	Z,DGPASS
		CP	20h
		JR	NC,DGPASS
		LD	A,'^'		;any other control code, shown inertly
		CALL	RAWOUT
		JP	DGDONE
DGPASS:
		LD	A,C
		CALL	RAWOUT
DGDONE:
		POP	HL
		POP	DE
		POP	BC
		POP	AF
		RET

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
