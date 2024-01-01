# typed: true
# frozen_string_literal: true

require "securerandom"
require "utils/tty"

module GitHub
  # Helper functions for interacting with GitHub Actions.
  #
  # @api private
  module Actions
    sig { params(string: String).returns(String) }
    def self.escape(string)
      # See https://github.community/t/set-output-truncates-multiline-strings/16852/3.
      string.gsub("%", "%25")
            .gsub("\n", "%0A")
            .gsub("\r", "%0D")
    end

    sig { params(name: String, value: String).returns(String) }
    def self.format_multiline_string(name, value)
      # Format multiline strings for environment files
      # See https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#multiline-strings

      delimiter = "ghadelimiter_#{SecureRandom.uuid}"

      if name.include?(delimiter) || value.include?(delimiter)
        raise "`name` and `value` must not contain the delimiter"
      end

      <<~EOS
        #{name}<<#{delimiter}
        #{value}
        #{delimiter}
      EOS
    end

    # Helper class for formatting annotations on GitHub Actions.
    class Annotation
      ANNOTATION_TYPES = [:notice, :warning, :error].freeze

      sig { params(path: T.any(String, Pathname)).returns(T.nilable(Pathname)) }
      def self.path_relative_to_workspace(path)
        workspace = Pathname(ENV.fetch("GITHUB_WORKSPACE", Dir.pwd)).realpath
        path = Pathname(path)
        return path unless path.exist?

        path.realpath.relative_path_from(workspace)
      end

      sig {
        params(
          type:       Symbol,
          message:    String,
          file:       T.any(String, Pathname),
          title:      T.nilable(String),
          line:       T.nilable(Integer),
          end_line:   T.nilable(Integer),
          column:     T.nilable(Integer),
          end_column: T.nilable(Integer),
        ).void
      }
      def initialize(type, message, file:, title: nil, line: nil, end_line: nil, column: nil, end_column: nil)
        raise ArgumentError, "Unsupported type: #{type.inspect}" if ANNOTATION_TYPES.exclude?(type)

        @type = type
        @message = Tty.strip_ansi(message)
        @file = self.class.path_relative_to_workspace(file)
        @title = Tty.strip_ansi(title) if title
        @line = Integer(line) if line
        @end_line = Integer(end_line) if end_line
        @column = Integer(column) if column
        @end_column = Integer(end_column) if end_column
      end

      sig { returns(String) }
      def to_s
        metadata = @type.to_s
        metadata << " file=#{Actions.escape(@file.to_s)}"

        if @line
          metadata << ",line=#{@line}"
          metadata << ",endLine=#{@end_line}" if @end_line

          if @column
            metadata << ",col=#{@column}"
            metadata << ",endColumn=#{@end_column}" if @end_column
          end
        end

        metadata << ",title=#{Actions.escape(@title)}" if @title

        "::#{metadata}::#{Actions.escape(@message)}"
      end

      # An annotation is only relevant if the corresponding `file` is relative to
      # the `GITHUB_WORKSPACE` directory or if no `file` is specified.
      sig { returns(T::Boolean) }
      def relevant?
        @file.descend.next.to_s != ".."
      end
    end
  end
end
