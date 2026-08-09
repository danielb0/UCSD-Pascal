;==================================================================================
; SECBOOT for the ZX Spectrum Next -- v6 -- VERIFY THE LOAD AND THE CARVE
;
; v5 reaches marker C, enters the interpreter, and the machine goes quiet with
; the border steady. Instrumenting every SBIOS entry in the shim produced
; nothing at all -- not a disk call, not even a CONST poll.
;
; Disassembling the interpreter accounts for that without contradiction. Its
; cold start does a great deal before it ever touches the SBIOS:
;
;   243Bh  pop the boot unit, then twelve words into a table at 1E89h
;   1C5Bh  unitclear(0) -> 2326h -> 2056h, which builds the interleave table
;          from SECTORS and computes 512/BYTES; unitclear(1); then unitstatus(0)
;          -> 2331h, which returns TOPRAM, and THAT becomes SP
;   246Fh  LD SP,(03A6h)
;   24D4h  the first disk access: unitread(unit 4, block 2, 2048 bytes) for the
;          p-System directory, which reaches SELDSK at 1F26h
;
; So the absence of markers only proves it died somewhere before 1F26h -- a
; long stretch that never touches the shim. Every part of it that depends on
; our twelve parameters checks out on paper: the SBIOS offsets are CP/M's
; shifted by three, which is right for SBIOS = base+3; the divide at 214Ah
; really does return 1 for BYTES=512, as it returns 4 for 128; the gate at
; 22B1h passes; the interleave builder writes exactly SECTORS bytes to
; MAXSEC_ADDR.
;
; What has NEVER been checked is the one link the disassembly cannot reach:
; whether the interpreter actually in memory is the interpreter we think we
; loaded. So this build prints, without changing any behaviour:
;
;   after A   the words at 0200h and 0202h. SYSTEM.INTERP begins its cold-start
;             vector table there, so these must read 3BC3 C324 -- little-endian
;             for C3 3B 24 C3, "JP 243Bh". Anything else and the load is wrong
;             and every conclusion above is void.
;
;   after B   TOPRAM, MAXSEC_ADDR, MAXBYT_ADDR as actually computed by the
;             carve. Expect BB80 BD80 BB80.
;
; -- original v5 header follows --
;
; SECBOOT for the ZX Spectrum Next -- v5 -- THE INTERPRETER'S STACK
;
; v4 reached marker C and entered the interpreter. The border went purple --
; nothing in this code touches port FEh, so that was the ULA being hit by wild
; OUTs, i.e. the interpreter running away.
;
; The cause was an omission of mine when porting from MultiComp. That version
; ends the carve with:
;
;       LD   A,L
;       AND  0FEh
;       LD   L,A
;       LD   (TOPRAMV),HL
;       LD   SP,HL
;
; and v1-v4 here had neither the alignment nor, far more importantly, the
; LD SP,HL. So the thirteen words were pushed on PASBOOT's stack at BE00h and
; the interpreter inherited that as ITS stack. But the carve had just placed:
;
;       BB80h   sector buffer (512 bytes, MAXBYTES)
;       BD80h   sector table  (128 bytes, MAXSECTORS)
;       BE00h   the shim
;
; which puts the handoff words at BDE6h..BDFFh -- inside the sector table --
; with the interpreter's stack then growing down through the table and into the
; buffer. It overwrites its own disk buffers with stack the moment it starts
; work, and vice versa.
;
; SP must be the FINAL TOPRAM, below both carved areas. That is the whole point
; of computing TOPRAM last.
;
; The AND 0FEh is a no-op with these numbers (BE00h - 128 - 512 = BB80h, already
; even) but it is in the original for a reason and costs three bytes.
;
; -- original v4 header follows --
;
; SECBOOT for the ZX Spectrum Next -- v4 -- THE BIOS ADDRESS MUST NOT COME
; FROM PAGE ZERO
;
; v3 reached marker 9: shim relocated, directory read, SYSTEM.INTERP found. It
; died during the load itself.
;
; SYSTEM.INTERP is 27 blocks, 13824 bytes, and loads to 0000h..35FFh. The first
; block of that load overwrites 0000h..01FFh -- including the two bytes at
; 0001h that hold the BIOS address. READ and BIOSJMP were still fetching it
; with LD HL,(BOOT+1) on every single call, so the second block's SELDSK read
; two bytes of freshly-loaded interpreter, treated them as an address, and
; jumped there.
;
; MARK already avoided this: it uses SBIOSADDRV at 9002h, which is why markers
; 5 through 9 all appeared. The fix is simply to be consistent -- READ and
; BIOSJMP now read SBIOSADDRV too. The value is identical (wboote, F803h on
; this machine), it just lives somewhere the load cannot reach.
;
; The seed at ENTRY still uses (BOOT+1), which is correct: it runs before
; anything has been loaded, and it is what puts the address in SBIOSADDRV in
; the first place.
;
; The load's extent is worth recording, because it is what makes the rest of
; the layout safe: 35FFh is comfortably below SCRATCH at 9000h, DIRBUF at
; 9800h and SECBOOT's own code at 8200h. Nothing else needs moving.
;
; -- original v3 header follows --
;
; SECBOOT for the ZX Spectrum Next -- v3 -- BANKING WRAPPER + MARKER FIX
;
; PASBOOT v4 reached marker 4: both sectors read, the C5 signature matched, and
; it jumped here. Marker 5 never appeared, for two reasons -- one a fault in the
; instrumentation, one fatal either way.
;
; 1. MARK read the BIOS address from SBIOSADDRV, but marker 5 fires BEFORE the
;    handoff parameters are popped, so it read uninitialised memory at 9002h
;    and jumped into it. Fixed by seeding SBIOSADDRV from (BOOT+1) on entry.
;    The value is the same one PASBOOT pushes, so the later pop is harmless.
;
; 2. READ was called directly, which cannot work: it dispatches to 7C98h, which
;    only exists with the system bank paged in. Same obstacle PASBOOT hit, and
;    the same way round -- go through the BIOS's own banking wrapper.
;
;      wrapper     PRL 01FFh -> base + 00FFh
;      READ entry  PRL 02A5h -> base + 01A5h
;      base = (0001h) - 3
;
; The wrapper saves SP, switches to a stack in common memory, pages in the
; system bank, calls whatever HL points at, pages back and restores SP. It
; preserves the routine's return value in A, so the read status survives.
;
; v1 got as far as PASBOOT's banner and locked up silently. These markers
; continue PASBOOT v2's sequence, so the last character on screen says exactly
; where it stopped:
;
;   5  entered, C5 gate passed
;   6  twelve handoff parameters popped
;   7  shim relocated to BE00h
;   8  directory read (blocks 2..5)
;   9  SYSTEM.INTERP found in the directory
;   A  interpreter loaded to 0000h  <-- page zero and BDOS are gone after this
;   B  TOPRAM forced down, buffers carved
;   C  13 words pushed, about to enter the interpreter
;
; MARK cannot use BDOS, because marker A destroys the vector at 0005h. It calls
; the real BIOS CONOUT directly through the address PASBOOT handed us, which is
; saved in SBIOSADDRV at 9002h and survives the load.
;
; If the last thing seen is C, the interpreter is being entered and refusing to
; run -- which would point at BYTES=512 or the handoff itself, not at the disk.
;
; Secondary bootstrap. Runs at 8200h, loaded there by PASBOOT along with the
; shim image. It relocates the shim above the p-System's memory, loads
; SYSTEM.INTERP to 0000h, carves the sector buffers, and hands over.
;
; Derived from SECBOOT_MULTICOMP_v21.ASM. The sequence is identical; what
; changed is the arithmetic and two things that are simply not needed here.
;
;----------------------------------------------------------------------------------
; DIFFERENCES FROM THE MULTICOMP VERSION
;
; 1. READBLOCK does ONE read, not four. On MultiComp a 512-byte p-System block
;    was four 128-byte CP/M sectors. Here a physical sector IS 512 bytes, so
;    block N maps to exactly one BIOS read.
;
; 2. No iobyte capture. MultiComp's shim had to drive the ACIA directly, because
;    the interpreter overwrites the iobyte at 0003h when it loads at 0000h.
;    Here the shim passes console calls straight to the real BIOS, which keeps
;    its own state in common memory at C000h and up -- untouched by the load.
;
; 3. The shim lives at BE00h, just under the CP/M 3 common area at C000h,
;    rather than at E200h under Grant's CBIOS at E600h.
;
;----------------------------------------------------------------------------------
; MEMORY MAP AFTER HANDOFF
;
;   0000h..35FFh   SYSTEM.INTERP        (owns page zero -- see MultiComp NOTES)
;   3600h..BB7Fh   p-System workspace   about 47K
;   BB80h..BD7Fh   sector buffer  ) carved by this code from NEWTOP = BE00h
;   BD80h..BDFFh   sector table   )
;   BE00h..BFFFh   the shim             above TOPRAM, so it survives
;   C000h..FFFFh   CP/M 3 common area   BIOS, resident BDOS -- must not be touched
;
;----------------------------------------------------------------------------------
; WHERE THIS CODE LIVES ON DISK
;
; PASBOOT loads 1024 bytes -- the p-System volume's reserved blocks 0 and 1 --
; to 8200h. Within that window:
;
;   8200h .. 847Fh   this code            (640 bytes available)
;   8480h .. 85FFh   the shim image       (384 bytes available)
;
; Both limits are hard. The p-System directory starts at block 2, so there is
; no room to grow without moving the secondary stage off the volume entirely.
;==================================================================================

FIRSTBLOCK	EQU	2		;p-System directory starts at block 2
DIRBLOCKS	EQU	4		;directory occupies blocks 2..5
ENTRYSIZE	EQU	26
NAMEOFFSET	EQU	6
NAMEFIELDLEN	EQU	14		;length byte + "SYSTEM.INTERP"
MAXENTRIES	EQU	77

PSYSDRV		EQU	15		;P: = unit 15
BOOTUNIT	EQU	4		;p-System boot unit

SHIMDEST	EQU	0BE00h		;where the shim runs (above TOPRAM,
					;below the CP/M 3 common area at C000h)
SHIMSRC		EQU	8200h+640	;its image slot in the loaded window
SHIMLEN		EQU	384
SHIMREAL	EQU	SHIMDEST+51	;shim's REALBIOS word (0BE33h)
NEWTOP		EQU	SHIMDEST	;TOPRAM before the carve

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

BOOT		EQU	0000h
BDOS		EQU	0005h
CR		EQU	0Dh
LF		EQU	0Ah
EOM		EQU	'$'
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
		LD	HL,(BOOT+1)	;seed this NOW -- MARK needs it before the
		LD	(SBIOSADDRV),HL	;handoff parameters are popped
;
		LD	A,'5'
		CALL	MARK
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
		LD	A,'6'
		CALL	MARK
;
; --- relocate the shim and tell it where the real BIOS is ---
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
;
		LD	A,'7'
		CALL	MARK
;
; --- read the directory, blocks 2..5 ---
		LD	HL,FIRSTBLOCK
		LD	(CURBLOCK),HL
		LD	HL,DIRBUF
		LD	(CURDEST),HL
		LD	A,DIRBLOCKS
		LD	(BLOCKSLEFT),A
		CALL	READMANY
;
		LD	A,'8'
		CALL	MARK
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
		LD	A,'9'
		CALL	MARK
;
		LD	HL,(STARTBLOCK)
		LD	(CURBLOCK),HL
		LD	HL,(INTERPBASEV)
		LD	(CURDEST),HL
		CALL	READMANY	;<-- page zero dies here
;
		LD	A,'A'
		CALL	MARK
		LD	HL,(0200h)	;must be 3BC3 C324 = C3 3B 24 C3 = JP 243Bh
		CALL	PRHL
		LD	HL,(0202h)
		CALL	PRHL
;
;==================================================================================
; Force TOPRAM down to the shim's base, then carve the sector table and the
; sector buffer below it, exactly as the real tertbot does. Passing the raw
; counts instead of addresses points the interpreter's buffer at 0080h, inside
; its own code.
;==================================================================================
		LD	HL,NEWTOP
		LD	(TOPRAMV),HL
;
		LD	HL,(TOPRAMV)
		LD	DE,(MAXSECTORSV)
		OR	A
		SBC	HL,DE
		LD	(MAXSECTORSV),HL	;sector-table ADDRESS
;
		LD	DE,(MAXBYTESV)
		OR	A
		SBC	HL,DE
		LD	(MAXBYTESV),HL		;sector-buffer ADDRESS
;
		LD	A,L			;word-align, as the real tertbot does
		AND	0FEh
		LD	L,A
		LD	(TOPRAMV),HL		;TOPRAM ends up below both
		LD	SP,HL			;AND SO DOES THE STACK. Without this
					;the thirteen words are pushed into the
					;sector table and the interpreter runs
					;on a stack inside its own buffers.
;
		LD	A,'B'
		CALL	MARK
		LD	HL,(TOPRAMV)	;expect BB80 BD80 BB80
		CALL	PRHL
		LD	HL,(MAXSECTORSV)
		CALL	PRHL
		LD	HL,(MAXBYTESV)
		CALL	PRHL
;
;==================================================================================
; Push the 13 words and enter the interpreter. Twelve parameters, then the boot
; unit on top -- the cold start pops the unit FIRST, then exactly twelve. Push
; only twelve and everything is off by two bytes and it dies silently.
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
		LD	HL,SHIMDEST+3		;SBIOS = the shim's WBOOT entry
		PUSH	HL
		LD	HL,(INTERPBASEV)
		PUSH	HL
		LD	HL,BOOTUNIT
		PUSH	HL
;
		LD	A,'C'
		CALL	MARK
;
		LD	HL,(INTERPBASEV)
		LD	DE,0200h
		ADD	HL,DE
		JP	(HL)			;INTERPBASE+0200h
;
NOTFOUND:
		LD	DE,NOTFOUNDMSG
		CALL	MESSAGEOUT	;BDOS is still valid -- nothing loaded yet
HANGLOOP:
		JP	HANGLOOP

;==================================================================================
; READMANY / READBLOCK
;
; A p-System block is 512 bytes and so is a physical sector, so one block is
; ONE read. On MultiComp this loop ran four times per block.
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
; HL = block number, DE = destination
READBLOCK:
		LD	(DESTPTR),DE
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
		RET
;
; SECBOOT's own BIOS access -- straight to the real thing, never the shim.
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
; READ is NOT called directly -- it dispatches into the system bank. Go through
; the BIOS's own banking wrapper, exactly as PASBOOT v4 does.
READ:
		PUSH	BC
		LD	HL,(SBIOSADDRV)	;NOT (BOOT+1) -- page zero is destroyed
		DEC	HL		;partway through the interpreter load
		DEC	HL
		DEC	HL		;HL = BIOS base
		PUSH	HL
		LD	BC,01A5h	;READ entry, PRL 02A5h
		ADD	HL,BC
		POP	DE		;DE = base
		EX	DE,HL		;HL = base, DE = READ entry
		LD	BC,00FFh	;wrapper, PRL 01FFh
		ADD	HL,BC
		EX	DE,HL		;HL = READ entry, DE = wrapper
		POP	BC
		CALL	GOWRAP
		RET
GOWRAP:
		PUSH	DE		;tail-jump to the wrapper with HL set
		RET
;
BIOSJMP:
		LD	D,0
		LD	HL,(SBIOSADDRV)	;likewise -- SELDSK/SETTRK/SETSEC/SETDMA
		ADD	HL,DE		;are called for every block of the load
		JP	(HL)
;
MESSAGEOUT:
		LD	C,WRBUF
		JP	BDOS
;
; MARK -- print the character in A through the REAL BIOS CONOUT, using the
; address saved in SBIOSADDRV. Deliberately not BDOS: marker A comes after the
; interpreter has overwritten page zero, so the vector at 0005h is gone by then.
; SBIOSADDRV holds wboote (= BIOS+3); CONOUT is BIOS+12, i.e. wboote+9.
MARK:
		PUSH	AF
		PUSH	BC
		PUSH	DE
		PUSH	HL
		LD	C,A
		LD	HL,(SBIOSADDRV)
		LD	DE,9
		ADD	HL,DE
		CALL	MKCALL
		POP	HL
		POP	DE
		POP	BC
		POP	AF
		RET
MKCALL:
		JP	(HL)
;
; PRHL -- print HL as four hex digits through MARK, which preserves everything.
PRHL:
		LD	A,H
		CALL	PRHEX
		LD	A,L
PRHEX:
		PUSH	AF
		RRA
		RRA
		RRA
		RRA
		CALL	PRNIB
		POP	AF
PRNIB:
		AND	0Fh
		ADD	A,'0'
		CP	'9'+1
		JR	C,PRPUT
		ADD	A,7
PRPUT:
		JP	MARK
;
TARGETNAME:	DB	13,"SYSTEM.INTERP"
NOTFOUNDMSG:	DB	CR,LF,"SYSTEM.INTERP not found",CR,LF,EOM
;
