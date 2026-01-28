# typed: strict
# frozen_string_literal: true

module GitHub
  # Helper functions for interacting with GitHub Actions.
  #
  # @api internal
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

      require "securerandom"
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

    sig { returns(T::Boolean) }
    def self.env_set?
      ENV.fetch("GITHUB_ACTIONS", false).present?
    end

    sig {
      params(
        type: Symbol, message: String,
        file: T.nilable(T.any(String, Pathname)),
        line: T.nilable(Integer)
      ).returns(T::Boolean)
    }
    def self.puts_annotation_if_env_set!(type, message, file: nil, line: nil)
      # Don't print annotations during tests, too messy to handle these.
      return false if ENV.fetch("HOMEBREW_TESTS", false)
      return false unless env_set?

      std = (type == :notice) ? $stdout : $stderr
      std.puts Annotation.new(type, message)

      true
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
          file:       T.nilable(T.any(String, Pathname)),
          title:      T.nilable(String),
          line:       T.nilable(Integer),
          end_line:   T.nilable(Integer),
          column:     T.nilable(Integer),
          end_column: T.nilable(Integer),
        ).void
      }
      def initialize(type, message, file: nil, title: nil, line: nil, end_line: nil, column: nil, end_column: nil)
        raise ArgumentError, "Unsupported type: #{type.inspect}" if ANNOTATION_TYPES.exclude?(type)
        raise ArgumentError, "`title` must not contain `::`" if title.present? && title.include?("::")

        require "utils/tty"
        @type = type
        @message = T.let(Tty.strip_ansi(message), String)
        @file = T.let(self.class.path_relative_to_workspace(file), T.nilable(Pathname)) if file.present?
        @title = T.let(Tty.strip_ansi(title), String) if title
        @line = T.let(Integer(line), Integer) if line
        @end_line = T.let(Integer(end_line), Integer) if end_line
        @column = T.let(Integer(column), Integer) if column
        @end_column = T.let(Integer(end_column), Integer) if end_column
      end

      sig { returns(String) }
      def to_s
        metadata = @type.to_s.dup
        if @file
          metadata << " file=#{Actions.escape(@file.to_s)}"

          if @line
            metadata << ",line=#{@line}"
            metadata << ",endLine=#{@end_line}" if @end_line

            if @column
              metadata << ",col=#{@column}"
              metadata << ",endColumn=#{@end_column}" if @end_column
            end
          end
        end

        if @title
          metadata << (@file ? "," : " ")
          metadata << "title=#{Actions.escape(@title)}"
        end
        metadata << " " if metadata.end_with?(":")

        "::#{metadata}::#{Actions.escape(@message)}"
      end

      # An annotation is only relevant if the corresponding `file` is relative to
      # the `GITHUB_WORKSPACE` directory or if no `file` is specified.
      sig { returns(T::Boolean) }
      def relevant?
        return true if @file.blank?

        @file.descend.next.to_s != ".."
      end
    end
  end
end
