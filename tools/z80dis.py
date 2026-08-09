R=['B','C','D','E','H','L','(HL)','A']; RP=['BC','DE','HL','SP']; RP2=['BC','DE','HL','AF']
CC=['NZ','Z','NC','C','PO','PE','P','M']
ALU=['ADD A,','ADC A,','SUB ','SBC A,','AND ','XOR ','OR ','CP ']
ROT=['RLC','RRC','RL','RR','SLA','SRA','SLL','SRL']
def dis(m,a):
    o=m[a]; s=a; a+=1
    def n8():
        nonlocal a; v=m[a]; a+=1; return v
    def n16():
        nonlocal a; v=m[a]|(m[a+1]<<8); a+=2; return v
    def d8():
        v=n8(); return v-256 if v>127 else v
    def _R(t):
        return a,t
    if o==0xED:
        o2=n8()
        if o2 in (0x43,0x53,0x63,0x73): return _R(f"LD ({n16():04X}h),{RP[(o2>>4)&3]}")
        if o2 in (0x4B,0x5B,0x6B,0x7B): return _R(f"LD {RP[(o2>>4)&3]},({n16():04X}h)")
        if o2&0xC7==0x42: return _R(f"SBC HL,{RP[(o2>>4)&3]}")
        if o2&0xC7==0x4A: return _R(f"ADC HL,{RP[(o2>>4)&3]}")
        if o2==0xB0: return _R("LDIR")
        if o2==0xB8: return _R("LDDR")
        if o2==0x44: return _R("NEG")
        if o2==0x56: return _R("IM 1")
        if o2==0x5E: return _R("IM 2")
        if o2==0x78: return _R("IN A,(C)")
        if o2==0x79: return _R("OUT (C),A")
        return _R(f"ED {o2:02X}")
    if o==0xCB:
        o2=n8(); r=R[o2&7]
        if o2<0x40: return _R(f"{ROT[o2>>3]} {r}")
        return _R(f"{['BIT','RES','SET'][(o2>>6)-1]} {(o2>>3)&7},{r}")
    if o in (0xDD,0xFD):
        ix='IX' if o==0xDD else 'IY'; o2=n8()
        if o2==0x21: return _R(f"LD {ix},{n16():04X}h")
        if o2==0x2A: return _R(f"LD {ix},({n16():04X}h)")
        if o2==0x22: return _R(f"LD ({n16():04X}h),{ix}")
        if o2==0xE5: return _R(f"PUSH {ix}")
        if o2==0xE1: return _R(f"POP {ix}")
        if o2==0xE9: return _R(f"JP ({ix})")
        if o2&0xC7==0x46: return _R(f"LD {R[(o2>>3)&7]},({ix}{d8():+d})")
        return _R(f"{ix} {o2:02X}")
    if o==0x00: return _R("NOP")
    if o==0x76: return _R("HALT")
    if o==0xF3: return _R("DI")
    if o==0xFB: return _R("EI")
    if o==0xE3: return _R("EX (SP),HL")
    if o==0xEB: return _R("EX DE,HL")
    if o==0x08: return _R("EX AF,AF'")
    if o==0xD9: return _R("EXX")
    if o==0xE9: return _R("JP (HL)")
    if o==0xF9: return _R("LD SP,HL")
    if o==0x07: return _R("RLCA")
    if o==0x0F: return _R("RRCA")
    if o==0x17: return _R("RLA")
    if o==0x1F: return _R("RRA")
    if o==0x27: return _R("DAA")
    if o==0x2F: return _R("CPL")
    if o==0x37: return _R("SCF")
    if o==0x3F: return _R("CCF")
    if o==0xC9: return _R("RET")
    if o==0xC3: return _R(f"JP {n16():04X}h")
    if o==0xCD: return _R(f"CALL {n16():04X}h")
    if o==0x18: v=d8(); return _R(f"JR {a+v:04X}h")
    if o&0xE7==0x20: v=d8(); return _R(f"JR {CC[(o>>3)&3]},{a+v:04X}h")
    if o==0x10: v=d8(); return _R(f"DJNZ {a+v:04X}h")
    if o&0xC7==0xC2: return _R(f"JP {CC[(o>>3)&7]},{n16():04X}h")
    if o&0xC7==0xC4: return _R(f"CALL {CC[(o>>3)&7]},{n16():04X}h")
    if o&0xC7==0xC0: return _R(f"RET {CC[(o>>3)&7]}")
    if o&0xC7==0xC7: return _R(f"RST {o&0x38:02X}h")
    if o&0xCF==0xC5: return _R(f"PUSH {RP2[(o>>4)&3]}")
    if o&0xCF==0xC1: return _R(f"POP {RP2[(o>>4)&3]}")
    if o&0xCF==0x01: return _R(f"LD {RP[(o>>4)&3]},{n16():04X}h")
    if o&0xCF==0x09: return _R(f"ADD HL,{RP[(o>>4)&3]}")
    if o&0xCF==0x03: return _R(f"INC {RP[(o>>4)&3]}")
    if o&0xCF==0x0B: return _R(f"DEC {RP[(o>>4)&3]}")
    if o==0x22: return _R(f"LD ({n16():04X}h),HL")
    if o==0x2A: return _R(f"LD HL,({n16():04X}h)")
    if o==0x32: return _R(f"LD ({n16():04X}h),A")
    if o==0x3A: return _R(f"LD A,({n16():04X}h)")
    if o==0x02: return _R("LD (BC),A")
    if o==0x0A: return _R("LD A,(BC)")
    if o==0x12: return _R("LD (DE),A")
    if o==0x1A: return _R("LD A,(DE)")
    if o&0xC7==0x04: return _R(f"INC {R[(o>>3)&7]}")
    if o&0xC7==0x05: return _R(f"DEC {R[(o>>3)&7]}")
    if o&0xC7==0x06: return _R(f"LD {R[(o>>3)&7]},{n8():02X}h")
    if o&0xC0==0x40: return _R(f"LD {R[(o>>3)&7]},{R[o&7]}")
    if o&0xC0==0x80: return _R(f"{ALU[(o>>3)&7]}{R[o&7]}")
    if o&0xC7==0xC6: return _R(f"{ALU[(o>>3)&7]}{n8():02X}h")
    if o==0xD3: return _R(f"OUT ({n8():02X}h),A")
    if o==0xDB: return _R(f"IN A,({n8():02X}h)")
    return _R(f"DB {o:02X}h")
