# frozen_string_literal: true

module Prism
  # This module is used for testing and debugging and is not meant to be used by
  # consumers of this library.
  module Debug
    # A wrapper around a RubyVM::InstructionSequence that provides a more
    # convenient interface for accessing parts of the iseq.
    class ISeq # :nodoc:
      attr_reader :parts

      def initialize(parts)
        @parts = parts
      end

      def type
        parts[0]
      end

      def local_table
        parts[10]
      end

      def instructions
        parts[13]
      end

      def each_child
        instructions.each do |instruction|
          # Only look at arrays. Other instructions are line numbers or
          # tracepoint events.
          next unless instruction.is_a?(Array)

          instruction.each do |opnd|
            # Only look at arrays. Other operands are literals.
            next unless opnd.is_a?(Array)

            # Only look at instruction sequences. Other operands are literals.
            next unless opnd[0] == "YARVInstructionSequence/SimpleDataFormat"

            yield ISeq.new(opnd)
          end
        end
      end
    end

    private_constant :ISeq

    # :call-seq:
    #   Debug::cruby_locals(source) -> Array
    #
    # For the given source, compiles with CRuby and returns a list of all of the
    # sets of local variables that were encountered.
    def self.cruby_locals(source)
      verbose, $VERBOSE = $VERBOSE, nil

      begin
        locals = []
        stack = [ISeq.new(RubyVM::InstructionSequence.compile(source).to_a)]

        while (iseq = stack.pop)
          names = [*iseq.local_table]
          names.map!.with_index do |name, index|
            # When an anonymous local variable is present in the iseq's local
            # table, it is represented as the stack offset from the top.
            # However, when these are dumped to binary and read back in, they
            # are replaced with the symbol :#arg_rest. To consistently handle
            # this, we replace them here with their index.
            if name == :"#arg_rest"
              names.length - index + 1
            else
              name
            end
          end

          locals << names
          iseq.each_child { |child| stack << child }
        end

        locals
      ensure
        $VERBOSE = verbose
      end
    end

    # Used to hold the place of a local that will be in the local table but
    # cannot be accessed directly from the source code. For example, the
    # iteration variable in a for loop or the positional parameter on a method
    # definition that is destructured.
    AnonymousLocal = Object.new
    private_constant :AnonymousLocal

    # :call-seq:
    #   Debug::prism_locals(source) -> Array
    #
    # For the given source, parses with prism and returns a list of all of the
    # sets of local variables that were encountered.
    def self.prism_locals(source)
      locals = []
      stack = [Prism.parse(source).value]

      while (node = stack.pop)
        case node
        when BlockNode, DefNode, LambdaNode
          names = node.locals
          params =
            if node.is_a?(DefNode)
              node.parameters
            elsif node.parameters.is_a?(NumberedParametersNode)
              nil
            else
              node.parameters&.parameters
            end

          # prism places parameters in the same order that they appear in the
          # source. CRuby places them in the order that they need to appear
          # according to their own internal calling convention. We mimic that
          # order here so that we can compare properly.
          if params
            sorted = [
              *params.requireds.map do |required|
                if required.is_a?(RequiredParameterNode)
                  required.name
                else
                  AnonymousLocal
                end
              end,
              *params.optionals.map(&:name),
              *((params.rest.name || :*) if params.rest && !params.rest.is_a?(ImplicitRestNode)),
              *params.posts.map do |post|
                if post.is_a?(RequiredParameterNode)
                  post.name
                else
                  AnonymousLocal
                end
              end,
              *params.keywords.grep(RequiredKeywordParameterNode).map(&:name),
              *params.keywords.grep(OptionalKeywordParameterNode).map(&:name),
            ]

            if params.keyword_rest.is_a?(ForwardingParameterNode)
              sorted.push(:*, :&, :"...")
            end

            sorted << AnonymousLocal if params.keywords.any?

            # Recurse down the parameter tree to find any destructured
            # parameters and add them after the other parameters.
            param_stack = params.requireds.concat(params.posts).grep(MultiTargetNode).reverse
            while (param = param_stack.pop)
              case param
              when MultiTargetNode
                param_stack.concat(param.rights.reverse)
                param_stack << param.rest
                param_stack.concat(param.lefts.reverse)
              when RequiredParameterNode
                sorted << param.name
              when SplatNode
                sorted << param.expression.name if param.expression
              end
            end

            names = sorted.concat(names - sorted)
          end

          names.map!.with_index do |name, index|
            if name == AnonymousLocal
              names.length - index + 1
            else
              name
            end
          end

          locals << names
        when ClassNode, ModuleNode, ProgramNode, SingletonClassNode
          locals << node.locals
        when ForNode
          locals << [2]
        when PostExecutionNode
          locals.push([], [])
        when InterpolatedRegularExpressionNode
          locals << [] if node.once?
        end

        stack.concat(node.compact_child_nodes)
      end

      locals
    end

    # :call-seq:
    #   Debug::newlines(source) -> Array
    #
    # For the given source string, return the byte offsets of every newline in
    # the source.
    def self.newlines(source)
      Prism.parse(source).source.offsets
    end
  end
end
