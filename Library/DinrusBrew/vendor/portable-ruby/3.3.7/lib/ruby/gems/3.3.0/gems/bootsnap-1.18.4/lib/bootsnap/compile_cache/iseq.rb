# frozen_string_literal: true

require "bootsnap/bootsnap"
require "zlib"

module Bootsnap
  module CompileCache
    module ISeq
      class << self
        attr_reader(:cache_dir)

        def cache_dir=(cache_dir)
          @cache_dir = cache_dir.end_with?("/") ? "#{cache_dir}iseq" : "#{cache_dir}-iseq"
        end

        def supported?
          CompileCache.supported? && defined?(RubyVM)
        end
      end

      has_ruby_bug_18250 = begin # https://bugs.ruby-lang.org/issues/18250
        if defined? RubyVM::InstructionSequence
          RubyVM::InstructionSequence.compile("def foo(*); ->{ super }; end; def foo(**); ->{ super }; end").to_binary
        end
        false
      rescue TypeError
        true
      end

      if has_ruby_bug_18250
        def self.input_to_storage(_, path)
          iseq = begin
            RubyVM::InstructionSequence.compile_file(path)
          rescue SyntaxError
            return UNCOMPILABLE # syntax error
          end

          begin
            iseq.to_binary
          rescue TypeError
            UNCOMPILABLE # ruby bug #18250
          end
        end
      else
        def self.input_to_storage(_, path)
          RubyVM::InstructionSequence.compile_file(path).to_binary
        rescue SyntaxError
          UNCOMPILABLE # syntax error
        end
      end

      def self.storage_to_output(binary, _args)
        RubyVM::InstructionSequence.load_from_binary(binary)
      rescue RuntimeError => error
        if error.message == "broken binary format"
          $stderr.puts("[Bootsnap::CompileCache] warning: rejecting broken binary")
          nil
        else
          raise
        end
      end

      def self.fetch(path, cache_dir: ISeq.cache_dir)
        Bootsnap::CompileCache::Native.fetch(
          cache_dir,
          path.to_s,
          Bootsnap::CompileCache::ISeq,
          nil,
        )
      end

      def self.precompile(path)
        Bootsnap::CompileCache::Native.precompile(
          cache_dir,
          path.to_s,
          Bootsnap::CompileCache::ISeq,
        )
      end

      def self.input_to_output(_data, _kwargs)
        nil # ruby handles this
      end

      module InstructionSequenceMixin
        def load_iseq(path)
          # Having coverage enabled prevents iseq dumping/loading.
          return nil if defined?(Coverage) && Coverage.running?

          Bootsnap::CompileCache::ISeq.fetch(path.to_s)
        rescue RuntimeError => error
          if error.message =~ /unmatched platform/
            puts("unmatched platform for file #{path}")
          end
          raise
        end

        def compile_option=(hash)
          super(hash)
          Bootsnap::CompileCache::ISeq.compile_option_updated
        end
      end

      def self.compile_option_updated
        option = RubyVM::InstructionSequence.compile_option
        crc = Zlib.crc32(option.inspect)
        Bootsnap::CompileCache::Native.compile_option_crc32 = crc
      end
      compile_option_updated if supported?

      def self.install!(cache_dir)
        Bootsnap::CompileCache::ISeq.cache_dir = cache_dir

        return unless supported?

        Bootsnap::CompileCache::ISeq.compile_option_updated

        class << RubyVM::InstructionSequence
          prepend(InstructionSequenceMixin)
        end
      end
    end
  end
end
