# frozen_string_literal: true

require_relative "nop"
require_relative "../color"
require_relative "../ruby-lex"

# :stopdoc:
module IRB
  module ExtendCommand
    class ShowSource < Nop
      def execute(str = nil)
        unless str.is_a?(String)
          puts "Error: Expected a string but got #{str.inspect}"
          return
        end
        source = find_source(str)
        if source && File.exist?(source.file)
          show_source(source)
        else
          puts "Error: Couldn't locate a definition for #{str}"
        end
        nil
      end

      private

      # @param [IRB::ExtendCommand::ShowSource::Source] source
      def show_source(source)
        puts
        puts "#{bold("From")}: #{source.file}:#{source.first_line}"
        puts
        code = IRB::Color.colorize_code(File.read(source.file))
        puts code.lines[(source.first_line - 1)...source.last_line].join
        puts
      end

      def find_source(str)
        case str
        when /\A[A-Z]\w*(::[A-Z]\w*)*\z/ # Const::Name
          eval(str, irb_context.workspace.binding) # trigger autoload
          base = irb_context.workspace.binding.receiver.yield_self { |r| r.is_a?(Module) ? r : Object }
          file, line = base.const_source_location(str) if base.respond_to?(:const_source_location) # Ruby 2.7+
        when /\A(?<owner>[A-Z]\w*(::[A-Z]\w*)*)#(?<method>[^ :.]+)\z/ # Class#method
          owner = eval(Regexp.last_match[:owner], irb_context.workspace.binding)
          method = Regexp.last_match[:method]
          if owner.respond_to?(:instance_method) && owner.instance_methods.include?(method.to_sym)
            file, line = owner.instance_method(method).source_location
          end
        when /\A((?<receiver>.+)(\.|::))?(?<method>[^ :.]+)\z/ # method, receiver.method, receiver::method
          receiver = eval(Regexp.last_match[:receiver] || 'self', irb_context.workspace.binding)
          method = Regexp.last_match[:method]
          file, line = receiver.method(method).source_location if receiver.respond_to?(method)
        end
        if file && line
          Source.new(file: file, first_line: line, last_line: find_end(file, line))
        end
      end

      def find_end(file, first_line)
        return first_line unless File.exist?(file)
        lex = RubyLex.new
        lines = File.read(file).lines[(first_line - 1)..-1]
        tokens = RubyLex.ripper_lex_without_warning(lines.join)
        prev_tokens = []

        # chunk with line number
        tokens.chunk { |tok| tok.pos[0] }.each do |lnum, chunk|
          code = lines[0..lnum].join
          prev_tokens.concat chunk
          continue = lex.process_continue(prev_tokens)
          code_block_open = lex.check_code_block(code, prev_tokens)
          if !continue && !code_block_open
            return first_line + lnum
          end
        end
        first_line
      end

      def bold(str)
        Color.colorize(str, [:BOLD])
      end

      Source = Struct.new(
        :file,       # @param [String] - file name
        :first_line, # @param [String] - first line
        :last_line,  # @param [String] - last line
        keyword_init: true,
      )
      private_constant :Source
    end
  end
end
# :startdoc:
