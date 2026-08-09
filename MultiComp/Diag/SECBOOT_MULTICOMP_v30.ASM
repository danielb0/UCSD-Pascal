;==================================================================================
; SECBOOT for MultiComp -- v30 -- WHAT DO THE ERASES ACTUALLY DO? Does NOT boot.
; (v29 was the same test but 1146 bytes, over the 1024 SECBOOT limit, because it
; carried three near-identical legend blocks. v30 shares the common part.)
;
; v28 wrote SHORT three times, to rows 3, 5 and 7, and never wrote anything to
; row 1. The screen came back with ONE SHORT at the top and every X gone. That
; is only possible if ESC[0K clears far more than one line AND leaves the cursor
; at home, so all three SHORTs landed on row 1 on top of each other.
;
; This measures what each erase variant does to the SCREEN and to the CURSOR.
; ESC[2K matters most: the editor always erases from column 1, so "erase the
; whole line" would do the same job, and if it is the one implemented correctly
; the shim fix is a single string.
;
; THREE SCREENS, one per variant. Press a key to advance. Each starts fresh, so
; a destructive variant cannot corrupt the next test.
;
; Every screen is set up identically: rows 1 to 5 hold ten identical letters
; each (AAAA.. BBBB.. CCCC.. DDDD.. EEEE..), the cursor is put in the MIDDLE of
; row 3 at column 5, the erase is issued, and a single '@' is written with NO
; positioning in between -- so wherever the '@' lands IS the cursor position the
; erase left behind.
;
;   SCREEN 1  ESC[0K   correct = row 3 reads CCCC@   rows 1 2 4 5 untouched
;   SCREEN 2  ESC[2K   correct = row 3 reads    @    (blank before the @,
;                      since the whole line goes)    rows 1 2 4 5 untouched
;   SCREEN 3  ESC[1K   correct = row 3 reads    @CCCCC  (first 5 cols cleared)
;
; For each screen report WHERE THE @ IS and WHICH ROWS SURVIVED. If any variant
; leaves rows 1 2 4 5 alone and only alters row 3, that is the one to use.

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
		JP	TERMTEST	;*** v22: probe and stop. Nothing is booted. ***
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
; --- relocate the shim to 0E300h and give it what it needs ---
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
		LD	A,(SAVEIOB)
		LD	(SHIMIOB),A
;
; --- read the directory (blocks 2..5) ---
		LD	HL,FIRSTBLOCK
		LD	(CURBLOCK),HL
		LD	HL,DIRBUF
		LD	(CURDEST),HL
		LD	A,DIRBLOCKS
		LD	(BLOCKSLEFT),A
		CALL	READMANY
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
		LD	HL,(STARTBLOCK)
		LD	(CURBLOCK),HL
		LD	HL,(INTERPBASEV)
		LD	(CURDEST),HL
		CALL	READMANY	;<-- page zero dies here
;
;==================================================================================
; Force TOPRAM down to the shim's base, then carve the sector table and
; sector buffer below it exactly as the real tertbot does.
;==================================================================================
		LD	HL,NEWTOP
		LD	(TOPRAMV),HL
;
		LD	HL,(TOPRAMV)
		LD	DE,(MAXSECTORSV)
		OR	A
		SBC	HL,DE
		LD	(MAXSECTORSV),HL ;sector-table ADDRESS
;
		LD	DE,(MAXBYTESV)
		OR	A
		SBC	HL,DE
		LD	(MAXBYTESV),HL	;sector-buffer ADDRESS (unaligned, as reference)
;
		LD	A,L
		AND	0FEh
		LD	L,A
		LD	(TOPRAMV),HL
		LD	SP,HL
;
;==================================================================================
; 12 parameters, then the boot unit on top: the 13 words the interpreter's
; cold start at 243Bh consumes. SBIOSADDR is the relocated shim.
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
		LD	HL,SHIMDEST+3
		PUSH	HL
		LD	HL,(INTERPBASEV)
		PUSH	HL
		LD	HL,BOOTUNIT
		PUSH	HL
;
		LD	HL,(INTERPBASEV)
		LD	DE,0200h
		ADD	HL,DE
		JP	(HL)		;INTERPBASE+0200h
;
NOTFOUND:
		LD	DE,NOTFOUNDMSG
		CALL	MESSAGEOUT	;BDOS is still valid -- nothing loaded yet
HANGLOOP:
		JP	HANGLOOP
;
;==================================================================================
; READMANY / READBLOCK
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
READBLOCK:
		LD	(DESTPTR),DE
		ADD	HL,HL		;block * 4 = absolute logical sector
		ADD	HL,HL
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
		LD	B,4
RB_LOOP:
		PUSH	BC
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
		LD	HL,(DESTPTR)
		LD	DE,128
		ADD	HL,DE
		LD	(DESTPTR),HL
		LD	A,(CURSECTOR)
		INC	A
		LD	(CURSECTOR),A
		POP	BC
		DJNZ	RB_LOOP
		RET
;
; SECBOOT's own CBIOS access -- straight to the real thing, never the shim.
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
READ:
		LD	E,27h-03h
BIOSJMP:
		LD	D,0
		LD	HL,(SBIOSADDRV)
		ADD	HL,DE
		JP	(HL)
;
MESSAGEOUT:
		LD	C,WRBUF
		JP	BDOS
;
TARGETNAME:
		DB	13,"SYSTEM.INTERP"
;
NOTFOUNDMSG:
		DB	CR,LF,"SYSTEM.INTERP NOT FOUND ON P: -- HALTED",CR,LF,EOM


;==================================================================================
; v22 TERMINAL PROBE
;==================================================================================
TERMTEST:
;--- screen 1: ESC[0K ----------------------------------------------------
		LD	HL,TTCLR
		CALL	TTSTR
		CALL	BIGDLY
		LD	HL,TTROWS
		CALL	TTSTR
		LD	HL,TTER0
		CALL	TTSTR
		LD	HL,TTAT
		CALL	TTSTR
		LD	HL,TTLEG0
		CALL	TTSTR
		LD	HL,TTCOMM
		CALL	TTSTR
		CALL	TTIN
;--- screen 2: ESC[2K ----------------------------------------------------
		LD	HL,TTCLR
		CALL	TTSTR
		CALL	BIGDLY
		LD	HL,TTROWS
		CALL	TTSTR
		LD	HL,TTER2
		CALL	TTSTR
		LD	HL,TTAT
		CALL	TTSTR
		LD	HL,TTLEG2
		CALL	TTSTR
		LD	HL,TTCOMM
		CALL	TTSTR
		CALL	TTIN
;--- screen 3: ESC[1K ----------------------------------------------------
		LD	HL,TTCLR
		CALL	TTSTR
		CALL	BIGDLY
		LD	HL,TTROWS
		CALL	TTSTR
		LD	HL,TTER1
		CALL	TTSTR
		LD	HL,TTAT
		CALL	TTSTR
		LD	HL,TTLEG1
		CALL	TTSTR
		LD	HL,TTCOMM
		CALL	TTSTR
		CALL	TTIN
TTHANG:
		JP	TTHANG

;--- the identical setup used by all three screens ------------------------
TTROWS:
		DB	ESC,'[','1',';','1','H',"AAAAAAAAAA"
		DB	ESC,'[','2',';','1','H',"BBBBBBBBBB"
		DB	ESC,'[','3',';','1','H',"CCCCCCCCCC"
		DB	ESC,'[','4',';','1','H',"DDDDDDDDDD"
		DB	ESC,'[','5',';','1','H',"EEEEEEEEEE",0
;--- cursor to the middle of row 3, then the erase under test -------------
TTER0:
		DB	ESC,'[','3',';','5','H',ESC,'[','0','K',0
TTER2:
		DB	ESC,'[','3',';','5','H',ESC,'[','2','K',0
TTER1:
		DB	ESC,'[','3',';','5','H',ESC,'[','1','K',0
;--- one character, NO positioning ----------------------------------------
TTAT:
		DB	"@",0
;
TTCLR:
		DB	ESC,'[','1',';','1','H',ESC,'[','0','J',0
TTLEG0:
		DB	ESC,'[','8',';','1','H',"1 OF 3  ESC[0K",0
TTLEG2:
		DB	ESC,'[','8',';','1','H',"2 OF 3  ESC[2K",0
TTLEG1:
		DB	ESC,'[','8',';','1','H',"3 OF 3  ESC[1K",0
TTCOMM:
		DB	ESC,'[','9',';','1','H',"WHERE IS @  WHICH ROWS LIVE",0


;--- raw ACIA helpers ----------------------------------------------------
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
