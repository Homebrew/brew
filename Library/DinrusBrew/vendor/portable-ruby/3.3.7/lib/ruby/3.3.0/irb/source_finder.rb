# frozen_string_literal: true

require_relative "ruby-lex"

module IRB
  class SourceFinder
    class EvaluationError < StandardError; end

    class Source
      attr_reader :file, :line
      def initialize(file, line, ast_source = nil)
        @file = file
        @line = line
        @ast_source = ast_source
      end

      def file_exist?
        File.exist?(@file)
      end

      def binary_file?
        # If the line is zero, it means that the target's source is probably in a binary file.
        @line.zero?
      end

      def file_content
        @file_content ||= File.read(@file)
      end

      def colorized_content
        if !binary_file? && file_exist?
          end_line = find_end
          # To correctly colorize, we need to colorize full content and extract the relevant lines.
          colored = IRB::Color.colorize_code(file_content)
          colored.lines[@line - 1...end_line].join
        elsif @ast_source
          IRB::Color.colorize_code(@ast_source)
        end
      end

      private

      def find_end
        lex = RubyLex.new
        code = file_content
        lines = code.lines[(@line - 1)..-1]
        tokens = RubyLex.ripper_lex_without_warning(lines.join)
        prev_tokens = []

        # chunk with line number
        tokens.chunk { |tok| tok.pos[0] }.each do |lnum, chunk|
          code = lines[0..lnum].join
          prev_tokens.concat chunk
          continue = lex.should_continue?(prev_tokens)
          syntax = lex.check_code_syntax(code, local_variables: [])
          if !continue && syntax == :valid
            return @line + lnum
          end
        end
        @line
      end
    end

    private_constant :Source

    def initialize(irb_context)
      @irb_context = irb_context
    end

    def find_source(signature, super_level = 0)
      case signature
      when /\A(::)?[A-Z]\w*(::[A-Z]\w*)*\z/ # ConstName, ::ConstName, ConstPath::ConstName
        eval_receiver_or_owner(signature) # trigger autoload
        *parts, name = signature.split('::', -1)
        base =
          if parts.empty? # ConstName
            find_const_owner(name)
          elsif parts == [''] # ::ConstName
            Object
          else # ConstPath::ConstName
            eval_receiver_or_owner(parts.join('::'))
          end
        file, line = base.const_source_location(name)
      when /\A(?<owner>[A-Z]\w*(::[A-Z]\w*)*)#(?<method>[^ :.]+)\z/ # Class#method
        owner = eval_receiver_or_owner(Regexp.last_match[:owner])
        method = Regexp.last_match[:method]
        return unless owner.respond_to?(:instance_method)
        method = method_target(owner, super_level, method, "owner")
        file, line = method&.source_location
      when /\A((?<receiver>.+)(\.|::))?(?<method>[^ :.]+)\z/ # method, receiver.method, receiver::method
        receiver = eval_receiver_or_owner(Regexp.last_match[:receiver] || 'self')
        method = Regexp.last_match[:method]
        return unless receiver.respond_to?(method, true)
        method = method_target(receiver, super_level, method, "receiver")
        file, line = method&.source_location
      end
      return unless file && line

      if File.exist?(file)
        Source.new(file, line)
      elsif method
        # Method defined with eval, probably in IRB session
        source = RubyVM::AbstractSyntaxTree.of(method)&.source rescue nil
        Source.new(file, line, source)
      end
    rescue EvaluationError
      nil
    end

    private

    def method_target(owner_receiver, super_level, method, type)
      case type
      when "owner"
        target_method = owner_receiver.instance_method(method)
      when "receiver"
        target_method = owner_receiver.method(method)
      end
      super_level.times do |s|
        target_method = target_method.super_method if target_method
      end
      target_method
    rescue NameError
      nil
    end

    def eval_receiver_or_owner(code)
      context_binding = @irb_context.workspace.binding
      eval(code, context_binding)
    rescue NameError
      raise EvaluationError
    end

    def find_const_owner(name)
      module_nesting = @irb_context.workspace.binding.eval('::Module.nesting')
      module_nesting.find { |mod| mod.const_defined?(name, false) } || module_nesting.find { |mod| mod.const_defined?(name) } || Object
    end
  end
end
