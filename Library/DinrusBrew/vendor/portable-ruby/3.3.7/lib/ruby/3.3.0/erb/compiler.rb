# frozen_string_literal: true
#--
# ERB::Compiler
#
# Compiles ERB templates into Ruby code; the compiled code produces the
# template result when evaluated. ERB::Compiler provides hooks to define how
# generated output is handled.
#
# Internally ERB does something like this to generate the code returned by
# ERB#src:
#
#   compiler = ERB::Compiler.new('<>')
#   compiler.pre_cmd    = ["_erbout=+''"]
#   compiler.put_cmd    = "_erbout.<<"
#   compiler.insert_cmd = "_erbout.<<"
#   compiler.post_cmd   = ["_erbout"]
#
#   code, enc = compiler.compile("Got <%= obj %>!\n")
#   puts code
#
# <i>Generates</i>:
#
#   #coding:UTF-8
#   _erbout=+''; _erbout.<< "Got ".freeze; _erbout.<<(( obj ).to_s); _erbout.<< "!\n".freeze; _erbout
#
# By default the output is sent to the print method.  For example:
#
#   compiler = ERB::Compiler.new('<>')
#   code, enc = compiler.compile("Got <%= obj %>!\n")
#   puts code
#
# <i>Generates</i>:
#
#   #coding:UTF-8
#   print "Got ".freeze; print(( obj ).to_s); print "!\n".freeze
#
# == Evaluation
#
# The compiled code can be used in any context where the names in the code
# correctly resolve. Using the last example, each of these print 'Got It!'
#
# Evaluate using a variable:
#
#   obj = 'It'
#   eval code
#
# Evaluate using an input:
#
#   mod = Module.new
#   mod.module_eval %{
#     def get(obj)
#       #{code}
#     end
#   }
#   extend mod
#   get('It')
#
# Evaluate using an accessor:
#
#   klass = Class.new Object
#   klass.class_eval %{
#     attr_accessor :obj
#     def initialize(obj)
#       @obj = obj
#     end
#     def get_it
#       #{code}
#     end
#   }
#   klass.new('It').get_it
#
# Good! See also ERB#def_method, ERB#def_module, and ERB#def_class.
class ERB::Compiler # :nodoc:
  class PercentLine # :nodoc:
    def initialize(str)
      @value = str
    end
    attr_reader :value
    alias :to_s :value
  end

  class Scanner # :nodoc:
    @scanner_map = {}
    class << self
      def register_scanner(klass, trim_mode, percent)
        @scanner_map[[trim_mode, percent]] = klass
      end
      alias :regist_scanner :register_scanner
    end

    def self.default_scanner=(klass)
      @default_scanner = klass
    end

    def self.make_scanner(src, trim_mode, percent)
      klass = @scanner_map.fetch([trim_mode, percent], @default_scanner)
      klass.new(src, trim_mode, percent)
    end

    DEFAULT_STAGS = %w(<%% <%= <%# <%).freeze
    DEFAULT_ETAGS = %w(%%> %>).freeze
    def initialize(src, trim_mode, percent)
      @src = src
      @stag = nil
      @stags = DEFAULT_STAGS
      @etags = DEFAULT_ETAGS
    end
    attr_accessor :stag
    attr_reader :stags, :etags

    def scan; end
  end

  class TrimScanner < Scanner # :nodoc:
    def initialize(src, trim_mode, percent)
      super
      @trim_mode = trim_mode
      @percent = percent
      if @trim_mode == '>'
        @scan_reg  = /(.*?)(%>\r?\n|#{(stags + etags).join('|')}|\n|\z)/m
        @scan_line = self.method(:trim_line1)
      elsif @trim_mode == '<>'
        @scan_reg  = /(.*?)(%>\r?\n|#{(stags + etags).join('|')}|\n|\z)/m
        @scan_line = self.method(:trim_line2)
      elsif @trim_mode == '-'
        @scan_reg  = /(.*?)(^[ \t]*<%\-|<%\-|-%>\r?\n|-%>|#{(stags + etags).join('|')}|\z)/m
        @scan_line = self.method(:explicit_trim_line)
      else
        @scan_reg  = /(.*?)(#{(stags + etags).join('|')}|\n|\z)/m
        @scan_line = self.method(:scan_line)
      end
    end

    def scan(&block)
      @stag = nil
      if @percent
        @src.each_line do |line|
          percent_line(line, &block)
        end
      else
        @scan_line.call(@src, &block)
      end
      nil
    end

    def percent_line(line, &block)
      if @stag || line[0] != ?%
        return @scan_line.call(line, &block)
      end

      line[0] = ''
      if line[0] == ?%
        @scan_line.call(line, &block)
      else
        yield(PercentLine.new(line.chomp))
      end
    end

    def scan_line(line)
      line.scan(@scan_reg) do |tokens|
        tokens.each do |token|
          next if token.empty?
          yield(token)
        end
      end
    end

    def trim_line1(line)
      line.scan(@scan_reg) do |tokens|
        tokens.each do |token|
          next if token.empty?
          if token == "%>\n" || token == "%>\r\n"
            yield('%>')
            yield(:cr)
          else
            yield(token)
          end
        end
      end
    end

    def trim_line2(line)
      head = nil
      line.scan(@scan_reg) do |tokens|
        tokens.each do |token|
          next if token.empty?
          head = token unless head
          if token == "%>\n" || token == "%>\r\n"
            yield('%>')
            if is_erb_stag?(head)
              yield(:cr)
            else
              yield("\n")
            end
            head = nil
          else
            yield(token)
            head = nil if token == "\n"
          end
        end
      end
    end

    def explicit_trim_line(line)
      line.scan(@scan_reg) do |tokens|
        tokens.each do |token|
          next if token.empty?
          if @stag.nil? && /[ \t]*<%-/ =~ token
            yield('<%')
          elsif @stag && (token == "-%>\n" || token == "-%>\r\n")
            yield('%>')
            yield(:cr)
          elsif @stag && token == '-%>'
            yield('%>')
          else
            yield(token)
          end
        end
      end
    end

    ERB_STAG = %w(<%= <%# <%)
    def is_erb_stag?(s)
      ERB_STAG.member?(s)
    end
  end

  Scanner.default_scanner = TrimScanner

  begin
    require 'strscan'
  rescue LoadError
  else
    class SimpleScanner < Scanner # :nodoc:
      def scan
        stag_reg = (stags == DEFAULT_STAGS) ? /(.*?)(<%[%=#]?|\z)/m : /(.*?)(#{stags.join('|')}|\z)/m
        etag_reg = (etags == DEFAULT_ETAGS) ? /(.*?)(%%?>|\z)/m : /(.*?)(#{etags.join('|')}|\z)/m
        scanner = StringScanner.new(@src)
        while ! scanner.eos?
          scanner.scan(@stag ? etag_reg : stag_reg)
          yield(scanner[1])
          yield(scanner[2])
        end
      end
    end
    Scanner.register_scanner(SimpleScanner, nil, false)

    class ExplicitScanner < Scanner # :nodoc:
      def scan
        stag_reg = /(.*?)(^[ \t]*<%-|<%-|#{stags.join('|')}|\z)/m
        etag_reg = /(.*?)(-%>|#{etags.join('|')}|\z)/m
        scanner = StringScanner.new(@src)
        while ! scanner.eos?
          scanner.scan(@stag ? etag_reg : stag_reg)
          yield(scanner[1])

          elem = scanner[2]
          if /[ \t]*<%-/ =~ elem
            yield('<%')
          elsif elem == '-%>'
            yield('%>')
            yield(:cr) if scanner.scan(/(\r?\n|\z)/)
          else
            yield(elem)
          end
        end
      end
    end
    Scanner.register_scanner(ExplicitScanner, '-', false)
  end

  class Buffer # :nodoc:
    def initialize(compiler, enc=nil, frozen=nil)
      @compiler = compiler
      @line = []
      @script = +''
      @script << "#coding:#{enc}\n" if enc
      @script << "#frozen-string-literal:#{frozen}\n" unless frozen.nil?
      @compiler.pre_cmd.each do |x|
        push(x)
      end
    end
    attr_reader :script

    def push(cmd)
      @line << cmd
    end

    def cr
      @script << (@line.join('; '))
      @line = []
      @script << "\n"
    end

    def close
      return unless @line
      @compiler.post_cmd.each do |x|
        push(x)
      end
      @script << (@line.join('; '))
      @line = nil
    end
  end

  def add_put_cmd(out, content)
    out.push("#{@put_cmd} #{content.dump}.freeze#{"\n" * content.count("\n")}")
  end

  def add_insert_cmd(out, content)
    out.push("#{@insert_cmd}((#{content}).to_s)")
  end

  # Compiles an ERB template into Ruby code.  Returns an array of the code
  # and encoding like ["code", Encoding].
  def compile(s)
    enc = s.encoding
    raise ArgumentError, "#{enc} is not ASCII compatible" if enc.dummy?
    s = s.b # see String#b
    magic_comment = detect_magic_comment(s, enc)
    out = Buffer.new(self, *magic_comment)

    self.content = +''
    scanner = make_scanner(s)
    scanner.scan do |token|
      next if token.nil?
      next if token == ''
      if scanner.stag.nil?
        compile_stag(token, out, scanner)
      else
        compile_etag(token, out, scanner)
      end
    end
    add_put_cmd(out, content) if content.size > 0
    out.close
    return out.script, *magic_comment
  end

  def compile_stag(stag, out, scanner)
    case stag
    when PercentLine
      add_put_cmd(out, content) if content.size > 0
      self.content = +''
      out.push(stag.to_s)
      out.cr
    when :cr
      out.cr
    when '<%', '<%=', '<%#'
      scanner.stag = stag
      add_put_cmd(out, content) if content.size > 0
      self.content = +''
    when "\n"
      content << "\n"
      add_put_cmd(out, content)
      self.content = +''
    when '<%%'
      content << '<%'
    else
      content << stag
    end
  end

  def compile_etag(etag, out, scanner)
    case etag
    when '%>'
      compile_content(scanner.stag, out)
      scanner.stag = nil
      self.content = +''
    when '%%>'
      content << '%>'
    else
      content << etag
    end
  end

  def compile_content(stag, out)
    case stag
    when '<%'
      if content[-1] == ?\n
        content.chop!
        out.push(content)
        out.cr
      else
        out.push(content)
      end
    when '<%='
      add_insert_cmd(out, content)
    when '<%#'
      out.push("\n" * content.count("\n")) # only adjust lineno
    end
  end

  def prepare_trim_mode(mode) # :nodoc:
    case mode
    when 1
      return [false, '>']
    when 2
      return [false, '<>']
    when 0, nil
      return [false, nil]
    when String
      unless mode.match?(/\A(%|-|>|<>){1,2}\z/)
        warn_invalid_trim_mode(mode, uplevel: 5)
      end

      perc = mode.include?('%')
      if mode.include?('-')
        return [perc, '-']
      elsif mode.include?('<>')
        return [perc, '<>']
      elsif mode.include?('>')
        return [perc, '>']
      else
        [perc, nil]
      end
    else
      warn_invalid_trim_mode(mode, uplevel: 5)
      return [false, nil]
    end
  end

  def make_scanner(src) # :nodoc:
    Scanner.make_scanner(src, @trim_mode, @percent)
  end

  # Construct a new compiler using the trim_mode. See ERB::new for available
  # trim modes.
  def initialize(trim_mode)
    @percent, @trim_mode = prepare_trim_mode(trim_mode)
    @put_cmd = 'print'
    @insert_cmd = @put_cmd
    @pre_cmd = []
    @post_cmd = []
  end
  attr_reader :percent, :trim_mode

  # The command to handle text that ends with a newline
  attr_accessor :put_cmd

  # The command to handle text that is inserted prior to a newline
  attr_accessor :insert_cmd

  # An array of commands prepended to compiled code
  attr_accessor :pre_cmd

  # An array of commands appended to compiled code
  attr_accessor :post_cmd

  private

  # A buffered text in #compile
  attr_accessor :content

  def detect_magic_comment(s, enc = nil)
    re = @percent ? /\G(?:<%#(.*)%>|%#(.*)\n)/ : /\G<%#(.*)%>/
    frozen = nil
    s.scan(re) do
      comment = $+
      comment = $1 if comment[/-\*-\s*([^\s].*?)\s*-\*-$/]
      case comment
      when %r"coding\s*[=:]\s*([[:alnum:]\-_]+)"
        enc = Encoding.find($1.sub(/-(?:mac|dos|unix)/i, ''))
      when %r"frozen[-_]string[-_]literal\s*:\s*([[:alnum:]]+)"
        frozen = $1
      end
    end
    return enc, frozen
  end

  def warn_invalid_trim_mode(mode, uplevel:)
    warn "Invalid ERB trim mode: #{mode.inspect} (trim_mode: nil, 0, 1, 2, or String composed of '%' and/or '-', '>', '<>')", uplevel: uplevel + 1
  end
end
