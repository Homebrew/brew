# typed: strict
# frozen_string_literal: true

require "shellwords"

module Cask
  # Reads and edits freedesktop.org desktop entry files, keeping their comments and layout.
  # Ref: https://specifications.freedesktop.org/desktop-entry/latest/
  class DesktopFileParser
    DESKTOP_ENTRY_GROUP = "Desktop Entry"
    private_constant :DESKTOP_ENTRY_GROUP

    # Escape sequences in values of the spec's `string` type.
    VALUE_ESCAPES = T.let({ "s" => " ", "n" => "\n", "t" => "\t", "r" => "\r", "\\" => "\\" }.freeze,
                          T::Hash[String, String])
    private_constant :VALUE_ESCAPES

    # Characters an `Exec` argument must be quoted for.
    # Ref: https://specifications.freedesktop.org/desktop-entry/latest/exec-variables.html
    EXEC_RESERVED_CHARACTERS = /[\s"'\\<>~|&;$*?#()`]/
    private_constant :EXEC_RESERVED_CHARACTERS

    sig { params(contents: String).void }
    def initialize(contents)
      @lines = T.let(contents.scrub.lines(chomp: true), T::Array[String])
    end

    # Whether the first group is `[Desktop Entry]`, as the spec requires of desktop entries.
    sig { returns(T::Boolean) }
    def desktop_entry?
      @lines.find { |line| line.strip.present? && !line.start_with?("#") }&.strip == "[#{DESKTOP_ENTRY_GROUP}]"
    end

    # The value of `key` in the `[Desktop Entry]` group, with escape sequences resolved.
    sig { params(key: String).returns(T.nilable(String)) }
    def get(key)
      each_value(key) { |value, group| return value if group == DESKTOP_ENTRY_GROUP }
      nil
    end

    # Replace the value of `key` in every group that sets it with the block's result.
    sig { params(key: String, block: T.proc.params(value: String).returns(String)).void }
    def update(key, &block)
      each_value(key) do |value, _group, index|
        # Reverse of the escape sequences `each_value` resolves.
        value = yield(value).gsub(/[\\\n\t\r]/, "\\" => "\\\\", "\n" => "\\n", "\t" => "\\t", "\r" => "\\r")
        @lines[index] = "#{key}=#{value}"
      end
    end

    # Replace the program each `Exec` and `TryExec` names with the block's result for it,
    # keeping the arguments and environment variables of each `Exec` and setting `environment`
    # with `env`, e.g. for a block returning `"<target>"` and
    # `environment: { "DESKTOPINTEGRATION" => "1" }`:
    #   Input:  Exec=env GDK_BACKEND=x11 UBUNTU_MENUPROXY=0 audacity %F
    #   Output: Exec=env DESKTOPINTEGRATION=1 GDK_BACKEND=x11 UBUNTU_MENUPROXY=0 <target> %F
    # Raises `ArgumentError` if an `Exec` has unmatched quotes.
    sig {
      params(environment: T::Hash[String, String], block: T.proc.params(program: String).returns(String)).void
    }
    def replace_program(environment: {}, &block)
      update("TryExec", &block)
      update("Exec") do |exec|
        words = Shellwords.split(exec)
        # Variables can be set with or without a leading `env` or `/usr/bin/env`.
        words.shift if %w[env /usr/bin/env].include?(words.first)
        variables = words.take_while { |word| word.match?(/\A[A-Za-z_]\w*=/) }
        program = yield(words.fetch(variables.length, ""))
        arguments = words.drop(variables.length + 1)
        # `environment` takes precedence over the same variables in `exec`.
        variables.reject! { |variable| environment.key?(variable.split("=", 2).fetch(0)) }
        variables = environment.map { |name, value| "#{name}=#{value}" } + variables
        variables.unshift("env") if variables.present?
        # `%` starts a field code like `%U`, so a literal one in `program` must be doubled.
        [*variables, program.gsub("%", "%%"), *arguments].map do |word|
          # Quote only what needs it, as some launchers split `Exec` on spaces and keep the quotes.
          next word unless word.match?(EXEC_RESERVED_CHARACTERS)

          # Surround with quotes and precede `"`, `` ` ``, `$` and `\` with `\`.
          quoted_word = word.gsub(/["`$\\]/) { |character| "\\#{character}" }
          "\"#{quoted_word}\""
        end.join(" ")
      end
    end

    sig { returns(String) }
    def to_s
      "#{@lines.join("\n")}\n"
    end

    private

    # Yield the value of each line setting `key`, with escape sequences resolved,
    # along with its group and line index.
    sig { params(key: String, block: T.proc.params(value: String, group: String, index: Integer).void).void }
    def each_value(key, &block)
      group = T.let(nil, T.nilable(String))
      @lines.each_with_index do |line, index|
        if (name = line.strip[/\A\[([^\[\]]+)\]\z/, 1])
          group = name
          next
        end
        next if group.nil? || line.start_with?("#") || line.exclude?("=")

        # Split at the first `=` only, as values may contain more.
        line_key, value = line.split("=", 2)
        # Keys are case-sensitive and include any locale, so `Name` doesn't match `Name[de]`.
        next if line_key.to_s.strip != key

        value = value.to_s.strip.gsub(/\\(.)/) do
          character = Regexp.last_match(1).to_s
          # Keep unknown escapes such as `\;`, used within lists, for the caller.
          VALUE_ESCAPES.fetch(character, "\\#{character}")
        end
        yield(value, group, index)
      end
    end
  end
end
