;==================================================================================
; SECBOOT for MultiComp -- v32 -- FAULT 4 RETEST: LEFT-MOVE AT COLUMN 0/1.
; Does NOT boot. Built on the v30 template (identical boot stub and ACIA
; helpers, unreachable boot-loader body kept only for structural parity).
;
; CORE_TERMINAL_FAULTS.md's primary candidate for the "+1,+1,-1,+3" wobble:
; the shim (SHIM_MULTICOMP_v29.ASM) sends cursor-left as a raw 08h backspace,
; not ESC[1D -- because the v24 probe found ESC[1D "misbehaves" and BS was the
; known-good alternative. But MultiComp's backspace at column 0 used to WRAP to
; the end of the previous line, and until today's fix it was also destructive
; (Fault 2). The shim's own COLDEC clamps its tracked column at 1 and never
; checks before sending the raw 08h, so a left-move issued at column 0 would
; desync the shim's belief about the cursor from where hardware actually put
; it -- by exactly one row. That desync, silently corrected by the next
; absolute reposition, is a source-grounded explanation for "net movement
; correct, intermediate positions not".
;
; Fault 2 (destructive backspace) and the column-0 wrap are now both fixed at
; source: backspace now clamps at column 0 instead of wrapping.
;
; THREE SCREENS. Press a key to advance. Each starts fresh.
;
;   SCREEN 1  raw 08h at column 1 (row 3, the CCCC row)
;             fixed   = row 3 reads @CCCCCCCCC, row 2 (BBBB) untouched
;             old bug = cursor wrapped to row 2 end; @ appears far right of
;                       row 2 instead
;   SCREEN 2  ESC[1D at column 1 (row 4, the DDDD row) -- sanity check; this
;             handler was never implicated, should already clamp correctly
;             worked  = row 4 reads @DDDDDDDDD
;             wrapped = @ appears on row 3 instead
;   SCREEN 3  ESC[1D from mid-line (row 5, the EEEE row): one single step,
;             then a fresh reposition and three consecutive single steps --
;             re-tests the original v24 "landed to the right" finding, which
;             predates the Fault 1 discovery and may have been corrupted by it
;             worked  = row 5 reads EEE#E*EEEE (# at col 4, * at col 6)
;             drifted = # or * land somewhere else
;
; Report, per screen: where the marker is, and which other rows survived.

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
		JP	TERMTEST	;*** v32: probe and stop. Nothing is booted. ***
					;(the real SECBOOT's disk/relocate/handoff code
					; that used to follow here is unreachable behind
					; that jump, and has been dropped to fit 1024
					; bytes with an extra test screen added.)

;==================================================================================
; v32 TERMINAL PROBE -- LEFT-MOVE AT THE COLUMN 0/1 EDGE
;==================================================================================
TERMTEST:
;--- screen 1: raw 08h at column 1, row 3 -----------------------------------
		LD	HL,TTCLR
		CALL	TTSTR
		CALL	BIGDLY
		LD	HL,TTROWS
		CALL	TTSTR
		LD	HL,TTBS1
		CALL	TTSTR
		LD	HL,TTAT
		CALL	TTSTR
		LD	HL,TTLEGBS
		CALL	TTSTR
		LD	HL,TTCOMMBS
		CALL	TTSTR
		CALL	TTIN
;--- screen 2: ESC[1D at column 1, row 4 ------------------------------------
		LD	HL,TTCLR
		CALL	TTSTR
		CALL	BIGDLY
		LD	HL,TTROWS
		CALL	TTSTR
		LD	HL,TTD1
		CALL	TTSTR
		LD	HL,TTAT
		CALL	TTSTR
		LD	HL,TTLEGD1
		CALL	TTSTR
		LD	HL,TTCOMMD1
		CALL	TTSTR
		CALL	TTIN
;--- screen 3: ESC[1D mid-line, single then triple, row 5 -------------------
		LD	HL,TTCLR
		CALL	TTSTR
		CALL	BIGDLY
		LD	HL,TTROWS
		CALL	TTSTR
		LD	HL,TTDSINGLE
		CALL	TTSTR
		LD	HL,TTHASH
		CALL	TTSTR
		LD	HL,TTDTRIPLE
		CALL	TTSTR
		LD	HL,TTSTAR
		CALL	TTSTR
		LD	HL,TTLEGD3
		CALL	TTSTR
		LD	HL,TTCOMMD3
		CALL	TTSTR
		CALL	TTIN
TTHANG:
		JP	TTHANG

;--- the identical setup used by all three screens --------------------------
TTROWS:
		DB	ESC,'[','1',';','1','H',"AAAAAAAAAA"
		DB	ESC,'[','2',';','1','H',"BBBBBBBBBB"
		DB	ESC,'[','3',';','1','H',"CCCCCCCCCC"
		DB	ESC,'[','4',';','1','H',"DDDDDDDDDD"
		DB	ESC,'[','5',';','1','H',"EEEEEEEEEE",0
;--- screen 1 data: row 3 column 1, then raw backspace ----------------------
TTBS1:
		DB	ESC,'[','3',';','1','H',08h,0
TTLEGBS:
		DB	ESC,'[','8',';','1','H',"1 OF 3  RAW 08h AT COLUMN 1",0
TTCOMMBS:
		DB	ESC,'[','9',';','1','H',"ROW3=@CCCCCCCCC IF CLAMPED.  @ FAR RIGHT OF ROW2 IF WRAPPED",0
;--- screen 2 data: row 4 column 1, then ESC[1D -----------------------------
TTD1:
		DB	ESC,'[','4',';','1','H',ESC,'[','1','D',0
TTLEGD1:
		DB	ESC,'[','8',';','1','H',"2 OF 3  ESC[1D AT COLUMN 1",0
TTCOMMD1:
		DB	ESC,'[','9',';','1','H',"ROW4=@DDDDDDDDD EXPECTED.  ANYTHING ON ROW3 IS A BUG",0
;--- screen 3 data: row 5, single step then triple step ---------------------
TTDSINGLE:
		DB	ESC,'[','5',';','5','H',ESC,'[','1','D',0
TTHASH:
		DB	"#",0
TTDTRIPLE:
		DB	ESC,'[','5',';','9','H',ESC,'[','1','D',ESC,'[','1','D',ESC,'[','1','D',0
TTSTAR:
		DB	"*",0
TTLEGD3:
		DB	ESC,'[','8',';','1','H',"3 OF 3  ESC[1D SINGLE AND TRIPLE",0
TTCOMMD3:
		DB	ESC,'[','9',';','1','H',"EXPECT EEE#E*EEEE ON ROW5 -- # AT COL4, * AT COL6",0
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
