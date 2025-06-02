module RubyVM::RJIT
  class CodeBlock
    # @param mem_block [Integer] JIT buffer address
    # @param mem_size  [Integer] JIT buffer size
    # @param outliend  [TrueClass,FalseClass] true for outlined CodeBlock
    def initialize(mem_block:, mem_size:, outlined: false)
      @comments  = Hash.new { |h, k| h[k] = [] } if dump_disasm?
      @mem_block = mem_block
      @mem_size  = mem_size
      @write_pos = 0
      @outlined  = outlined
    end

    # @param asm [RubyVM::RJIT::Assembler]
    def write(asm)
      return 0 if @write_pos + asm.size >= @mem_size

      start_addr = write_addr

      # Write machine code
      C.mprotect_write(@mem_block, @mem_size)
      @write_pos += asm.assemble(start_addr)
      C.mprotect_exec(@mem_block, @mem_size)

      end_addr = write_addr

      # Convert comment indexes to addresses
      asm.comments.each do |index, comments|
        @comments[start_addr + index] += comments if dump_disasm?
      end
      asm.comments.clear

      # Dump disasm if --rjit-dump-disasm
      if C.rjit_opts.dump_disasm && start_addr < end_addr
        dump_disasm(start_addr, end_addr)
      end
      start_addr
    end

    def set_write_addr(addr)
      @write_pos = addr - @mem_block
      @comments.delete(addr) if dump_disasm?
    end

    def with_write_addr(addr)
      old_write_pos = @write_pos
      set_write_addr(addr)
      yield
    ensure
      @write_pos = old_write_pos
    end

    def write_addr
      @mem_block + @write_pos
    end

    def include?(addr)
      (@mem_block...(@mem_block + @mem_size)).include?(addr)
    end

    def dump_disasm(from, to, io: STDOUT, color: true, test: false)
      C.dump_disasm(from, to, test:).each do |address, mnemonic, op_str|
        @comments.fetch(address, []).each do |comment|
          io.puts colorize("  # #{comment}", bold: true, color:)
        end
        io.puts colorize("  0x#{format("%x", address)}: #{mnemonic} #{op_str}", color:)
      end
      io.puts
    end

    private

    def colorize(text, bold: false, color:)
      return text unless color
      buf = +''
      buf << "\e[1m" if bold
      buf << "\e[34m" if @outlined
      buf << text
      buf << "\e[0m"
      buf
    end

    def bold(text)
      "\e[1m#{text}\e[0m"
    end

    def dump_disasm?
      C.rjit_opts.dump_disasm
    end
  end
end
