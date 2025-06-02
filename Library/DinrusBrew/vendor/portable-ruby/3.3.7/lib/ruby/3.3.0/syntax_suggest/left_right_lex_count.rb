# frozen_string_literal: true

module SyntaxSuggest
  # Find mis-matched syntax based on lexical count
  #
  # Used for detecting missing pairs of elements
  # each keyword needs an end, each '{' needs a '}'
  # etc.
  #
  # Example:
  #
  #   left_right = LeftRightLexCount.new
  #   left_right.count_kw
  #   left_right.missing.first
  #   # => "end"
  #
  #   left_right = LeftRightLexCount.new
  #   source = "{ a: b, c: d" # Note missing '}'
  #   LexAll.new(source: source).each do |lex|
  #     left_right.count_lex(lex)
  #   end
  #   left_right.missing.first
  #   # => "}"
  class LeftRightLexCount
    def initialize
      @kw_count = 0
      @end_count = 0

      @count_for_char = {
        "{" => 0,
        "}" => 0,
        "[" => 0,
        "]" => 0,
        "(" => 0,
        ")" => 0,
        "|" => 0
      }
    end

    def count_kw
      @kw_count += 1
    end

    def count_end
      @end_count += 1
    end

    # Count source code characters
    #
    # Example:
    #
    #   left_right = LeftRightLexCount.new
    #   left_right.count_lex(LexValue.new(1, :on_lbrace, "{", Ripper::EXPR_BEG))
    #   left_right.count_for_char("{")
    #   # => 1
    #   left_right.count_for_char("}")
    #   # => 0
    def count_lex(lex)
      case lex.type
      when :on_tstring_content
        # ^^^
        # Means it's a string or a symbol `"{"` rather than being
        # part of a data structure (like a hash) `{ a: b }`
        # ignore it.
      when :on_words_beg, :on_symbos_beg, :on_qwords_beg,
           :on_qsymbols_beg, :on_regexp_beg, :on_tstring_beg
        # ^^^
        # Handle shorthand syntaxes like `%Q{ i am a string }`
        #
        # The start token will be the full thing `%Q{` but we
        # need to count it as if it's a `{`. Any token
        # can be used
        char = lex.token[-1]
        @count_for_char[char] += 1 if @count_for_char.key?(char)
      when :on_embexpr_beg
        # ^^^
        # Embedded string expressions like `"#{foo} <-embed"`
        # are parsed with chars:
        #
        # `#{` as :on_embexpr_beg
        #  `}` as :on_embexpr_end
        #
        # We cannot ignore both :on_emb_expr_beg and :on_embexpr_end
        # because sometimes the lexer thinks something is an embed
        # string end, when it is not like `lol = }` (no clue why).
        #
        # When we see `#{` count it as a `{` or we will
        # have a mis-match count.
        #
        case lex.token
        when "\#{"
          @count_for_char["{"] += 1
        end
      else
        @end_count += 1 if lex.is_end?
        @kw_count += 1 if lex.is_kw?
        @count_for_char[lex.token] += 1 if @count_for_char.key?(lex.token)
      end
    end

    def count_for_char(char)
      @count_for_char[char]
    end

    # Returns an array of missing syntax characters
    # or `"end"` or `"keyword"`
    #
    #   left_right.missing
    #   # => ["}"]
    def missing
      out = missing_pairs
      out << missing_pipe
      out << missing_keyword_end
      out.compact!
      out
    end

    PAIRS = {
      "{" => "}",
      "[" => "]",
      "(" => ")"
    }.freeze

    # Opening characters like `{` need closing characters # like `}`.
    #
    # When a mis-match count is detected, suggest the
    # missing member.
    #
    # For example if there are 3 `}` and only two `{`
    # return `"{"`
    private def missing_pairs
      PAIRS.map do |(left, right)|
        case @count_for_char[left] <=> @count_for_char[right]
        when 1
          right
        when 0
          nil
        when -1
          left
        end
      end
    end

    # Keywords need ends and ends need keywords
    #
    # If we have more keywords, there's a missing `end`
    # if we have more `end`-s, there's a missing keyword
    private def missing_keyword_end
      case @kw_count <=> @end_count
      when 1
        "end"
      when 0
        nil
      when -1
        "keyword"
      end
    end

    # Pipes come in pairs.
    # If there's an odd number of pipes then we
    # are missing one
    private def missing_pipe
      if @count_for_char["|"].odd?
        "|"
      end
    end
  end
end
