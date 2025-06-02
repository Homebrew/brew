# frozen_string_literal: true

module SyntaxSuggest
  # Parses and sanitizes source into a lexically aware document
  #
  # Internally the document is represented by an array with each
  # index containing a CodeLine correlating to a line from the source code.
  #
  # There are three main phases in the algorithm:
  #
  # 1. Sanitize/format input source
  # 2. Search for invalid blocks
  # 3. Format invalid blocks into something meaninful
  #
  # This class handles the first part.
  #
  # The reason this class exists is to format input source
  # for better/easier/cleaner exploration.
  #
  # The CodeSearch class operates at the line level so
  # we must be careful to not introduce lines that look
  # valid by themselves, but when removed will trigger syntax errors
  # or strange behavior.
  #
  # ## Join Trailing slashes
  #
  # Code with a trailing slash is logically treated as a single line:
  #
  #     1 it "code can be split" \
  #     2    "across multiple lines" do
  #
  # In this case removing line 2 would add a syntax error. We get around
  # this by internally joining the two lines into a single "line" object
  #
  # ## Logically Consecutive lines
  #
  # Code that can be broken over multiple
  # lines such as method calls are on different lines:
  #
  #     1 User.
  #     2   where(name: "schneems").
  #     3   first
  #
  # Removing line 2 can introduce a syntax error. To fix this, all lines
  # are joined into one.
  #
  # ## Heredocs
  #
  # A heredoc is an way of defining a multi-line string. They can cause many
  # problems. If left as a single line, the parser would try to parse the contents
  # as ruby code rather than as a string. Even without this problem, we still
  # hit an issue with indentation:
  #
  #    1 foo = <<~HEREDOC
  #    2  "Be yourself; everyone else is already taken.""
  #    3    ― Oscar Wilde
  #    4      puts "I look like ruby code" # but i'm still a heredoc
  #    5 HEREDOC
  #
  # If we didn't join these lines then our algorithm would think that line 4
  # is separate from the rest, has a higher indentation, then look at it first
  # and remove it.
  #
  # If the code evaluates line 5 by itself it will think line 5 is a constant,
  # remove it, and introduce a syntax errror.
  #
  # All of these problems are fixed by joining the whole heredoc into a single
  # line.
  #
  # ## Comments and whitespace
  #
  # Comments can throw off the way the lexer tells us that the line
  # logically belongs with the next line. This is valid ruby but
  # results in a different lex output than before:
  #
  #     1 User.
  #     2   where(name: "schneems").
  #     3   # Comment here
  #     4   first
  #
  # To handle this we can replace comment lines with empty lines
  # and then re-lex the source. This removal and re-lexing preserves
  # line index and document size, but generates an easier to work with
  # document.
  #
  class CleanDocument
    def initialize(source:)
      lines = clean_sweep(source: source)
      @document = CodeLine.from_source(lines.join, lines: lines)
    end

    # Call all of the document "cleaners"
    # and return self
    def call
      join_trailing_slash!
      join_consecutive!
      join_heredoc!

      self
    end

    # Return an array of CodeLines in the
    # document
    def lines
      @document
    end

    # Renders the document back to a string
    def to_s
      @document.join
    end

    # Remove comments
    #
    # replace with empty newlines
    #
    #     source = <<~'EOM'
    #       # Comment 1
    #       puts "hello"
    #       # Comment 2
    #       puts "world"
    #     EOM
    #
    #     lines = CleanDocument.new(source: source).lines
    #     expect(lines[0].to_s).to eq("\n")
    #     expect(lines[1].to_s).to eq("puts "hello")
    #     expect(lines[2].to_s).to eq("\n")
    #     expect(lines[3].to_s).to eq("puts "world")
    #
    # Important: This must be done before lexing.
    #
    # After this change is made, we lex the document because
    # removing comments can change how the doc is parsed.
    #
    # For example:
    #
    #     values = LexAll.new(source: <<~EOM))
    #       User.
    #         # comment
    #         where(name: 'schneems')
    #     EOM
    #     expect(
    #       values.count {|v| v.type == :on_ignored_nl}
    #     ).to eq(1)
    #
    # After the comment is removed:
    #
    #     values = LexAll.new(source: <<~EOM))
    #       User.
    #
    #         where(name: 'schneems')
    #     EOM
    #     expect(
    #      values.count {|v| v.type == :on_ignored_nl}
    #    ).to eq(2)
    #
    def clean_sweep(source:)
      # Match comments, but not HEREDOC strings with #{variable} interpolation
      # https://rubular.com/r/HPwtW9OYxKUHXQ
      source.lines.map do |line|
        if line.match?(/^\s*#([^{].*|)$/)
          $/
        else
          line
        end
      end
    end

    # Smushes all heredoc lines into one line
    #
    #     source = <<~'EOM'
    #       foo = <<~HEREDOC
    #          lol
    #          hehehe
    #       HEREDOC
    #     EOM
    #
    #     lines = CleanDocument.new(source: source).join_heredoc!.lines
    #     expect(lines[0].to_s).to eq(source)
    #     expect(lines[1].to_s).to eq("")
    def join_heredoc!
      start_index_stack = []
      heredoc_beg_end_index = []
      lines.each do |line|
        line.lex.each do |lex_value|
          case lex_value.type
          when :on_heredoc_beg
            start_index_stack << line.index
          when :on_heredoc_end
            start_index = start_index_stack.pop
            end_index = line.index
            heredoc_beg_end_index << [start_index, end_index]
          end
        end
      end

      heredoc_groups = heredoc_beg_end_index.map { |start_index, end_index| @document[start_index..end_index] }

      join_groups(heredoc_groups)
      self
    end

    # Smushes logically "consecutive" lines
    #
    #     source = <<~'EOM'
    #       User.
    #         where(name: 'schneems').
    #         first
    #     EOM
    #
    #     lines = CleanDocument.new(source: source).join_consecutive!.lines
    #     expect(lines[0].to_s).to eq(source)
    #     expect(lines[1].to_s).to eq("")
    #
    # The one known case this doesn't handle is:
    #
    #     Ripper.lex <<~EOM
    #       a &&
    #        b ||
    #        c
    #     EOM
    #
    # For some reason this introduces `on_ignore_newline` but with BEG type
    #
    def join_consecutive!
      consecutive_groups = @document.select(&:ignore_newline_not_beg?).map do |code_line|
        take_while_including(code_line.index..) do |line|
          line.ignore_newline_not_beg?
        end
      end

      join_groups(consecutive_groups)
      self
    end

    # Join lines with a trailing slash
    #
    #     source = <<~'EOM'
    #       it "code can be split" \
    #          "across multiple lines" do
    #     EOM
    #
    #     lines = CleanDocument.new(source: source).join_consecutive!.lines
    #     expect(lines[0].to_s).to eq(source)
    #     expect(lines[1].to_s).to eq("")
    def join_trailing_slash!
      trailing_groups = @document.select(&:trailing_slash?).map do |code_line|
        take_while_including(code_line.index..) { |x| x.trailing_slash? }
      end
      join_groups(trailing_groups)
      self
    end

    # Helper method for joining "groups" of lines
    #
    # Input is expected to be type Array<Array<CodeLine>>
    #
    # The outer array holds the various "groups" while the
    # inner array holds code lines.
    #
    # All code lines are "joined" into the first line in
    # their group.
    #
    # To preserve document size, empty lines are placed
    # in the place of the lines that were "joined"
    def join_groups(groups)
      groups.each do |lines|
        line = lines.first

        # Handle the case of multiple groups in a row
        # if one is already replaced, move on
        next if @document[line.index].empty?

        # Join group into the first line
        @document[line.index] = CodeLine.new(
          lex: lines.map(&:lex).flatten,
          line: lines.join,
          index: line.index
        )

        # Hide the rest of the lines
        lines[1..].each do |line|
          # The above lines already have newlines in them, if add more
          # then there will be double newline, use an empty line instead
          @document[line.index] = CodeLine.new(line: "", index: line.index, lex: [])
        end
      end
      self
    end

    # Helper method for grabbing elements from document
    #
    # Like `take_while` except when it stops
    # iterating, it also returns the line
    # that caused it to stop
    def take_while_including(range = 0..)
      take_next_and_stop = false
      @document[range].take_while do |line|
        next if take_next_and_stop

        take_next_and_stop = !(yield line)
        true
      end
    end
  end
end
