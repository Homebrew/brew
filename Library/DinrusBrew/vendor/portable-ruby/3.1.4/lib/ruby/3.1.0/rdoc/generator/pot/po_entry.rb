# frozen_string_literal: true
##
# A PO entry in PO

class RDoc::Generator::POT::POEntry

  # The msgid content
  attr_reader :msgid

  # The msgstr content
  attr_reader :msgstr

  # The comment content created by translator (PO editor)
  attr_reader :translator_comment

  # The comment content extracted from source file
  attr_reader :extracted_comment

  # The locations where the PO entry is extracted
  attr_reader :references

  # The flags of the PO entry
  attr_reader :flags

  ##
  # Creates a PO entry for +msgid+. Other valus can be specified by
  # +options+.

  def initialize msgid, options = {}
    @msgid = msgid
    @msgstr = options[:msgstr] || ""
    @translator_comment = options[:translator_comment]
    @extracted_comment = options[:extracted_comment]
    @references = options[:references] || []
    @flags = options[:flags] || []
  end

  ##
  # Returns the PO entry in PO format.

  def to_s
    entry = ''
    entry += format_translator_comment
    entry += format_extracted_comment
    entry += format_references
    entry += format_flags
    entry += <<-ENTRY
msgid #{format_message(@msgid)}
msgstr #{format_message(@msgstr)}
    ENTRY
  end

  ##
  # Merges the PO entry with +other_entry+.

  def merge other_entry
    options = {
      :extracted_comment  => merge_string(@extracted_comment,
                                          other_entry.extracted_comment),
      :translator_comment => merge_string(@translator_comment,
                                          other_entry.translator_comment),
      :references         => merge_array(@references,
                                         other_entry.references),
      :flags              => merge_array(@flags,
                                         other_entry.flags),
    }
    self.class.new(@msgid, options)
  end

  private

  def format_comment mark, comment
    return '' unless comment
    return '' if comment.empty?

    formatted_comment = ''
    comment.each_line do |line|
      formatted_comment += "#{mark} #{line}"
    end
    formatted_comment += "\n" unless formatted_comment.end_with?("\n")
    formatted_comment
  end

  def format_translator_comment
    format_comment('#', @translator_comment)
  end

  def format_extracted_comment
    format_comment('#.', @extracted_comment)
  end

  def format_references
    return '' if @references.empty?

    formatted_references = ''
    @references.sort.each do |file, line|
      formatted_references += "\#: #{file}:#{line}\n"
    end
    formatted_references
  end

  def format_flags
    return '' if @flags.empty?

    formatted_flags = flags.join(",")
    "\#, #{formatted_flags}\n"
  end

  def format_message message
    return "\"#{escape(message)}\"" unless message.include?("\n")

    formatted_message = '""'
    message.each_line do |line|
      formatted_message += "\n"
      formatted_message += "\"#{escape(line)}\""
    end
    formatted_message
  end

  def escape string
    string.gsub(/["\\\t\n]/) do |special_character|
      case special_character
      when "\t"
        "\\t"
      when "\n"
        "\\n"
      else
        "\\#{special_character}"
      end
    end
  end

  def merge_string string1, string2
    [string1, string2].compact.join("\n")
  end

  def merge_array array1, array2
      (array1 + array2).uniq
  end

end
