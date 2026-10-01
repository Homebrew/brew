# typed: strict
# frozen_string_literal: true

require "utils/tty"

# Helper module for formatting output.
#
# @api internal
module Formatter
  COMMAND_DESC_WIDTH = 80
  OPTION_DESC_WIDTH = 45

  sig { params(string: String, color: T.nilable(Symbol)).returns(String) }
  def self.arrow(string, color: nil)
    prefix("==>", string, color)
  end

  # Format a string as headline.
  #
  # @api internal
  # Keep in sync with `headline` in Library/Homebrew/utils/formatter.sh.
  sig { params(string: String, color: T.nilable(Symbol)).returns(String) }
  def self.headline(string, color: nil)
    arrow("#{Tty.bold}#{string}#{Tty.reset}", color:)
  end

  sig { params(string: Object).returns(String) }
  def self.identifier(string)
    "#{Tty.green}#{string}#{Tty.default}"
  end

  # Keep in sync with `bold` in Library/Homebrew/utils/formatter.sh.
  sig { params(string: String).returns(String) }
  def self.bold(string)
    "#{Tty.bold}#{string}#{Tty.reset}"
  end

  sig { params(string: String).returns(String) }
  def self.option(string)
    bold(string)
  end

  # Format a string as success, with an optional label.
  #
  # @api internal
  sig { params(string: String, label: T.nilable(String)).returns(String) }
  def self.success(string, label: nil)
    label(label, string, :green)
  end

  # Format a string as warning, with an optional label.
  #
  # @api internal
  sig { params(string: T.any(String, Exception), label: T.nilable(String)).returns(String) }
  def self.warning(string, label: nil)
    label(label, string, :yellow)
  end

  # Format a string as error, with an optional label.
  #
  # @api internal
  sig { params(string: T.any(String, Exception), label: T.nilable(String)).returns(String) }
  def self.error(string, label: nil)
    label(label, string, :red)
  end

  # Truncate a string to a specific length.
  #
  # @api internal
  sig { params(string: String, max: Integer, omission: String).returns(String) }
  def self.truncate(string, max: 30, omission: "...")
    return string if string.length <= max

    length_with_room_for_omission = max - omission.length
    truncated = string[0, length_with_room_for_omission]

    "#{truncated}#{omission}"
  end

  # Wraps text to fit within a given number of columns using regular expressions that:
  #
  # 1. convert hard-wrapped paragraphs to a single line
  # 2. add line break and indent to subcommand descriptions
  # 3. find any option descriptions longer than a pre-set length and wrap between words
  #    with a hanging indent, without breaking any words that overflow
  # 4. wrap any remaining description lines that need wrapping with the same indent
  # 5. wrap all lines to the given width.
  #
  # Note that an option (e.g. `--foo`) may not be at the beginning of a line,
  # so we always wrap one word before an option.
  # @see https://github.com/Homebrew/brew/pull/12672
  # @see https://macromates.com/blog/2006/wrapping-text-with-regular-expressions/
  sig { params(string: String, width: Integer).returns(String) }
  def self.format_help_text(string, width: 172)
    desc = OPTION_DESC_WIDTH
    indent = width - desc
    string.gsub(/(?<=\S) *\n(?=\S)/, " ")
          .gsub(/([`>)\]]:) /, "\\1\n    ")
          .gsub(/^( +-.+  +(?=\S.{#{desc}}))(.{1,#{desc}})(?: +|$)(?!-)\n?/, "\\1\\2\n#{" " * indent}")
          .gsub(/^( {#{indent}}(?=\S.{#{desc}}))(.{1,#{desc}})(?: +|$)(?!-)\n?/, "\\1\\2\n#{" " * indent}")
          .gsub(/(.{1,#{width}})(?: +|$)(?!-)\n?/, "\\1\n")
  end

  T::Sig::WithoutRuntime.sig { params(string: T.nilable(T.any(String, URI::Generic))).returns(String) }
  def self.url(string)
    "#{Tty.underline}#{string}#{Tty.no_underline}"
  end

  sig { params(label: T.nilable(String), string: T.any(String, Exception), color: Symbol).returns(String) }
  def self.label(label, string, color)
    label = "#{label}:" unless label.nil?
    prefix(label, string, color)
  end
  private_class_method :label

  sig {
    params(prefix: T.nilable(String), string: T.any(String, Exception), color: T.nilable(Symbol)).returns(String)
  }
  def self.prefix(prefix, string, color)
    if color.nil?
      prefix.nil? ? string.to_s : "#{prefix} #{string}"
    elsif prefix.nil?
      "#{Tty.public_send(color)}#{string}#{Tty.reset}"
    else
      "#{Tty.public_send(color)}#{prefix}#{Tty.reset} #{string}"
    end
  end
  private_class_method :prefix

  # Layout objects in columns that fit the current terminal width.
  #
  # @api internal
  sig { params(objects: T::Array[String], gap_size: Integer, min_width: Integer).returns(String) }
  def self.columns(objects, gap_size: 2, min_width: 0)
    objects = objects.flatten.map(&:to_s)

    fallback = proc do
      return objects.join("\n").concat("\n")
    end

    fallback.call if objects.empty?
    fallback.call unless $stdout.tty?

    console_width = Tty.width
    object_lengths = objects.map { |obj| Tty.strip_ansi(obj).length }
    max_length = [*object_lengths, min_width].max || 0
    cols = (console_width + gap_size) / (max_length + gap_size)

    fallback.call if cols < 2

    rows = (objects.count + cols - 1) / cols
    cols = (objects.count + rows - 1) / rows if min_width.zero? # avoid empty trailing columns
    col_width = ((console_width + gap_size) / cols) - gap_size

    gap_string = "".rjust(gap_size)

    output = +""

    rows.times do |row_index|
      item_indices_for_row = T.cast(row_index.step(objects.size - 1, rows).to_a, T::Array[Integer])

      first_n = item_indices_for_row.first(item_indices_for_row.size - 1).map do |index|
        objects.fetch(index) + "".rjust(col_width - object_lengths.fetch(index))
      end

      # don't add trailing whitespace to last column
      last = objects.values_at(item_indices_for_row.fetch(-1))

      output.concat((first_n + last)
            .join(gap_string))
            .concat("\n")
    end

    output.freeze
  end

  sig {
    params(
      size_in_bytes: T.any(Integer, Float),
      precision:     T.nilable(Integer),
    ).returns([T.any(Integer, Float), String])
  }
  def self.disk_usage_readable_size_unit(size_in_bytes, precision: nil)
    size = size_in_bytes
    unit = "B"
    %w[KB MB GB].each do |next_unit|
      break if (precision ? size.abs.round(precision) : size.abs) < 1000

      size /= 1000.0
      unit = next_unit
    end
    [size, unit]
  end

  sig { params(size_in_bytes: T.any(Integer, Float)).returns(String) }
  def self.disk_usage_readable(size_in_bytes)
    size, unit = disk_usage_readable_size_unit(size_in_bytes)
    # avoid trailing zero after decimal point
    if ((size * 10).to_i % 10).zero?
      "#{size.to_i}#{unit}"
    else
      "#{format("%<size>.1f", size:)}#{unit}"
    end
  end

  sig { params(number: Integer).returns(String) }
  def self.number_readable(number)
    number.to_i.to_s.gsub(/(\d)(?=(?:\d{3})+\z)/, "\\1,")
  end

  sig { params(input: String, secrets: T::Array[String]).returns(String) }
  def self.redact_secrets(input, secrets)
    secrets.compact
           .reduce(input) { |str, secret| str.gsub secret, "******" }
           .freeze
  end
end
