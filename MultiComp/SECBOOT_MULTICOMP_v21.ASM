;==================================================================================
; SECBOOT for MultiComp -- v21 -- SHIM REGION MOVED TO E200h, SHIMLEN 1024
;
; v21 = v17 with the shim's home enlarged: SHIMDEST E300h -> E200h and
; SHIMLEN 640 -> 1024, because SHIM v9 adds cursor tracking and outgrew the
; old allowance. The region E200h..E5FFh is 1024 bytes; the image slot in the
; loaded window has 2176-1024 = 1152 available. Carving from NEWTOP = E200h
; gives buffer E100h, table E180h, TOPRAM E100h, leaving the p-System 43776
; bytes -- 256 less than before, which it has to spare.
;
; No probe in this version -- it is the production loader again.
;
; PAIRS WITH PASBOOT v16 and SHIM_MULTICOMP_v2.ASM (assembled at ORG 0E300h).
;
; Functionally identical to v16. Removed: the '#' and '@' markers, the
; "IOB=.. SHIM AT ..", "SEARCHING FOR SYSTEM.INTERP" and "LOADING
; INTERPRETER" lines, the three memory dumps and the "STARTING" line.
; SECBOOT is now silent on success; only the "SYSTEM.INTERP not found"
; failure still speaks.
;
; The load and handoff are unchanged, and every part of them was established
; on hardware:
;   * the interpreter loads at 0000h and is entered at 0200h
;   * 13 words are pushed -- the 12 parameters plus the boot unit on top --
;     which is exactly what the cold start at 243Bh consumes
;   * MAXSECTORS/MAXBYTES are replaced by carved buffer ADDRESSES and TOPRAM
;     is lowered, as the real z80pack tertbot does
;   * iobyte is captured before the load destroys page zero, then handed to
;     the shim, whose own console driver replaces Grant's (which reads
;     iobyte at 0003h and is therefore unusable afterwards)
;   * the shim is copied to 0E300h, ABOVE TOPRAM, because the p-System
;     otherwise writes straight through it -- proven by watching it march
;     8200h, 825Ah, 82DAh, 835Ah, 83DAh during a load
;==================================================================================

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
