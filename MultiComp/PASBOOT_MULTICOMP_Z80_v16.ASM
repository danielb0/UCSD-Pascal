;==================================================================================
; PASBOOT for MultiComp -- Z80 -- v16 -- PRODUCTION (diagnostics removed)
;
; Functionally identical to v15, which booted UCSD Pascal successfully on
; hardware. Only the instrumentation is gone: the per-sector progress dots,
; the 8200h hex dump, the "READ LOOP COMPLETE"/"SIGNATURE OK" banners, the
; '*' marker and the "insert disk" prompt (pointless when the volume lives
; on a fixed SD image).
;
; What is deliberately KEPT:
;   - the C5 signature gate on SECBOOT. It costs nothing, and it already
;     caught one bad handoff during development. It is silent on success and
;     reports only on failure.
;   - the per-sector BIOS status check, likewise silent unless a read fails.
;   - RDSEC's memory-resident parameters. Every parameter is reloaded from
;     memory immediately before its BIOS call, because BIOSJMP destroys DE
;     and HL on every call -- assuming otherwise was the original loader bug.
;
; Constants that matter and why:
;   INTERPBASE = LOWMEMORY = 0000h  the interpreter's dispatch table has to
;                                   own page zero (see SECBOOT's notes)
;   TRACKS     = 77                 range-checked as a SINGLE BYTE by the
;                                   interpreter, so it must be < 256
;==================================================================================

BOOT		EQU	0000h		;CP/M boot vector; (BOOT+1) = wboote
BDOS		EQU	0005h
TPA		EQU	0100h
;
WRCHAR		EQU	2
WRBUF		EQU	9
;
SECBOOT		EQU	8200h		;secondary bootstrap runs here
INTERPBASE	EQU	0000h		;interpreter loads at 0000h
LOWMEMORY	EQU	0000h		;must equal INTERPBASE
PSYSDRV		EQU	15		;P: = unit 15
FIRSTSEC	EQU	3		;SECBOOT starts at track 0 sector 3
NSECS		EQU	17		;sectors to load
TRACKS		EQU	77		;MUST fit in 8 bits
SECTORS		EQU	128		;Grant's CBIOS: 128 CP/M sectors per track
BYTES		EQU	128
INTERLEAVE	EQU	1
FIRSTTRACK	EQU	1		;p-System volume starts at track 1
SKEW		EQU	0
MAXSECTORS	EQU	128
MAXBYTES	EQU	128
;
CR		EQU	0Dh
LF		EQU	0Ah
EOM		EQU	'$'
;
		ORG	TPA
;
MAIN:
		LD	DE,BANNER
		CALL	MESSAGEOUT
		CALL	READBOOT
;
		LD	A,(SECBOOT)	;SECBOOT must begin with PUSH BC (C5)
		CP	0C5h
		JR	Z,SBOK
		LD	DE,BADMSG
		CALL	MESSAGEOUT
		JP	HALTLOOP
SBOK:
;
		LD	HL,(BOOT+1)	;top of RAM, less room for odd BIOSes
		LD	DE,-3-14
		ADD	HL,DE
		LD	SP,HL
		EX	DE,HL		;DE = top of available RAM
		LD	HL,MAXBYTES
		PUSH	HL
		LD	HL,MAXSECTORS
		PUSH	HL
		LD	HL,SKEW
		PUSH	HL
		LD	HL,FIRSTTRACK
		PUSH	HL
		LD	HL,INTERLEAVE
		PUSH	HL
		LD	HL,BYTES
		PUSH	HL
		LD	HL,SECTORS
		PUSH	HL
		LD	HL,TRACKS
		PUSH	HL
		PUSH	DE
		LD	HL,LOWMEMORY
		PUSH	HL
		LD	HL,(BOOT+1)	;SBIOS address (JP WBOOT)
		PUSH	HL
		LD	HL,INTERPBASE
		PUSH	HL
		JP	SECBOOT
;
HALTLOOP:
		JP	HALTLOOP
;
;==================================================================================
; READBOOT -- load NSECS sectors from FIRSTSEC, track 0, drive P into
; consecutive 128-byte blocks from SECBOOT upward.
;==================================================================================
READBOOT:
		LD	A,PSYSDRV
		LD	(PDRV),A
		LD	HL,0
		LD	(PTRK),HL
		LD	HL,FIRSTSEC
		LD	(PSEC),HL
		LD	HL,SECBOOT
		LD	(PDMA),HL
		LD	A,NSECS
		LD	(SECCNT),A
RBLOOP:
		CALL	RDSEC
		OR	A
		JR	NZ,RBERR
		LD	HL,(PDMA)
		LD	DE,BYTES
		ADD	HL,DE
		LD	(PDMA),HL
		LD	HL,(PSEC)
		INC	HL
		LD	(PSEC),HL
		LD	A,(SECCNT)
		DEC	A
		LD	(SECCNT),A
		JR	NZ,RBLOOP
		RET
RBERR:
		LD	(RDSTAT),A
		LD	DE,ERRMSG
		CALL	MESSAGEOUT
		LD	A,(RDSTAT)
		CALL	PRINTHEX8
		JP	HALTLOOP
;
;==================================================================================
; RDSEC -- read one sector using PDRV/PTRK/PSEC/PDMA. Returns A = status.
; Each parameter is reloaded from memory right before its own BIOS call.
;==================================================================================
RDSEC:
		LD	A,(PDRV)
		LD	C,A
		CALL	SELDSK
		LD	BC,(PTRK)
		CALL	SETTRK
		LD	BC,(PSEC)
		CALL	SETSEC
		LD	BC,(PDMA)
		CALL	SETDMA
		CALL	READ
		RET
;
; BIOSJMP uses DE as the jump-table offset, so every call below destroys
; DE and HL. Never assume they survive.
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
		LD	HL,(BOOT+1)
		ADD	HL,DE
		JP	(HL)
;
MESSAGEOUT:
		LD	C,WRBUF
		JP	BDOS
;
PRINTHEX8:
		PUSH	AF
		RRA
		RRA
		RRA
		RRA
		CALL	PRINTNIBBLE
		POP	AF
		CALL	PRINTNIBBLE
		RET
PRINTNIBBLE:
		PUSH	AF
		PUSH	BC
		PUSH	DE
		PUSH	HL
		AND	0Fh
		CP	0Ah
		JR	C,PN1
		ADD	A,7
PN1:
		ADD	A,'0'
		LD	E,A
		LD	C,WRCHAR
		CALL	BDOS
		POP	HL
		POP	DE
		POP	BC
		POP	AF
		RET
;
BANNER:
		DB	CR,LF,"UCSD p-System IV.0",CR,LF,EOM
BADMSG:
		DB	CR,LF,"BOOTSTRAP CORRUPT -- HALTED",CR,LF,EOM
ERRMSG:
		DB	CR,LF,"DISK ERROR, STATUS=",EOM
;
PDRV:		DB	00h
PTRK:		DW	0000h
PSEC:		DW	0000h
PDMA:		DW	0000h
SECCNT:		DB	00h
RDSTAT:		DB	00h
