# frozen_string_literal: true

module RequireHooks
  module LoadIseq
    def load_iseq(path)
      ctx = RequireHooks.context_for(path)

      ctx.run_around_load_callbacks(path) do
        if ctx.source_transform? || ctx.hijack?
          new_contents = ctx.perform_source_transform(path)
          hijacked = ctx.try_hijack_load(path, new_contents)

          if hijacked
            raise TypeError, "Unsupported bytecode format for #{path}: #{hijack.class}" unless hijacked.is_a?(::RubyVM::InstructionSequence)
            return hijacked
          elsif new_contents
            return RubyVM::InstructionSequence.compile(new_contents, path, path, 1)
          end
        end

        defined?(super) ? super : RubyVM::InstructionSequence.compile_file(path)
      end
    end
  end
end

if RubyVM::InstructionSequence.respond_to?(:load_iseq)
  warn "require-hooks: RubyVM::InstructionSequence.load_iseq is already defined. It won't be used by files processed by require-hooks."
end

RubyVM::InstructionSequence.singleton_class.prepend(RequireHooks::LoadIseq)
