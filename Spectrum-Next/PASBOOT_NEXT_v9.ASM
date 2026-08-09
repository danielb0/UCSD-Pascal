;==================================================================================
; PASBOOT for the ZX Spectrum Next -- Z80 -- v9 -- PRODUCTION, MARKERS OUT
;
; Functionally identical to v7. The (BOOT+1) print, the per-sector S T E D R
; markers, the 1/2/3/4 progress markers, the eight-byte dump of 8200h and the
; MARK routine are all removed, so a normal boot prints only the banner.
;
; What is deliberately kept: the banner, the C5 signature gate on SECBOOT, and
; the per-sector read status check. All three are silent unless something is
; wrong, and the signature gate has already earned its place twice.
;
; -- original v7 header follows --
;
; PASBOOT for the ZX Spectrum Next -- Z80 -- v7 -- TRACKS OFF BY ONE
;
; Disassembling the interpreter's block-to-track mapping turned up a real bug
; that v1-v6 all had. At 20E7h:
;
;       LD A,(1E99h)    ; FIRSTTRACK
;       ADD A,E         ; + track within the volume
;       CCF
;       RET NC          ; carry out -> fail
;       CP (HL)         ; HL -> TRACKS
;       RET NC          ; track >= TRACKS -> fail
;
; The check is against the track number AFTER FIRSTTRACK has been added. With
; 2400 blocks, a blocking factor of 1 and SECTORS=128, the last block is 2399,
; which is track 2399/128 = 18. Add FIRSTTRACK=1 and the BIOS is asked for
; track 19 -- and 19 >= TRACKS(19) fails.
;
; So TRACKS has to cover the volume PLUS the offset. 20 does; 19 was one short.
; This would not have shown up until something touched the last few hundred
; blocks, which is exactly the kind of bug that surfaces months later when a
; file finally grows into that region.
;
; -- original v6 header follows --
;
; PASBOOT for the ZX Spectrum Next -- Z80 -- v6
;
; v5 proved the load is correct: "1STEDRSTEDR23C5D5E5E1D1C12A0145". The dump
; matched SECBOOT v3 byte for byte, and SECBOOT's own marker 5 appeared. Then
; the console started printing the '$' terminators it should swallow, invented
; a disk error, and collapsed.
;
; THE HANDOFF STACK WAS INSIDE THE BIOS.
;
; Every version so far inherited MultiComp's idiom, SP = (BOOT+1) - 17. Under
; CP/M 2.2 that is a safe gap just below the CBIOS. Under CP/M 3 it is not,
; because (BOOT+1) is the jump table at base+0103h and the BIOS's own code sits
; BELOW it:
;
;     base+00CCh  MOVE          base+00E6h  CONST
;     base+00D0h  XMOVE         base+00EFh  CONIN
;     base+00D1h  SELMEM        base+00F8h  CONOUT
;                               base+0103h  (BOOT+1)
;
; So SP = base+00F2h. With the twelve parameters pushed it sat at base+00D8h,
; over MOVE/XMOVE/SELMEM -- markers 4 and 5 squeezed out before the damage
; told. Once SECBOOT popped all twelve, SP was back at base+00F2h and the next
; console call pushed its return address through CONST and CONIN.
;
; SECBOOT never sets SP of its own; it runs on whatever we hand it, all the way
; into the interpreter's cold start. So this one wrong constant was going to
; corrupt the BIOS no matter how far the boot got.
;
; v6:
;
; A. SP = 0BE00h -- SHIMDEST, which is also SECBOOT's NEWTOP. The twelve
;    parameters land at BDE8h..BDFFh and SECBOOT pops them straight back off.
;    Below that is the 128-byte gap down to the carved sector buffer at BD7Fh,
;    which is ample: SECBOOT's stack use is shallow, because both its MARK and
;    its disk reads go through the BIOS wrapper, and the wrapper switches to
;    the BIOS's own stack before doing anything.
;
; B. Marker 4 now prints BEFORE the switch, so no BDOS call ever runs on the
;    new stack. BDOS function 2 under CP/M 3 is banked and its appetite is not
;    worth guessing at.
;
; C. It prints (BOOT+1) as four hex digits right after the banner. That is the
;    measurement behind all of the above -- if the BIOS is not where this note
;    claims, the number will say so immediately.
;
; -- original v5 header follows --
;
; PASBOOT for the ZX Spectrum Next -- Z80 -- v5
;
; v4 got as far as "1STEDRSTEDR234": both 512-byte sectors read, the C5 gate
; passed, the handoff built, and the jump to SECBOOT taken. SECBOOT's own first
; marker never appeared.
;
; v5 changes two things, both cheap, and neither of them affects the boot path:
;
; A. It dumps the first 8 bytes actually sitting at 8200h before jumping. The
;    C5 gate is a ONE-BYTE test, and the read happens with the system bank
;    paged in -- so there is a version of events where the data landed in the
;    wrong bank and 8200h holds rubbish that merely begins with C5. Eight bytes
;    of hex settles that for good. SECBOOT begins C5 D5 E5 E1 D1 C1 3E 35.
;
; B. It calls SETBNK explicitly. Disassembling nextbios.prl shows the DMA bank
;    is a plain variable at PRL 02E7h, set by SETBNK (jump table entry 28) and
;    read by the low-level disk routine just before it is entered. It happens
;    to default to 01, which is the TPA bank -- so v4 worked by luck. Saying so
;    outright costs six bytes and removes a hidden dependency.
;
; What the PRL disassembly also confirmed, and why READ needs the wrapper:
;
;    READ   base+01A5h:  PUSH IX / LD IX,7C98h / CALL base+01B1h / POP IX / RET
;    WRITE  base+019Dh:  PUSH IX / LD IX,7CC8h / JR ...
;    tail   base+01B1h:  PUSH IX / load trk,sec,DMA,bank from variables / RET
;
; That closing RET is a tail-jump to the pushed IX -- 7C98h -- which only
; exists when the system bank is paged in. Nothing in that path pages it in,
; because the BIOS's normal caller is the banked BDOS. The generic wrapper at
; base+00FFh does: save SP, switch to the BIOS's own stack, push the current
; bank, SELMEM(0), JP (HL), keep the result in A, restore bank and SP, RET.
;
; -- original v4 header follows --
;
; PASBOOT for the ZX Spectrum Next -- Z80 -- v4 -- READ VIA THE BANKING WRAPPER
;
; v3 printed 1STED and hung: SELDSK, SETTRK, SETSEC and SETDMA all returned,
; READ did not. Confirmed -- the first four are plain stores, while READ
; dispatches to 7C98h, which only exists when the system bank is paged in. Its
; normal caller is the banked BDOS, already running there.
;
; THE WAY ROUND. The console entries in nextbios.prl all funnel through a
; generic wrapper at PRL address 01FFh:
;
;     LD (0183),SP : LD SP,0183      local stack, in common memory
;     LD A,(02E8) : PUSH AF
;     XOR A : CALL SELMEM             page IN the system bank
;     CALL 021C                       JP (HL) -- runs whatever HL points at
;     LD D,A : POP AF : CALL SELMEM   page back, keeping the return value
;     LD A,D : LD SP,(0183) : RET
;
; It runs ANY address in HL with the system bank mapped, and it lives in common
; memory so it survives the switch. Calling it with HL = the BIOS's own READ
; entry should make the dispatch to 7C98h land on real code.
;
; ADDRESSES. The stub is page-relocatable from 0100h, so PRL address X sits at
; BIOS_base + (X - 0100h), and BIOS_base is the word at 0001h minus 3:
;
;     wrapper     01FFh -> base + 00FFh
;     READ entry  02A5h -> base + 01A5h
;
; STILL UNPROVEN: where the 512 bytes land. During the read the system bank is
; mapped over our DMA address at 8200h, so the transfer has to be done via the
; bank recorded by SETBNK. SETDMA copies the CURRENT bank into it, and we are
; running in the TPA bank, so it should be right -- but that is the next thing
; to fail if this does not work.
;
;   R  READ returned
;   2  READBOOT finished
;
; v2 stopped at marker 1: the first BIOS call sequence never returned.
;
; HYPOTHESIS. Re-reading nextbios.prl, the console and disk entries are built
; differently. CONOUT saves SP, switches to a stack in common memory, calls
; SELMEM to page IN the system bank, calls its routine, then pages back. READ
; does none of that -- it dispatches straight to 7C98h, which only exists when
; the system bank is mapped. Its normal caller is the BANKED BDOS, which is
; already running there, so it never has to.
;
; We call it from the TPA, where 7C98h is our own memory. That jumps into
; whatever happens to be there.
;
; This version proves or disproves that. SELDSK, SETTRK, SETSEC and SETDMA are
; all trivial stores with no banking, so they should return normally:
;
;   1  about to call the BIOS
;   S  SELDSK returned
;   T  SETTRK returned
;   E  SETSEC returned
;   D  SETDMA returned
;   R  READ returned      <-- if this never appears, the hypothesis holds
;   2  READBOOT finished
;
; v1 reached the banner and locked up with no error message, so either the
; BIOS read never returned or something after it hung silently. These markers
; say exactly how far it gets. Each prints one character via BDOS, which is
; still valid here -- nothing has been loaded over CP/M yet.
;
;   1  banner printed, about to read
;   2  READBOOT returned without error
;   3  SECBOOT's C5 signature is good
;   4  handoff built, jumping to SECBOOT
;
; SECBOOT v2 continues the sequence with 5 onwards.
;
; Primary bootstrap. A CP/M 3 .COM file: loads the secondary bootstrap and the
; SBIOS shim from drive P, builds the 13-word handoff, and jumps.
;
; Derived from PASBOOT_MULTICOMP_Z80_v16.ASM, which boots UCSD Pascal on Grant
; Searle's MultiComp. The structure is unchanged; only the constants and the
; read loop differ. Everything in the MultiComp NOTES.md about WHY each piece
; exists still applies.
;
;----------------------------------------------------------------------------------
; WHAT IS DIFFERENT FROM THE MULTICOMP VERSION
;
; 1. CP/M 3, not CP/M 2.2. This matters far less than expected: the first 17
;    BIOS jump table entries are in exactly the CP/M 2.2 order (verified by
;    disassembling nextbios.prl), and CP/M 3 still puts JP WBOOT at 0000h, so
;    the (BOOT+1) trick to find the BIOS works unchanged.
;
; 2. 512-byte physical sectors. SHOW [DRIVES] on real hardware reports
;    512 records/track, 0 reserved tracks, 512 bytes/physical record. So a BIOS
;    READ transfers 512 bytes, not 128, and the whole secondary stage is just
;    TWO sectors instead of seventeen.
;
; 3. BYTES = 512 in the handoff. One p-System sector is one physical sector,
;    which removes any need for deblocking or read-modify-write in the shim.
;    This is the one genuinely unproven choice here -- BYTES is a handoff
;    parameter precisely so it can vary, but if the interpreter rejects it the
;    fallback is BYTES=128 with the shim deblocking, and TRACKS becomes 75.
;
; 4. TOPRAM = C000h. CP/M 3 on the Next is banked via port 1FFDh, and bank 3
;    sits at C000h in BOTH configurations -- that is the common area holding the
;    BIOS and resident BDOS. Everything below C000h is ours: 48K, against 43K on
;    MultiComp.
;
; 5. The secondary stage lives in the p-System volume's own reserved blocks 0
;    and 1, not in a separate boot track. On MultiComp it sat on track 0 of the
;    drive, but here track 0 is the CP/M directory that keeps the .p3d
;    mountable, and must not be touched. Blocks 0 and 1 are reserved for exactly
;    this purpose by the p-System's own layout -- the directory starts at
;    block 2 -- so nothing is being stolen.
;
; 6. FIRSTTRACK = 1 already tells the p-System its volume begins one track in,
;    so the shim needs NO address offset of its own. The parameter does the job.
;
;----------------------------------------------------------------------------------
; DISK LAYOUT OF cpm-p.p3d
;
;   file   0 ..    511   P3D header, not part of the disk
;   track  0             CP/M directory -- LEFT INTACT so the drive still mounts
;   track  1  sector 0   SECBOOT   (loaded to 8200h)
;   track  1  sector 1   the shim  (loaded to 8400h, relocated by SECBOOT)
;   track  1  sector 2+  the p-System volume proper; its directory is at block 2
;
; NEVER write a file to P: from the CP/M prompt. CP/M believes that space is
; free and will allocate straight over the volume.
;==================================================================================

BOOT		EQU	0000h		;CP/M boot vector; (BOOT+1) = wboote
BDOS		EQU	0005h
TPA		EQU	0100h
WRBUF		EQU	9

SECBOOT		EQU	8200h		;secondary bootstrap runs here
HANDOFF		EQU	0BE00h		;handoff stack -- must be OUR memory, not
					;the BIOS's. Equals SECBOOT's SHIMDEST and
					;NEWTOP, so the parameters sit just below
					;TOPRAM and the shim sits just above it.
INTERPBASE	EQU	0000h		;interpreter loads at 0000h
LOWMEMORY	EQU	0000h		;must equal INTERPBASE
PSYSDRV		EQU	15		;P: = unit 15, as on MultiComp

BOOTTRK		EQU	1		;secondary stage: track 1 ...
BOOTSEC		EQU	0		;... sectors 0 and 1
NSECS		EQU	2
PHYSSEC		EQU	512		;bytes per physical sector

TRACKS		EQU	20		;20 x 128 x 512 = 1,310,720 >= the 2400-block
					;volume. MUST fit in 8 bits -- the interpreter
					;range-checks it with a single-byte CP.
SECTORS		EQU	128		;physical sectors per track
BYTES		EQU	512		;one p-System sector = one physical sector
INTERLEAVE	EQU	1
FIRSTTRACK	EQU	1		;the volume starts one track in
SKEW		EQU	0
MAXSECTORS	EQU	128		;replaced by a carved ADDRESS in SECBOOT
MAXBYTES	EQU	512		;likewise -- 512 now, because BYTES is 512

CR		EQU	0Dh
LF		EQU	0Ah
EOM		EQU	'$'

		ORG	TPA

MAIN:
		LD	DE,BANNER
		CALL	MESSAGEOUT
;
		CALL	READBOOT
;
		LD	A,(SECBOOT)	;SECBOOT must begin with PUSH BC (C5).
		CP	0C5h		;Cheap, silent on success, and it caught a
		JR	Z,SBOK		;bad handoff during MultiComp development.
		LD	DE,BADMSG
		CALL	MESSAGEOUT
		JP	HALTLOOP
SBOK:
;
; --- build the 13-word handoff: 12 parameters, then the boot unit on top ---
		LD	SP,HANDOFF	;NOT (BOOT+1)-17. See the header: that
					;address is inside the CP/M 3 BIOS.
		LD	DE,0C000h	;TOPRAM: common memory starts here
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
		PUSH	DE		;TOPRAM
		LD	HL,LOWMEMORY
		PUSH	HL
		LD	HL,(BOOT+1)	;SBIOS address -- SECBOOT replaces this
		PUSH	HL		;with the shim's entry point
		LD	HL,INTERPBASE
		PUSH	HL
		JP	SECBOOT
;
HALTLOOP:
		JP	HALTLOOP

;==================================================================================
; READBOOT -- load NSECS physical sectors from track BOOTTRK, starting at
; sector BOOTSEC, into consecutive 512-byte blocks from SECBOOT upward.
;==================================================================================
READBOOT:
		LD	A,PSYSDRV
		LD	(PDRV),A
		LD	HL,BOOTTRK
		LD	(PTRK),HL
		LD	HL,BOOTSEC
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
		LD	DE,PHYSSEC
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

;==================================================================================
; RDSEC -- read one sector using PDRV/PTRK/PSEC/PDMA. Returns A = status.
;
; Every parameter is reloaded from memory immediately before its own BIOS call.
; BIOSJMP is built on DE and destroys DE and HL on every call; assuming
; otherwise was the original MultiComp loader bug, and it cost a day.
;
; Note on CP/M 3: SELDSK is entered with E holding the jump-table offset (18h),
; whose bit 0 is 0. CP/M 3 reads bit 0 of E as "this is the first select, do the
; login" -- which is exactly what we want on the first call.
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
		LD	A,1		;DMA bank = 1 = the TPA bank. This is also
		CALL	SETBNK		;the power-on default, so it changes nothing
		CALL	READ		;-- it just stops it being a coincidence.
		PUSH	AF
		POP	AF
		RET
;
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
SETBNK:
		LD	E,54h-03h	;jump table entry 28; body is LD (02E7h),A
		JP	BIOSJMP		;/ RET, so no banking wrapper is needed
; READ is NOT called directly -- see the header. HL is set to the BIOS's own
; READ entry and the call goes through the banking wrapper.
READ:
		PUSH	BC
		LD	HL,(BOOT+1)
		DEC	HL
		DEC	HL
		DEC	HL		;HL = BIOS base
		PUSH	HL
		LD	BC,01A5h	;READ entry, PRL 02A5h
		ADD	HL,BC
		POP	DE		;DE = base
		EX	DE,HL		;HL = base, DE = READ entry
		LD	BC,00FFh	;wrapper, PRL 01FFh
		ADD	HL,BC		;HL = wrapper
		EX	DE,HL		;HL = READ entry, DE = wrapper
		POP	BC
		CALL	GOWRAP
		RET
GOWRAP:
		PUSH	DE		;tail-jump to the wrapper with HL set;
		RET			;its RET comes back to our caller
;
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
		CALL	NIBBLE
		POP	AF
NIBBLE:
		AND	0Fh
		ADD	A,'0'
		CP	'9'+1
		JR	C,PUTC
		ADD	A,7
PUTC:
		PUSH	AF
		LD	E,A
		LD	C,2
		CALL	BDOS
		POP	AF
		RET
;
BANNER:		DB	CR,LF,"UCSD p-System IV.0",CR,LF,EOM
BADMSG:		DB	CR,LF,"SECBOOT signature bad",CR,LF,EOM
ERRMSG:		DB	CR,LF,"Disk read error, status ",EOM
;
PDRV:		DB	0
PTRK:		DW	0
PSEC:		DW	0
PDMA:		DW	0
SECCNT:		DB	0
RDSTAT:		DB	0
;
