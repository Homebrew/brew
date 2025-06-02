# frozen_string_literal: true
module RubyVM::RJIT
  # 8-bit memory access
  class BytePtr < Data.define(:reg, :disp); end

  # 32-bit memory access
  class DwordPtr < Data.define(:reg, :disp); end

  # 64-bit memory access
  QwordPtr = Array

  # SystemV x64 calling convention
  C_ARGS = [:rdi, :rsi, :rdx, :rcx, :r8, :r9]
  C_RET  = :rax

  # https://cdrdv2.intel.com/v1/dl/getContent/671110
  # Mostly an x86_64 assembler, but this also has some stuff that is useful for any architecture.
  class Assembler
    # rel8 jumps are made with labels
    class Label < Data.define(:id, :name); end

    # rel32 is inserted as [Rel32, Rel32Pad..] and converted on #resolve_rel32
    class Rel32 < Data.define(:addr); end
    Rel32Pad = Object.new

    # A set of ModR/M values encoded on #insn
    class ModRM < Data.define(:mod, :reg, :rm); end
    Mod00 = 0b00 # Mod 00: [reg]
    Mod01 = 0b01 # Mod 01: [reg]+disp8
    Mod10 = 0b10 # Mod 10: [reg]+disp32
    Mod11 = 0b11 # Mod 11: reg

    # REX =   0100WR0B
    REX_B = 0b01000001
    REX_R = 0b01000100
    REX_W = 0b01001000

    # Operand matchers
    R32   = -> (op) { op.is_a?(Symbol) && r32?(op) }
    R64   = -> (op) { op.is_a?(Symbol) && r64?(op) }
    IMM8  = -> (op) { op.is_a?(Integer) && imm8?(op) }
    IMM32 = -> (op) { op.is_a?(Integer) && imm32?(op) }
    IMM64 = -> (op) { op.is_a?(Integer) && imm64?(op) }

    def initialize
      @bytes = []
      @labels = {}
      @label_id = 0
      @comments = Hash.new { |h, k| h[k] = [] }
      @blocks = Hash.new { |h, k| h[k] = [] }
      @stub_starts = Hash.new { |h, k| h[k] = [] }
      @stub_ends = Hash.new { |h, k| h[k] = [] }
      @pos_markers = Hash.new { |h, k| h[k] = [] }
    end

    def assemble(addr)
      set_code_addrs(addr)
      resolve_rel32(addr)
      resolve_labels

      write_bytes(addr)

      @pos_markers.each do |write_pos, markers|
        markers.each { |marker| marker.call(addr + write_pos) }
      end
      @bytes.size
    ensure
      @bytes.clear
    end

    def size
      @bytes.size
    end

    #
    # Instructions
    #

    def add(dst, src)
      case [dst, src]
      # ADD r/m64, imm8 (Mod 00: [reg])
      in [QwordPtr[R64 => dst_reg], IMM8 => src_imm]
        # REX.W + 83 /0 ib
        # MI: Operand 1: ModRM:r/m (r, w), Operand 2: imm8/16/32
        insn(
          prefix: REX_W,
          opcode: 0x83,
          mod_rm: ModRM[mod: Mod00, reg: 0, rm: dst_reg],
          imm: imm8(src_imm),
        )
      # ADD r/m64, imm8 (Mod 11: reg)
      in [R64 => dst_reg, IMM8 => src_imm]
        # REX.W + 83 /0 ib
        # MI: Operand 1: ModRM:r/m (r, w), Operand 2: imm8/16/32
        insn(
          prefix: REX_W,
          opcode: 0x83,
          mod_rm: ModRM[mod: Mod11, reg: 0, rm: dst_reg],
          imm: imm8(src_imm),
        )
      # ADD r/m64 imm32 (Mod 11: reg)
      in [R64 => dst_reg, IMM32 => src_imm]
        # REX.W + 81 /0 id
        # MI: Operand 1: ModRM:r/m (r, w), Operand 2: imm8/16/32
        insn(
          prefix: REX_W,
          opcode: 0x81,
          mod_rm: ModRM[mod: Mod11, reg: 0, rm: dst_reg],
          imm: imm32(src_imm),
        )
      # ADD r/m64, r64 (Mod 11: reg)
      in [R64 => dst_reg, R64 => src_reg]
        # REX.W + 01 /r
        # MR: Operand 1: ModRM:r/m (r, w), Operand 2: ModRM:reg (r)
        insn(
          prefix: REX_W,
          opcode: 0x01,
          mod_rm: ModRM[mod: Mod11, reg: src_reg, rm: dst_reg],
        )
      end
    end

    def and(dst, src)
      case [dst, src]
      # AND r/m64, imm8 (Mod 11: reg)
      in [R64 => dst_reg, IMM8 => src_imm]
        # REX.W + 83 /4 ib
        # MI: Operand 1: ModRM:r/m (r, w), Operand 2: imm8/16/32
        insn(
          prefix: REX_W,
          opcode: 0x83,
          mod_rm: ModRM[mod: Mod11, reg: 4, rm: dst_reg],
          imm: imm8(src_imm),
        )
      # AND r/m64, imm32 (Mod 11: reg)
      in [R64 => dst_reg, IMM32 => src_imm]
        # REX.W + 81 /4 id
        # MI: Operand 1: ModRM:r/m (r, w), Operand 2: imm8/16/32
        insn(
          prefix: REX_W,
          opcode: 0x81,
          mod_rm: ModRM[mod: Mod11, reg: 4, rm: dst_reg],
          imm: imm32(src_imm),
        )
      # AND r64, r/m64 (Mod 01: [reg]+disp8)
      in [R64 => dst_reg, QwordPtr[R64 => src_reg, IMM8 => src_disp]]
        # REX.W + 23 /r
        # RM: Operand 1: ModRM:reg (r, w), Operand 2: ModRM:r/m (r)
        insn(
          prefix: REX_W,
          opcode: 0x23,
          mod_rm: ModRM[mod: Mod01, reg: dst_reg, rm: src_reg],
          disp: imm8(src_disp),
        )
      end
    end

    def call(dst)
      case dst
      # CALL rel32
      in Integer => dst_addr
        # E8 cd
        # D: Operand 1: Offset
        insn(opcode: 0xe8, imm: rel32(dst_addr))
      # CALL r/m64 (Mod 11: reg)
      in R64 => dst_reg
        # FF /2
        # M: Operand 1: ModRM:r/m (r)
        insn(
          opcode: 0xff,
          mod_rm: ModRM[mod: Mod11, reg: 2, rm: dst_reg],
        )
      end
    end

    def cmove(dst, src)
      case [dst, src]
      # CMOVE r64, r/m64 (Mod 11: reg)
      in [R64 => dst_reg, R64 => src_reg]
        # REX.W + 0F 44 /r
        # RM: Operand 1: ModRM:reg (r, w), Operand 2: ModRM:r/m (r)
        insn(
          prefix: REX_W,
          opcode: [0x0f, 0x44],
          mod_rm: ModRM[mod: Mod11, reg: dst_reg, rm: src_reg],
        )
      end
    end

    def cmovg(dst, src)
      case [dst, src]
      # CMOVG r64, r/m64 (Mod 11: reg)
      in [R64 => dst_reg, R64 => src_reg]
        # REX.W + 0F 4F /r
        # RM: Operand 1: ModRM:reg (r, w), Operand 2: ModRM:r/m (r)
        insn(
          prefix: REX_W,
          opcode: [0x0f, 0x4f],
          mod_rm: ModRM[mod: Mod11, reg: dst_reg, rm: src_reg],
        )
      end
    end

    def cmovge(dst, src)
      case [dst, src]
      # CMOVGE r64, r/m64 (Mod 11: reg)
      in [R64 => dst_reg, R64 => src_reg]
        # REX.W + 0F 4D /r
        # RM: Operand 1: ModRM:reg (r, w), Operand 2: ModRM:r/m (r)
        insn(
          prefix: REX_W,
          opcode: [0x0f, 0x4d],
          mod_rm: ModRM[mod: Mod11, reg: dst_reg, rm: src_reg],
        )
      end
    end

    def cmovl(dst, src)
      case [dst, src]
      # CMOVL r64, r/m64 (Mod 11: reg)
      in [R64 => dst_reg, R64 => src_reg]
        # REX.W + 0F 4C /r
        # RM: Operand 1: ModRM:reg (r, w), Operand 2: ModRM:r/m (r)
        insn(
          prefix: REX_W,
          opcode: [0x0f, 0x4c],
          mod_rm: ModRM[mod: Mod11, reg: dst_reg, rm: src_reg],
        )
      end
    end

    def cmovle(dst, src)
      case [dst, src]
      # CMOVLE r64, r/m64 (Mod 11: reg)
      in [R64 => dst_reg, R64 => src_reg]
        # REX.W + 0F 4E /r
        # RM: Operand 1: ModRM:reg (r, w), Operand 2: ModRM:r/m (r)
        insn(
          prefix: REX_W,
          opcode: [0x0f, 0x4e],
          mod_rm: ModRM[mod: Mod11, reg: dst_reg, rm: src_reg],
        )
      end
    end

    def cmovne(dst, src)
      case [dst, src]
      # CMOVNE r64, r/m64 (Mod 11: reg)
      in [R64 => dst_reg, R64 => src_reg]
        # REX.W + 0F 45 /r
        # RM: Operand 1: ModRM:reg (r, w), Operand 2: ModRM:r/m (r)
        insn(
          prefix: REX_W,
          opcode: [0x0f, 0x45],
          mod_rm: ModRM[mod: Mod11, reg: dst_reg, rm: src_reg],
        )
      end
    end

    def cmovnz(dst, src)
      case [dst, src]
      # CMOVNZ r64, r/m64 (Mod 11: reg)
      in [R64 => dst_reg, R64 => src_reg]
        # REX.W + 0F 45 /r
        # RM: Operand 1: ModRM:reg (r, w), Operand 2: ModRM:r/m (r)
        insn(
          prefix: REX_W,
          opcode: [0x0f, 0x45],
          mod_rm: ModRM[mod: Mod11, reg: dst_reg, rm: src_reg],
        )
      end
    end

    def cmovz(dst, src)
      case [dst, src]
      # CMOVZ r64, r/m64 (Mod 11: reg)
      in [R64 => dst_reg, R64 => src_reg]
        # REX.W + 0F 44 /r
        # RM: Operand 1: ModRM:reg (r, w), Operand 2: ModRM:r/m (r)
        insn(
          prefix: REX_W,
          opcode: [0x0f, 0x44],
          mod_rm: ModRM[mod: Mod11, reg: dst_reg, rm: src_reg],
        )
      # CMOVZ r64, r/m64 (Mod 01: [reg]+disp8)
      in [R64 => dst_reg, QwordPtr[R64 => src_reg, IMM8 => src_disp]]
        # REX.W + 0F 44 /r
        # RM: Operand 1: ModRM:reg (r, w), Operand 2: ModRM:r/m (r)
        insn(
          prefix: REX_W,
          opcode: [0x0f, 0x44],
          mod_rm: ModRM[mod: Mod01, reg: dst_reg, rm: src_reg],
          disp: imm8(src_disp),
        )
      end
    end

    def cmp(left, right)
      case [left, right]
      # CMP r/m8, imm8 (Mod 01: [reg]+disp8)
      in [BytePtr[R64 => left_reg, IMM8 => left_disp], IMM8 => right_imm]
        # 80 /7 ib
        # MI: Operand 1: ModRM:r/m (r), Operand 2: imm8/16/32
        insn(
          opcode: 0x80,
          mod_rm: ModRM[mod: Mod01, reg: 7, rm: left_reg],
          disp: left_disp,
          imm: imm8(right_imm),
        )
      # CMP r/m32, imm32 (Mod 01: [reg]+disp8)
      in [DwordPtr[R64 => left_reg, IMM8 => left_disp], IMM32 => right_imm]
        # 81 /7 id
        # MI: Operand 1: ModRM:r/m (r), Operand 2: imm8/16/32
        insn(
          opcode: 0x81,
          mod_rm: ModRM[mod: Mod01, reg: 7, rm: left_reg],
          disp: left_disp,
          imm: imm32(right_imm),
        )
      # CMP r/m64, imm8 (Mod 01: [reg]+disp8)
      in [QwordPtr[R64 => left_reg, IMM8 => left_disp], IMM8 => right_imm]
        # REX.W + 83 /7 ib
        # MI: Operand 1: ModRM:r/m (r), Operand 2: imm8/16/32
        insn(
          prefix: REX_W,
          opcode: 0x83,
          mod_rm: ModRM[mod: Mod01, reg: 7, rm: left_reg],
          disp: left_disp,
          imm: imm8(right_imm),
        )
      # CMP r/m64, imm32 (Mod 01: [reg]+disp8)
      in [QwordPtr[R64 => left_reg, IMM8 => left_disp], IMM32 => right_imm]
        # REX.W + 81 /7 id
        # MI: Operand 1: ModRM:r/m (r), Operand 2: imm8/16/32
        insn(
          prefix: REX_W,
          opcode: 0x81,
          mod_rm: ModRM[mod: Mod01, reg: 7, rm: left_reg],
          disp: left_disp,
          imm: imm32(right_imm),
        )
      # CMP r/m64, imm8 (Mod 10: [reg]+disp32)
      in [QwordPtr[R64 => left_reg, IMM32 => left_disp], IMM8 => right_imm]
        # REX.W + 83 /7 ib
        # MI: Operand 1: ModRM:r/m (r), Operand 2: imm8/16/32
        insn(
          prefix: REX_W,
          opcode: 0x83,
          mod_rm: ModRM[mod: Mod10, reg: 7, rm: left_reg],
          disp: imm32(left_disp),
          imm: imm8(right_imm),
        )
      # CMP r/m64, imm8 (Mod 11: reg)
      in [R64 => left_reg, IMM8 => right_imm]
        # REX.W + 83 /7 ib
        # MI: Operand 1: ModRM:r/m (r), Operand 2: imm8/16/32
        insn(
          prefix: REX_W,
          opcode: 0x83,
          mod_rm: ModRM[mod: Mod11, reg: 7, rm: left_reg],
          imm: imm8(right_imm),
        )
      # CMP r/m64, imm32 (Mod 11: reg)
      in [R64 => left_reg, IMM32 => right_imm]
        # REX.W + 81 /7 id
        # MI: Operand 1: ModRM:r/m (r), Operand 2: imm8/16/32
        insn(
          prefix: REX_W,
          opcode: 0x81,
          mod_rm: ModRM[mod: Mod11, reg: 7, rm: left_reg],
          imm: imm32(right_imm),
        )
      # CMP r/m64, r64 (Mod 01: [reg]+disp8)
      in [QwordPtr[R64 => left_reg, IMM8 => left_disp], R64 => right_reg]
        # REX.W + 39 /r
        # MR: Operand 1: ModRM:r/m (r), Operand 2: ModRM:reg (r)
        insn(
          prefix: REX_W,
          opcode: 0x39,
          mod_rm: ModRM[mod: Mod01, reg: right_reg, rm: left_reg],
          disp: left_disp,
        )
      # CMP r/m64, r64 (Mod 10: [reg]+disp32)
      in [QwordPtr[R64 => left_reg, IMM32 => left_disp], R64 => right_reg]
        # REX.W + 39 /r
        # MR: Operand 1: ModRM:r/m (r), Operand 2: ModRM:reg (r)
        insn(
          prefix: REX_W,
          opcode: 0x39,
          mod_rm: ModRM[mod: Mod10, reg: right_reg, rm: left_reg],
          disp: imm32(left_disp),
        )
      # CMP r/m64, r64 (Mod 11: reg)
      in [R64 => left_reg, R64 => right_reg]
        # REX.W + 39 /r
        # MR: Operand 1: ModRM:r/m (r), Operand 2: ModRM:reg (r)
        insn(
          prefix: REX_W,
          opcode: 0x39,
          mod_rm: ModRM[mod: Mod11, reg: right_reg, rm: left_reg],
        )
      end
    end

    def jbe(dst)
      case dst
      # JBE rel8
      in Label => dst_label
        # 76 cb
        insn(opcode: 0x76, imm: dst_label)
      # JBE rel32
      in Integer => dst_addr
        # 0F 86 cd
        insn(opcode: [0x0f, 0x86], imm: rel32(dst_addr))
      end
    end

    def je(dst)
      case dst
      # JE rel8
      in Label => dst_label
        # 74 cb
        insn(opcode: 0x74, imm: dst_label)
      # JE rel32
      in Integer => dst_addr
        # 0F 84 cd
        insn(opcode: [0x0f, 0x84], imm: rel32(dst_addr))
      end
    end

    def jl(dst)
      case dst
      # JL rel32
      in Integer => dst_addr
        # 0F 8C cd
        insn(opcode: [0x0f, 0x8c], imm: rel32(dst_addr))
      end
    end

    def jmp(dst)
      case dst
      # JZ rel8
      in Label => dst_label
        # EB cb
        insn(opcode: 0xeb, imm: dst_label)
      # JMP rel32
      in Integer => dst_addr
        # E9 cd
        insn(opcode: 0xe9, imm: rel32(dst_addr))
      # JMP r/m64 (Mod 01: [reg]+disp8)
      in QwordPtr[R64 => dst_reg, IMM8 => dst_disp]
        # FF /4
        insn(opcode: 0xff, mod_rm: ModRM[mod: Mod01, reg: 4, rm: dst_reg], disp: dst_disp)
      # JMP r/m64 (Mod 11: reg)
      in R64 => dst_reg
        # FF /4
        insn(opcode: 0xff, mod_rm: ModRM[mod: Mod11, reg: 4, rm: dst_reg])
      end
    end

    def jne(dst)
      case dst
      # JNE rel8
      in Label => dst_label
        # 75 cb
        insn(opcode: 0x75, imm: dst_label)
      # JNE rel32
      in Integer => dst_addr
        # 0F 85 cd
        insn(opcode: [0x0f, 0x85], imm: rel32(dst_addr))
      end
    end

    def jnz(dst)
      case dst
      # JE rel8
      in Label => dst_label
        # 75 cb
        insn(opcode: 0x75, imm: dst_label)
      # JNZ rel32
      in Integer => dst_addr
        # 0F 85 cd
        insn(opcode: [0x0f, 0x85], imm: rel32(dst_addr))
      end
    end

    def jo(dst)
      case dst
      # JO rel32
      in Integer => dst_addr
        # 0F 80 cd
        insn(opcode: [0x0f, 0x80], imm: rel32(dst_addr))
      end
    end

    def jz(dst)
      case dst
      # JZ rel8
      in Label => dst_label
        # 74 cb
        insn(opcode: 0x74, imm: dst_label)
      # JZ rel32
      in Integer => dst_addr
        # 0F 84 cd
        insn(opcode: [0x0f, 0x84], imm: rel32(dst_addr))
      end
    end

    def lea(dst, src)
      case [dst, src]
      # LEA r64,m (Mod 01: [reg]+disp8)
      in [R64 => dst_reg, QwordPtr[R64 => src_reg, IMM8 => src_disp]]
        # REX.W + 8D /r
        # RM: Operand 1: ModRM:reg (w), Operand 2: ModRM:r/m (r)
        insn(
          prefix: REX_W,
          opcode: 0x8d,
          mod_rm: ModRM[mod: Mod01, reg: dst_reg, rm: src_reg],
          disp: imm8(src_disp),
        )
      # LEA r64,m (Mod 10: [reg]+disp32)
      in [R64 => dst_reg, QwordPtr[R64 => src_reg, IMM32 => src_disp]]
        # REX.W + 8D /r
        # RM: Operand 1: ModRM:reg (w), Operand 2: ModRM:r/m (r)
        insn(
          prefix: REX_W,
          opcode: 0x8d,
          mod_rm: ModRM[mod: Mod10, reg: dst_reg, rm: src_reg],
          disp: imm32(src_disp),
        )
      end
    end

    def mov(dst, src)
      case dst
      in R32 => dst_reg
        case src
        # MOV r32 r/m32 (Mod 01: [reg]+disp8)
        in DwordPtr[R64 => src_reg, IMM8 => src_disp]
          # 8B /r
          # RM: Operand 1: ModRM:reg (w), Operand 2: ModRM:r/m (r)
          insn(
            opcode: 0x8b,
            mod_rm: ModRM[mod: Mod01, reg: dst_reg, rm: src_reg],
            disp: src_disp,
          )
        # MOV r32, imm32 (Mod 11: reg)
        in IMM32 => src_imm
          # B8+ rd id
          # OI: Operand 1: opcode + rd (w), Operand 2: imm8/16/32/64
          insn(
            opcode: 0xb8,
            rd: dst_reg,
            imm: imm32(src_imm),
          )
        end
      in R64 => dst_reg
        case src
        # MOV r64, r/m64 (Mod 00: [reg])
        in QwordPtr[R64 => src_reg]
          # REX.W + 8B /r
          # RM: Operand 1: ModRM:reg (w), Operand 2: ModRM:r/m (r)
          insn(
            prefix: REX_W,
            opcode: 0x8b,
            mod_rm: ModRM[mod: Mod00, reg: dst_reg, rm: src_reg],
          )
        # MOV r64, r/m64 (Mod 01: [reg]+disp8)
        in QwordPtr[R64 => src_reg, IMM8 => src_disp]
          # REX.W + 8B /r
          # RM: Operand 1: ModRM:reg (w), Operand 2: ModRM:r/m (r)
          insn(
            prefix: REX_W,
            opcode: 0x8b,
            mod_rm: ModRM[mod: Mod01, reg: dst_reg, rm: src_reg],
            disp: src_disp,
          )
        # MOV r64, r/m64 (Mod 10: [reg]+disp32)
        in QwordPtr[R64 => src_reg, IMM32 => src_disp]
          # REX.W + 8B /r
          # RM: Operand 1: ModRM:reg (w), Operand 2: ModRM:r/m (r)
          insn(
            prefix: REX_W,
            opcode: 0x8b,
            mod_rm: ModRM[mod: Mod10, reg: dst_reg, rm: src_reg],
            disp: imm32(src_disp),
          )
        # MOV r64, r/m64 (Mod 11: reg)
        in R64 => src_reg
          # REX.W + 8B /r
          # RM: Operand 1: ModRM:reg (w), Operand 2: ModRM:r/m (r)
          insn(
            prefix: REX_W,
            opcode: 0x8b,
            mod_rm: ModRM[mod: Mod11, reg: dst_reg, rm: src_reg],
          )
        # MOV r/m64, imm32 (Mod 11: reg)
        in IMM32 => src_imm
          # REX.W + C7 /0 id
          # MI: Operand 1: ModRM:r/m (w), Operand 2: imm8/16/32/64
          insn(
            prefix: REX_W,
            opcode: 0xc7,
            mod_rm: ModRM[mod: Mod11, reg: 0, rm: dst_reg],
            imm: imm32(src_imm),
          )
        # MOV r64, imm64
        in IMM64 => src_imm
          # REX.W + B8+ rd io
          # OI: Operand 1: opcode + rd (w), Operand 2: imm8/16/32/64
          insn(
            prefix: REX_W,
            opcode: 0xb8,
            rd: dst_reg,
            imm: imm64(src_imm),
          )
        end
      in DwordPtr[R64 => dst_reg, IMM8 => dst_disp]
        case src
        # MOV r/m32, imm32 (Mod 01: [reg]+disp8)
        in IMM32 => src_imm
          # C7 /0 id
          # MI: Operand 1: ModRM:r/m (w), Operand 2: imm8/16/32/64
          insn(
            opcode: 0xc7,
            mod_rm: ModRM[mod: Mod01, reg: 0, rm: dst_reg],
            disp: dst_disp,
            imm: imm32(src_imm),
          )
        end
      in QwordPtr[R64 => dst_reg]
        case src
        # MOV r/m64, imm32 (Mod 00: [reg])
        in IMM32 => src_imm
          # REX.W + C7 /0 id
          # MI: Operand 1: ModRM:r/m (w), Operand 2: imm8/16/32/64
          insn(
            prefix: REX_W,
            opcode: 0xc7,
            mod_rm: ModRM[mod: Mod00, reg: 0, rm: dst_reg],
            imm: imm32(src_imm),
          )
        # MOV r/m64, r64 (Mod 00: [reg])
        in R64 => src_reg
          # REX.W + 89 /r
          # MR: Operand 1: ModRM:r/m (w), Operand 2: ModRM:reg (r)
          insn(
            prefix: REX_W,
            opcode: 0x89,
            mod_rm: ModRM[mod: Mod00, reg: src_reg, rm: dst_reg],
          )
        end
      in QwordPtr[R64 => dst_reg, IMM8 => dst_disp]
        # Optimize encoding when disp is 0
        return mov([dst_reg], src) if dst_disp == 0

        case src
        # MOV r/m64, imm32 (Mod 01: [reg]+disp8)
        in IMM32 => src_imm
          # REX.W + C7 /0 id
          # MI: Operand 1: ModRM:r/m (w), Operand 2: imm8/16/32/64
          insn(
            prefix: REX_W,
            opcode: 0xc7,
            mod_rm: ModRM[mod: Mod01, reg: 0, rm: dst_reg],
            disp: dst_disp,
            imm: imm32(src_imm),
          )
        # MOV r/m64, r64 (Mod 01: [reg]+disp8)
        in R64 => src_reg
          # REX.W + 89 /r
          # MR: Operand 1: ModRM:r/m (w), Operand 2: ModRM:reg (r)
          insn(
            prefix: REX_W,
            opcode: 0x89,
            mod_rm: ModRM[mod: Mod01, reg: src_reg, rm: dst_reg],
            disp: dst_disp,
          )
        end
      in QwordPtr[R64 => dst_reg, IMM32 => dst_disp]
        case src
        # MOV r/m64, imm32 (Mod 10: [reg]+disp32)
        in IMM32 => src_imm
          # REX.W + C7 /0 id
          # MI: Operand 1: ModRM:r/m (w), Operand 2: imm8/16/32/64
          insn(
            prefix: REX_W,
            opcode: 0xc7,
            mod_rm: ModRM[mod: Mod10, reg: 0, rm: dst_reg],
            disp: imm32(dst_disp),
            imm: imm32(src_imm),
          )
        # MOV r/m64, r64 (Mod 10: [reg]+disp32)
        in R64 => src_reg
          # REX.W + 89 /r
          # MR: Operand 1: ModRM:r/m (w), Operand 2: ModRM:reg (r)
          insn(
            prefix: REX_W,
            opcode: 0x89,
            mod_rm: ModRM[mod: Mod10, reg: src_reg, rm: dst_reg],
            disp: imm32(dst_disp),
          )
        end
      end
    end

    def or(dst, src)
      case [dst, src]
      # OR r/m64, imm8 (Mod 11: reg)
      in [R64 => dst_reg, IMM8 => src_imm]
        # REX.W + 83 /1 ib
        # MI: Operand 1: ModRM:r/m (r, w), Operand 2: imm8/16/32
        insn(
          prefix: REX_W,
          opcode: 0x83,
          mod_rm: ModRM[mod: Mod11, reg: 1, rm: dst_reg],
          imm: imm8(src_imm),
        )
      # OR r/m64, imm32 (Mod 11: reg)
      in [R64 => dst_reg, IMM32 => src_imm]
        # REX.W + 81 /1 id
        # MI: Operand 1: ModRM:r/m (r, w), Operand 2: imm8/16/32
        insn(
          prefix: REX_W,
          opcode: 0x81,
          mod_rm: ModRM[mod: Mod11, reg: 1, rm: dst_reg],
          imm: imm32(src_imm),
        )
      # OR r64, r/m64 (Mod 01: [reg]+disp8)
      in [R64 => dst_reg, QwordPtr[R64 => src_reg, IMM8 => src_disp]]
        # REX.W + 0B /r
        # RM: Operand 1: ModRM:reg (r, w), Operand 2: ModRM:r/m (r)
        insn(
          prefix: REX_W,
          opcode: 0x0b,
          mod_rm: ModRM[mod: Mod01, reg: dst_reg, rm: src_reg],
          disp: imm8(src_disp),
        )
      end
    end

    def push(src)
      case src
      # PUSH r64
      in R64 => src_reg
        # 50+rd
        # O: Operand 1: opcode + rd (r)
        insn(opcode: 0x50, rd: src_reg)
      end
    end

    def pop(dst)
      case dst
      # POP r64
      in R64 => dst_reg
        # 58+ rd
        # O: Operand 1: opcode + rd (r)
        insn(opcode: 0x58, rd: dst_reg)
      end
    end

    def ret
      # RET
      # Near return: A return to a procedure within the current code segment
      insn(opcode: 0xc3)
    end

    def sar(dst, src)
      case [dst, src]
      in [R64 => dst_reg, IMM8 => src_imm]
        # REX.W + C1 /7 ib
        # MI: Operand 1: ModRM:r/m (r, w), Operand 2: imm8
        insn(
          prefix: REX_W,
          opcode: 0xc1,
          mod_rm: ModRM[mod: Mod11, reg: 7, rm: dst_reg],
          imm: imm8(src_imm),
        )
      end
    end

    def sub(dst, src)
      case [dst, src]
      # SUB r/m64, imm8 (Mod 11: reg)
      in [R64 => dst_reg, IMM8 => src_imm]
        # REX.W + 83 /5 ib
        # MI: Operand 1: ModRM:r/m (r, w), Operand 2: imm8/16/32
        insn(
          prefix: REX_W,
          opcode: 0x83,
          mod_rm: ModRM[mod: Mod11, reg: 5, rm: dst_reg],
          imm: imm8(src_imm),
        )
      # SUB r/m64, r64 (Mod 11: reg)
      in [R64 => dst_reg, R64 => src_reg]
        # REX.W + 29 /r
        # MR: Operand 1: ModRM:r/m (r, w), Operand 2: ModRM:reg (r)
        insn(
          prefix: REX_W,
          opcode: 0x29,
          mod_rm: ModRM[mod: Mod11, reg: src_reg, rm: dst_reg],
        )
      end
    end

    def test(left, right)
      case [left, right]
      # TEST r/m8*, imm8 (Mod 01: [reg]+disp8)
      in [BytePtr[R64 => left_reg, IMM8 => left_disp], IMM8 => right_imm]
        # REX + F6 /0 ib
        # MI: Operand 1: ModRM:r/m (r), Operand 2: imm8/16/32
        insn(
          opcode: 0xf6,
          mod_rm: ModRM[mod: Mod01, reg: 0, rm: left_reg],
          disp: left_disp,
          imm: imm8(right_imm),
        )
      # TEST r/m64, imm32 (Mod 01: [reg]+disp8)
      in [QwordPtr[R64 => left_reg, IMM8 => left_disp], IMM32 => right_imm]
        # REX.W + F7 /0 id
        # MI: Operand 1: ModRM:r/m (r), Operand 2: imm8/16/32
        insn(
          prefix: REX_W,
          opcode: 0xf7,
          mod_rm: ModRM[mod: Mod01, reg: 0, rm: left_reg],
          disp: left_disp,
          imm: imm32(right_imm),
        )
      # TEST r/m64, imm32 (Mod 10: [reg]+disp32)
      in [QwordPtr[R64 => left_reg, IMM32 => left_disp], IMM32 => right_imm]
        # REX.W + F7 /0 id
        # MI: Operand 1: ModRM:r/m (r), Operand 2: imm8/16/32
        insn(
          prefix: REX_W,
          opcode: 0xf7,
          mod_rm: ModRM[mod: Mod10, reg: 0, rm: left_reg],
          disp: imm32(left_disp),
          imm: imm32(right_imm),
        )
      # TEST r/m64, imm32 (Mod 11: reg)
      in [R64 => left_reg, IMM32 => right_imm]
        # REX.W + F7 /0 id
        # MI: Operand 1: ModRM:r/m (r), Operand 2: imm8/16/32
        insn(
          prefix: REX_W,
          opcode: 0xf7,
          mod_rm: ModRM[mod: Mod11, reg: 0, rm: left_reg],
          imm: imm32(right_imm),
        )
      # TEST r/m32, r32 (Mod 11: reg)
      in [R32 => left_reg, R32 => right_reg]
        # 85 /r
        # MR: Operand 1: ModRM:r/m (r), Operand 2: ModRM:reg (r)
        insn(
          opcode: 0x85,
          mod_rm: ModRM[mod: Mod11, reg: right_reg, rm: left_reg],
        )
      # TEST r/m64, r64 (Mod 11: reg)
      in [R64 => left_reg, R64 => right_reg]
        # REX.W + 85 /r
        # MR: Operand 1: ModRM:r/m (r), Operand 2: ModRM:reg (r)
        insn(
          prefix: REX_W,
          opcode: 0x85,
          mod_rm: ModRM[mod: Mod11, reg: right_reg, rm: left_reg],
        )
      end
    end

    def xor(dst, src)
      case [dst, src]
      # XOR r/m64, r64 (Mod 11: reg)
      in [R64 => dst_reg, R64 => src_reg]
        # REX.W + 31 /r
        # MR: Operand 1: ModRM:r/m (r, w), Operand 2: ModRM:reg (r)
        insn(
          prefix: REX_W,
          opcode: 0x31,
          mod_rm: ModRM[mod: Mod11, reg: src_reg, rm: dst_reg],
        )
      end
    end

    #
    # Utilities
    #

    attr_reader :comments

    def comment(message)
      @comments[@bytes.size] << message
    end

    # Mark the starting address of a block
    def block(block)
      @blocks[@bytes.size] << block
    end

    # Mark the starting/ending addresses of a stub
    def stub(stub)
      @stub_starts[@bytes.size] << stub
      yield
    ensure
      @stub_ends[@bytes.size] << stub
    end

    def pos_marker(&block)
      @pos_markers[@bytes.size] << block
    end

    def new_label(name)
      Label.new(id: @label_id += 1, name:)
    end

    # @param [RubyVM::RJIT::Assembler::Label] label
    def write_label(label)
      @labels[label] = @bytes.size
    end

    def incr_counter(name)
      if C.rjit_opts.stats
        comment("increment counter #{name}")
        mov(:rax, C.rb_rjit_counters[name].to_i)
        add([:rax], 1) # TODO: lock
      end
    end

    private

    def insn(prefix: 0, opcode:, rd: nil, mod_rm: nil, disp: nil, imm: nil)
      # Determine prefix
      if rd
        prefix |= REX_B if extended_reg?(rd)
        opcode += reg_code(rd)
      end
      if mod_rm
        prefix |= REX_R if mod_rm.reg.is_a?(Symbol) && extended_reg?(mod_rm.reg)
        prefix |= REX_B if mod_rm.rm.is_a?(Symbol) && extended_reg?(mod_rm.rm)
      end

      # Encode insn
      if prefix > 0
        @bytes.push(prefix)
      end
      @bytes.push(*Array(opcode))
      if mod_rm
        mod_rm_byte = encode_mod_rm(
          mod: mod_rm.mod,
          reg: mod_rm.reg.is_a?(Symbol) ? reg_code(mod_rm.reg) : mod_rm.reg,
          rm: mod_rm.rm.is_a?(Symbol) ? reg_code(mod_rm.rm) : mod_rm.rm,
        )
        @bytes.push(mod_rm_byte)
      end
      if disp
        @bytes.push(*Array(disp))
      end
      if imm
        @bytes.push(*imm)
      end
    end

    def reg_code(reg)
      reg_code_extended(reg).first
    end

    # Table 2-2. 32-Bit Addressing Forms with the ModR/M Byte
    #
    #  7  6  5  4  3  2  1  0
    # +--+--+--+--+--+--+--+--+
    # | Mod | Reg/   | R/M    |
    # |     | Opcode |        |
    # +--+--+--+--+--+--+--+--+
    #
    # The r/m field can specify a register as an operand or it can be combined
    # with the mod field to encode an addressing mode.
    #
    # /0: R/M is 0 (not used)
    # /r: R/M is a register
    def encode_mod_rm(mod:, reg: 0, rm: 0)
      if mod > 0b11
        raise ArgumentError, "too large Mod: #{mod}"
      end
      if reg > 0b111
        raise ArgumentError, "too large Reg/Opcode: #{reg}"
      end
      if rm > 0b111
        raise ArgumentError, "too large R/M: #{rm}"
      end
      (mod << 6) + (reg << 3) + rm
    end

    # ib: 1 byte
    def imm8(imm)
      unless imm8?(imm)
        raise ArgumentError, "unexpected imm8: #{imm}"
      end
      [imm].pack('c').unpack('c*') # TODO: consider uimm
    end

    # id: 4 bytes
    def imm32(imm)
      unless imm32?(imm)
        raise ArgumentError, "unexpected imm32: #{imm}"
      end
      [imm].pack('l').unpack('c*') # TODO: consider uimm
    end

    # io: 8 bytes
    def imm64(imm)
      unless imm64?(imm)
        raise ArgumentError, "unexpected imm64: #{imm}"
      end
      imm_bytes(imm, 8)
    end

    def imm_bytes(imm, num_bytes)
      bytes = []
      bits = imm
      num_bytes.times do
        bytes << (bits & 0xff)
        bits >>= 8
      end
      if bits != 0
        raise ArgumentError, "unexpected imm with #{num_bytes} bytes: #{imm}"
      end
      bytes
    end

    def rel32(addr)
      [Rel32.new(addr), Rel32Pad, Rel32Pad, Rel32Pad]
    end

    def set_code_addrs(write_addr)
      (@bytes.size + 1).times do |index|
        @blocks.fetch(index, []).each do |block|
          block.start_addr = write_addr + index
        end
        @stub_starts.fetch(index, []).each do |stub|
          stub.start_addr = write_addr + index
        end
        @stub_ends.fetch(index, []).each do |stub|
          stub.end_addr = write_addr + index
        end
      end
    end

    def resolve_rel32(write_addr)
      @bytes.each_with_index do |byte, index|
        if byte.is_a?(Rel32)
          src_addr = write_addr + index + 4 # offset 4 bytes for rel32 itself
          dst_addr = byte.addr
          rel32 = dst_addr - src_addr
          raise "unexpected offset: #{rel32}" unless imm32?(rel32)
          imm32(rel32).each_with_index do |rel_byte, rel_index|
            @bytes[index + rel_index] = rel_byte
          end
        end
      end
    end

    def resolve_labels
      @bytes.each_with_index do |byte, index|
        if byte.is_a?(Label)
          src_index = index + 1 # offset 1 byte for rel8 itself
          dst_index = @labels.fetch(byte)
          rel8 = dst_index - src_index
          raise "unexpected offset: #{rel8}" unless imm8?(rel8)
          @bytes[index] = rel8
        end
      end
    end

    def write_bytes(addr)
      Fiddle::Pointer.new(addr)[0, @bytes.size] = @bytes.pack('c*')
    end
  end

  module OperandMatcher
    def imm8?(imm)
      (-0x80..0x7f).include?(imm)
    end

    def imm32?(imm)
      (-0x8000_0000..0x7fff_ffff).include?(imm) # TODO: consider uimm
    end

    def imm64?(imm)
      (-0x8000_0000_0000_0000..0xffff_ffff_ffff_ffff).include?(imm)
    end

    def r32?(reg)
      if extended_reg?(reg)
        reg.end_with?('d')
      else
        reg.start_with?('e')
      end
    end

    def r64?(reg)
      if extended_reg?(reg)
        reg.match?(/\Ar\d+\z/)
      else
        reg.start_with?('r')
      end
    end

    def extended_reg?(reg)
      reg_code_extended(reg).last
    end

    def reg_code_extended(reg)
      case reg
      # Not extended
      when :al, :ax, :eax, :rax then [0, false]
      when :cl, :cx, :ecx, :rcx then [1, false]
      when :dl, :dx, :edx, :rdx then [2, false]
      when :bl, :bx, :ebx, :rbx then [3, false]
      when :ah, :sp, :esp, :rsp then [4, false]
      when :ch, :bp, :ebp, :rbp then [5, false]
      when :dh, :si, :esi, :rsi then [6, false]
      when :bh, :di, :edi, :rdi then [7, false]
      # Extended
      when :r8b,  :r8w,  :r8d,  :r8  then [0, true]
      when :r9b,  :r9w,  :r9d,  :r9  then [1, true]
      when :r10b, :r10w, :r10d, :r10 then [2, true]
      when :r11b, :r11w, :r11d, :r11 then [3, true]
      when :r12b, :r12w, :r12d, :r12 then [4, true]
      when :r13b, :r13w, :r13d, :r13 then [5, true]
      when :r14b, :r14w, :r14d, :r14 then [6, true]
      when :r15b, :r15w, :r15d, :r15 then [7, true]
      else raise ArgumentError, "unexpected reg: #{reg.inspect}"
      end
    end
  end

  class Assembler
    include OperandMatcher
    extend OperandMatcher
  end
end
