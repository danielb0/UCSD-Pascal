;==================================================================================
; SECBOOT for MultiComp -- v31 -- FAULT 3 RETEST: BARE PARAMETERLESS FORMS.
; Does NOT boot. Built on the v30 template (identical boot stub and ACIA
; helpers, unreachable boot-loader body kept only for structural parity).
;
; TERMINAL.md's original v9 probe reported ESC[H, ESC[K, ESC[J and ESC[2J all
; "ignored" -- everything needs an explicit parameter. CORE_TERMINAL_FAULTS.md's
; source read says otherwise: the parser sets paramCount=1/param1=0 identically
; whether or not a digit arrives, so ESC[K and ESC[0K cannot behave differently,
; and ESC[2J already carries an explicit '2' so it was never actually ambiguous.
; The retraction rests on the theory that v9's screen was corrupted by the
; not-yet-discovered Fault 1 (ESC[0K's homing) at measurement time.
;
; Fault 1 and Fault 2 (destructive backspace) are now fixed at source. This is
; the first real-hardware test of the four bare forms since v9, on a core that
; no longer has the confound that likely produced the original "ignored" result.
;
; FOUR SCREENS, one per form. Press a key to advance. Each starts fresh.
;
;   SCREEN 1  ESC[H   (bare)   worked  = @ appears at row 1 col 1 (homed)
;                                ignored = @ stays at row 4 col 6 (untouched)
;   SCREEN 2  ESC[K   (bare)   worked  = row 3 reads CCCC@, rows 1 2 4 5 intact
;                                ignored = row 3 still reads CCCCCCCCCC
;   SCREEN 3  ESC[J   (bare)   worked  = rows 4 5 gone, row 3 reads CCCC@
;                                ignored = all five rows intact
;   SCREEN 4  ESC[2J           worked  = whole screen blank, @ at row 1 col 1
;                                ignored = all five rows intact
;
; Report, per screen: where is the @, and which rows survived.

FIRSTBLOCK	EQU	2		;p-System directory starts at block 2
DIRBLOCKS	EQU	4		;directory occupies blocks 2..5
ENTRYSIZE	EQU	26
NAMEOFFSET	EQU	6
NAMEFIELDLEN	EQU	14		;length byte + "SYSTEM.INTERP"
MAXENTRIES	EQU	77

PSYSDRV		EQU	15
BOOTUNIT	EQU	4		;p-System boot unit

SHIMDEST	EQU	0E200h		;where the shim runs (above TOPRAM)
SHIMSRC		EQU	8200h+1024	;its image slot in the loaded window
SHIMLEN		EQU	1024		;v21: raised for the cursor-tracking shim (v9)
SHIMREAL	EQU	SHIMDEST+51	;shim's REALBIOS word (0E233h)
SHIMIOB		EQU	SHIMDEST+53	;shim's SAVEIOB byte  (0E235h)
NEWTOP		EQU	SHIMDEST	;TOPRAM before the carve

IOBYTE		EQU	0003h
DIRBUF		EQU	9800h		;scratch, used only before the handoff
SCRATCH		EQU	9000h

INTERPBASEV	EQU	SCRATCH+0
SBIOSADDRV	EQU	SCRATCH+2
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
SAVEIOB		EQU	SCRATCH+38

ESC		EQU	1Bh
ACIA0_C		EQU	80h
ACIA0_D		EQU	81h
ACIA1_C		EQU	82h
ACIA1_D		EQU	83h

CR		EQU	0Dh
LF		EQU	0Ah
EOM		EQU	'$'
BDOS		EQU	0005h
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
; --- capture iobyte before the interpreter load destroys page zero ---
		LD	A,(IOBYTE)
		LD	(SAVEIOB),A
;
		JP	TERMTEST	;*** v31: probe and stop. Nothing is booted. ***
					;(the real SECBOOT's disk/relocate/handoff code
					; that used to follow here is unreachable behind
					; that jump, and has been dropped to fit 1024
					; bytes with a fourth test screen added.)

;==================================================================================
; v31 TERMINAL PROBE -- BARE PARAMETERLESS FORMS
;==================================================================================
TERMTEST:
;--- screen 1: bare ESC[H --------------------------------------------------
		LD	HL,TTCLR
		CALL	TTSTR
		CALL	BIGDLY
		LD	HL,TTROWS
		CALL	TTSTR
		LD	HL,TTPOSH
		CALL	TTSTR
		LD	HL,TTAT
		CALL	TTSTR
		LD	HL,TTLEGH
		CALL	TTSTR
		LD	HL,TTCOMMH
		CALL	TTSTR
		CALL	TTIN
;--- screen 2: bare ESC[K --------------------------------------------------
		LD	HL,TTCLR
		CALL	TTSTR
		CALL	BIGDLY
		LD	HL,TTROWS
		CALL	TTSTR
		LD	HL,TTERK
		CALL	TTSTR
		LD	HL,TTAT
		CALL	TTSTR
		LD	HL,TTLEGK
		CALL	TTSTR
		LD	HL,TTCOMMK
		CALL	TTSTR
		CALL	TTIN
;--- screen 3: bare ESC[J --------------------------------------------------
		LD	HL,TTCLR
		CALL	TTSTR
		CALL	BIGDLY
		LD	HL,TTROWS
		CALL	TTSTR
		LD	HL,TTERJ
		CALL	TTSTR
		LD	HL,TTAT
		CALL	TTSTR
		LD	HL,TTLEGJ
		CALL	TTSTR
		LD	HL,TTCOMMJ
		CALL	TTSTR
		CALL	TTIN
;--- screen 4: ESC[2J -------------------------------------------------------
		LD	HL,TTCLR
		CALL	TTSTR
		CALL	BIGDLY
		LD	HL,TTROWS
		CALL	TTSTR
		LD	HL,TTER2J
		CALL	TTSTR
		LD	HL,TTAT
		CALL	TTSTR
		LD	HL,TTLEG2J
		CALL	TTSTR
		LD	HL,TTCOMM2J
		CALL	TTSTR
		CALL	TTIN
TTHANG:
		JP	TTHANG

;--- the identical setup used by all four screens --------------------------
TTROWS:
		DB	ESC,'[','1',';','1','H',"AAAAAAAAAA"
		DB	ESC,'[','2',';','1','H',"BBBBBBBBBB"
		DB	ESC,'[','3',';','1','H',"CCCCCCCCCC"
		DB	ESC,'[','4',';','1','H',"DDDDDDDDDD"
		DB	ESC,'[','5',';','1','H',"EEEEEEEEEE",0
;--- screen 1 data: position off-home, then bare ESC[H ---------------------
TTPOSH:
		DB	ESC,'[','4',';','6','H',ESC,'[','H',0
TTLEGH:
		DB	ESC,'[','8',';','1','H',"1 OF 4  ESC[H (bare)",0
TTCOMMH:
		DB	ESC,'[','9',';','1','H',"@ AT 1,1 = HOMED.  @ AT 4,6 = IGNORED",0
;--- screen 2 data: mid row 3, then bare ESC[K ------------------------------
TTERK:
		DB	ESC,'[','3',';','5','H',ESC,'[','K',0
TTLEGK:
		DB	ESC,'[','8',';','1','H',"2 OF 4  ESC[K (bare)",0
TTCOMMK:
		DB	ESC,'[','9',';','1','H',"ROW3=CCCC@ IF ERASED.  ROW3=CCCCCCCCCC IF IGNORED",0
;--- screen 3 data: mid row 3, then bare ESC[J ------------------------------
TTERJ:
		DB	ESC,'[','3',';','5','H',ESC,'[','J',0
TTLEGJ:
		DB	ESC,'[','8',';','1','H',"3 OF 4  ESC[J (bare)",0
TTCOMMJ:
		DB	ESC,'[','9',';','1','H',"ROWS 4,5 GONE + ROW3=CCCC@ IF ERASED.  ALL INTACT IF IGNORED",0
;--- screen 4 data: mid row 3, then ESC[2J ----------------------------------
TTER2J:
		DB	ESC,'[','3',';','5','H',ESC,'[','2','J',0
TTLEG2J:
		DB	ESC,'[','8',';','1','H',"4 OF 4  ESC[2J",0
TTCOMM2J:
		DB	ESC,'[','9',';','1','H',"SCREEN BLANK + @ AT 1,1 IF ERASED.  ALL INTACT IF IGNORED",0
;--- one character, NO positioning ------------------------------------------
TTAT:
		DB	"@",0
;
TTCLR:
		DB	ESC,'[','1',';','1','H',ESC,'[','0','J',0


;--- raw ACIA helpers ------------------------------------------------------
TTSTR:
		LD	A,(HL)
		OR	A
		RET	Z
		CALL	TTOUT
		INC	HL
		JR	TTSTR
TTOUT:
		PUSH	AF
		PUSH	BC
		LD	C,A
		LD	A,(SAVEIOB)
		AND	3
		CP	1
		JR	Z,TTOA
TTOB:
		IN	A,(ACIA1_C)
		BIT	1,A
		JR	Z,TTOB
		LD	A,C
		OUT	(ACIA1_D),A
		JR	TTODN
TTOA:
		IN	A,(ACIA0_C)
		BIT	1,A
		JR	Z,TTOA
		LD	A,C
		OUT	(ACIA0_D),A
TTODN:
		POP	BC
		POP	AF
		RET
TTIN:
		LD	A,(SAVEIOB)
		AND	3
		CP	1
		JR	Z,TTIA
TTIB:
		IN	A,(ACIA1_C)
		AND	1
		JR	Z,TTIB
		IN	A,(ACIA1_D)
		RET
TTIA:
		IN	A,(ACIA0_C)
		AND	1
		JR	Z,TTIA
		IN	A,(ACIA0_D)
		RET
BIGDLY:
		PUSH	BC
		LD	B,0
BD1:
		PUSH	BC
		LD	B,0
BD2:
		DJNZ	BD2
		POP	BC
		DJNZ	BD1
		POP	BC
		RET
