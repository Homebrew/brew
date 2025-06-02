# frozen_string_literal: true

##
# Manages changes of attributes in a block of text

class RDoc::Markup::AttributeManager
  unless ::MatchData.method_defined?(:match_length)
    using ::Module.new {
      refine(::MatchData) {
        def match_length(nth) # :nodoc:
          b, e = offset(nth)
          e - b if b
        end
      }
    }
  end

  ##
  # The NUL character

  NULL = "\000".freeze

  #--
  # We work by substituting non-printing characters in to the text. For now
  # I'm assuming that I can substitute a character in the range 0..8 for a 7
  # bit character without damaging the encoded string, but this might be
  # optimistic
  #++

  A_PROTECT = 004 # :nodoc:

  ##
  # Special mask character to prevent inline markup handling

  PROTECT_ATTR = A_PROTECT.chr # :nodoc:

  ##
  # The attributes enabled for this markup object.

  attr_reader :attributes

  ##
  # This maps delimiters that occur around words (such as *bold* or +tt+)
  # where the start and end delimiters and the same. This lets us optimize
  # the regexp

  attr_reader :matching_word_pairs

  ##
  # And this is used when the delimiters aren't the same. In this case the
  # hash maps a pattern to the attribute character

  attr_reader :word_pair_map

  ##
  # This maps HTML tags to the corresponding attribute char

  attr_reader :html_tags

  ##
  # A \ in front of a character that would normally be processed turns off
  # processing. We do this by turning \< into <#{PROTECT}

  attr_reader :protectable

  ##
  # And this maps _regexp handling_ sequences to a name. A regexp handling
  # sequence is something like a WikiWord

  attr_reader :regexp_handlings

  ##
  # A bits of exclusive maps
  attr_reader :exclusive_bitmap

  ##
  # Creates a new attribute manager that understands bold, emphasized and
  # teletype text.

  def initialize
    @html_tags = {}
    @matching_word_pairs = {}
    @protectable = %w[<]
    @regexp_handlings = []
    @word_pair_map = {}
    @exclusive_bitmap = 0
    @attributes = RDoc::Markup::Attributes.new

    add_word_pair "*", "*", :BOLD, true
    add_word_pair "_", "_", :EM, true
    add_word_pair "+", "+", :TT, true

    add_html "em", :EM, true
    add_html "i",  :EM, true
    add_html "b",  :BOLD, true
    add_html "tt",   :TT, true
    add_html "code", :TT, true
  end

  ##
  # Return an attribute object with the given turn_on and turn_off bits set

  def attribute(turn_on, turn_off)
    RDoc::Markup::AttrChanger.new turn_on, turn_off
  end

  ##
  # Changes the current attribute from +current+ to +new+

  def change_attribute current, new
    diff = current ^ new
    attribute(new & diff, current & diff)
  end

  ##
  # Used by the tests to change attributes by name from +current_set+ to
  # +new_set+

  def changed_attribute_by_name current_set, new_set
    current = new = 0
    current_set.each do |name|
      current |= @attributes.bitmap_for(name)
    end

    new_set.each do |name|
      new |= @attributes.bitmap_for(name)
    end

    change_attribute(current, new)
  end

  ##
  # Copies +start_pos+ to +end_pos+ from the current string

  def copy_string(start_pos, end_pos)
    res = @str[start_pos...end_pos]
    res.gsub!(/\000/, '')
    res
  end

  # :nodoc:
  def exclusive?(attr)
    (attr & @exclusive_bitmap) != 0
  end

  NON_PRINTING_START = "\1" # :nodoc:
  NON_PRINTING_END = "\2" # :nodoc:

  ##
  # Map attributes like <b>text</b>to the sequence
  # \001\002<char>\001\003<char>, where <char> is a per-attribute specific
  # character

  def convert_attrs(str, attrs, exclusive = false)
    convert_attrs_matching_word_pairs(str, attrs, exclusive)
    convert_attrs_word_pair_map(str, attrs, exclusive)
  end

  # :nodoc:
  def convert_attrs_matching_word_pairs(str, attrs, exclusive)
    # first do matching ones
    tags = @matching_word_pairs.select { |start, bitmap|
      exclusive == exclusive?(bitmap)
    }.keys
    return if tags.empty?
    tags = "[#{tags.join("")}](?!#{PROTECT_ATTR})"
    all_tags = "[#{@matching_word_pairs.keys.join("")}](?!#{PROTECT_ATTR})"

    re = /(?:^|\W|#{all_tags})\K(#{tags})(\1*[#\\]?[\w:#{PROTECT_ATTR}.\/\[\]-]+?\S?)\1(?!\1)(?=#{all_tags}|\W|$)/

    1 while str.gsub!(re) { |orig|
      a, w = (m = $~).values_at(1, 2)
      attr = @matching_word_pairs[a]
      if attrs.set_attrs(m.begin(2), w.length, attr)
        a = NULL * a.length
      else
        a = NON_PRINTING_START + a + NON_PRINTING_END
      end
      a + w + a
    }
    str.delete!(NON_PRINTING_START + NON_PRINTING_END)
  end

  # :nodoc:
  def convert_attrs_word_pair_map(str, attrs, exclusive)
    # then non-matching
    unless @word_pair_map.empty? then
      @word_pair_map.each do |regexp, attr|
        next unless exclusive == exclusive?(attr)
        1 while str.gsub!(regexp) { |orig|
          w = (m = ($~))[2]
          updated = attrs.set_attrs(m.begin(2), w.length, attr)
          if updated
            NULL * m.match_length(1) + w + NULL * m.match_length(3)
          else
            orig
          end
        }
      end
    end
  end

  ##
  # Converts HTML tags to RDoc attributes

  def convert_html(str, attrs, exclusive = false)
    tags = @html_tags.select { |start, bitmap|
      exclusive == exclusive?(bitmap)
    }.keys.join '|'

    1 while str.gsub!(/<(#{tags})>(.*?)<\/\1>/i) { |orig|
      attr = @html_tags[$1.downcase]
      html_length = $~.match_length(1) + 2 # "<>".length
      seq = NULL * html_length
      attrs.set_attrs($~.begin(2), $~.match_length(2), attr)
      seq + $2 + seq + NULL
    }
  end

  ##
  # Converts regexp handling sequences to RDoc attributes

  def convert_regexp_handlings str, attrs, exclusive = false
    @regexp_handlings.each do |regexp, attribute|
      next unless exclusive == exclusive?(attribute)
      str.scan(regexp) do
        capture = $~.size == 1 ? 0 : 1

        s, e = $~.offset capture

        attrs.set_attrs s, e - s, attribute | @attributes.regexp_handling
      end
    end
  end

  ##
  # Escapes regexp handling sequences of text to prevent conversion to RDoc

  def mask_protected_sequences
    # protect __send__, __FILE__, etc.
    @str.gsub!(/__([a-z]+)__/i,
      "_#{PROTECT_ATTR}_#{PROTECT_ATTR}\\1_#{PROTECT_ATTR}_#{PROTECT_ATTR}")
    @str.gsub!(/(\A|[^\\])\\([#{Regexp.escape @protectable.join}])/m,
               "\\1\\2#{PROTECT_ATTR}")
    @str.gsub!(/\\(\\[#{Regexp.escape @protectable.join}])/m, "\\1")
  end

  ##
  # Unescapes regexp handling sequences of text

  def unmask_protected_sequences
    @str.gsub!(/(.)#{PROTECT_ATTR}/, "\\1\000")
  end

  ##
  # Adds a markup class with +name+ for words wrapped in the +start+ and
  # +stop+ character.  To make words wrapped with "*" bold:
  #
  #   am.add_word_pair '*', '*', :BOLD

  def add_word_pair(start, stop, name, exclusive = false)
    raise ArgumentError, "Word flags may not start with '<'" if
      start[0,1] == '<'

    bitmap = @attributes.bitmap_for name

    if start == stop then
      @matching_word_pairs[start] = bitmap
    else
      pattern = /(#{Regexp.escape start})(\S+)(#{Regexp.escape stop})/
      @word_pair_map[pattern] = bitmap
    end

    @protectable << start[0,1]
    @protectable.uniq!

    @exclusive_bitmap |= bitmap if exclusive
  end

  ##
  # Adds a markup class with +name+ for words surrounded by HTML tag +tag+.
  # To process emphasis tags:
  #
  #   am.add_html 'em', :EM

  def add_html(tag, name, exclusive = false)
    bitmap = @attributes.bitmap_for name
    @html_tags[tag.downcase] = bitmap
    @exclusive_bitmap |= bitmap if exclusive
  end

  ##
  # Adds a regexp handling for +pattern+ with +name+.  A simple URL handler
  # would be:
  #
  #   @am.add_regexp_handling(/((https?:)\S+\w)/, :HYPERLINK)

  def add_regexp_handling pattern, name, exclusive = false
    bitmap = @attributes.bitmap_for(name)
    @regexp_handlings << [pattern, bitmap]
    @exclusive_bitmap |= bitmap if exclusive
  end

  ##
  # Processes +str+ converting attributes, HTML and regexp handlings

  def flow str
    @str = str.dup

    mask_protected_sequences

    @attrs = RDoc::Markup::AttrSpan.new @str.length, @exclusive_bitmap

    convert_attrs            @str, @attrs, true
    convert_html             @str, @attrs, true
    convert_regexp_handlings @str, @attrs, true
    convert_attrs            @str, @attrs
    convert_html             @str, @attrs
    convert_regexp_handlings @str, @attrs

    unmask_protected_sequences

    split_into_flow
  end

  ##
  # Debug method that prints a string along with its attributes

  def display_attributes
    puts
    puts @str.tr(NULL, "!")
    bit = 1
    16.times do |bno|
      line = ""
      @str.length.times do |i|
        if (@attrs[i] & bit) == 0
          line << " "
        else
          if bno.zero?
            line << "S"
          else
            line << ("%d" % (bno+1))
          end
        end
      end
      puts(line) unless line =~ /^ *$/
      bit <<= 1
    end
  end

  ##
  # Splits the string into chunks by attribute change

  def split_into_flow
    res = []
    current_attr = 0

    str_len = @str.length

    # skip leading invisible text
    i = 0
    i += 1 while i < str_len and @str[i].chr == "\0"
    start_pos = i

    # then scan the string, chunking it on attribute changes
    while i < str_len
      new_attr = @attrs[i]
      if new_attr != current_attr
        if i > start_pos
          res << copy_string(start_pos, i)
          start_pos = i
        end

        res << change_attribute(current_attr, new_attr)
        current_attr = new_attr

        if (current_attr & @attributes.regexp_handling) != 0 then
          i += 1 while
            i < str_len and (@attrs[i] & @attributes.regexp_handling) != 0

          res << RDoc::Markup::RegexpHandling.new(current_attr,
                                                  copy_string(start_pos, i))
          start_pos = i
          next
        end
      end

      # move on, skipping any invisible characters
      begin
        i += 1
      end while i < str_len and @str[i].chr == "\0"
    end

    # tidy up trailing text
    if start_pos < str_len
      res << copy_string(start_pos, str_len)
    end

    # and reset to all attributes off
    res << change_attribute(current_attr, 0) if current_attr != 0

    res
  end

end
