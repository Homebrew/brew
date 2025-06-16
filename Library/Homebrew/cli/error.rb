# typed: strict
# frozen_string_literal: true

require "utils/formatter"

module Homebrew
  module CLI
    class OptionConstraintError < UsageError
      sig { params(arg1: String, arg2: String, missing: T::Boolean).void }
      def initialize(arg1, arg2, missing: false)
        message = if missing
          "`#{arg2}` cannot be passed without `#{arg1}`."
        else
          "`#{arg1}` and `#{arg2}` should be passed together."
        end
        super message
      end
    end

    class OptionConflictError < UsageError
      sig { params(args: T::Array[String]).void }
      def initialize(args)
        args_list = args.map { Formatter.option(_1) }.join(" and ")
        super "Options #{args_list} are mutually exclusive."
      end
    end

    class InvalidConstraintError < UsageError
      sig { params(arg1: String, arg2: String).void }
      def initialize(arg1, arg2)
        super "`#{arg1}` and `#{arg2}` cannot be mutually exclusive and mutually dependent simultaneously."
      end
    end

    class MaxNamedArgumentsError < UsageError
      sig { params(maximum: Integer, types: T::Array[Symbol]).void }
      def initialize(maximum, types: [])
        super case maximum
        when 0
          "This command does not take named arguments."
        else
          types << :named if types.empty?
          arg_types = types.map { |type| type.to_s.tr("_", " ") }
                           .to_sentence two_words_connector: " or ", last_word_connector: " or "

          "This command does not take more than #{maximum} #{arg_types} #{Utils.pluralize("argument", maximum)}."
        end
      end
    end

    class MinNamedArgumentsError < UsageError
      sig { params(minimum: Integer, types: T::Array[Symbol]).void }
      def initialize(minimum, types: [])
        types << :named if types.empty?
        arg_types = types.map { |type| type.to_s.tr("_", " ") }
                         .to_sentence two_words_connector: " or ", last_word_connector: " or "

        super "This command requires at least #{minimum} #{arg_types} #{Utils.pluralize("argument", minimum)}."
      end
    end

    class NumberOfNamedArgumentsError < UsageError
      sig { params(minimum: Integer, types: T::Array[Symbol]).void }
      def initialize(minimum, types: [])
        types << :named if types.empty?
        arg_types = types.map { |type| type.to_s.tr("_", " ") }
                         .to_sentence two_words_connector: " or ", last_word_connector: " or "

        super "This command requires exactly #{minimum} #{arg_types} #{Utils.pluralize("argument", minimum)}."
      end
    end
  end
end
