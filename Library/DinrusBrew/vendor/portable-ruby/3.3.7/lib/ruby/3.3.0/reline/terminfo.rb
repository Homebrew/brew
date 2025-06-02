begin
  # Ignore warning `Add fiddle to your Gemfile or gemspec` in Ruby 3.4.
  # terminfo.rb and ansi.rb supports fiddle unavailable environment.
  verbose, $VERBOSE = $VERBOSE, nil
  require 'fiddle'
  require 'fiddle/import'
rescue LoadError
  module Reline::Terminfo
    def self.curses_dl
      false
    end
  end
ensure
  $VERBOSE = verbose
end

module Reline::Terminfo
  extend Fiddle::Importer

  class TerminfoError < StandardError; end

  def self.curses_dl_files
    case RUBY_PLATFORM
    when /mingw/, /mswin/
      # aren't supported
      []
    when /cygwin/
      %w[cygncursesw-10.dll cygncurses-10.dll]
    when /darwin/
      %w[libncursesw.dylib libcursesw.dylib libncurses.dylib libcurses.dylib]
    else
      %w[libncursesw.so libcursesw.so libncurses.so libcurses.so]
    end
  end

  @curses_dl = false
  def self.curses_dl
    return @curses_dl unless @curses_dl == false
    if Fiddle.const_defined?(:TYPE_VARIADIC)
      curses_dl_files.each do |curses_name|
        result = Fiddle::Handle.new(curses_name)
      rescue Fiddle::DLError
        next
      else
        @curses_dl = result
        break
      end
    end
    @curses_dl = nil if @curses_dl == false
    @curses_dl
  end
end if not Reline.const_defined?(:Terminfo) or not Reline::Terminfo.respond_to?(:curses_dl)

module Reline::Terminfo
  dlload curses_dl
  #extern 'int setupterm(char *term, int fildes, int *errret)'
  @setupterm = Fiddle::Function.new(curses_dl['setupterm'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
  #extern 'char *tigetstr(char *capname)'
  @tigetstr = Fiddle::Function.new(curses_dl['tigetstr'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
  begin
    #extern 'char *tiparm(const char *str, ...)'
    @tiparm = Fiddle::Function.new(curses_dl['tiparm'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VARIADIC], Fiddle::TYPE_VOIDP)
  rescue Fiddle::DLError
    # OpenBSD lacks tiparm
    #extern 'char *tparm(const char *str, ...)'
    @tiparm = Fiddle::Function.new(curses_dl['tparm'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VARIADIC], Fiddle::TYPE_VOIDP)
  end
  begin
    #extern 'int tigetflag(char *str)'
    @tigetflag = Fiddle::Function.new(curses_dl['tigetflag'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
  rescue Fiddle::DLError
    # OpenBSD lacks tigetflag
    #extern 'int tgetflag(char *str)'
    @tigetflag = Fiddle::Function.new(curses_dl['tgetflag'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
  end
  begin
    #extern 'int tigetnum(char *str)'
    @tigetnum = Fiddle::Function.new(curses_dl['tigetnum'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
  rescue Fiddle::DLError
    # OpenBSD lacks tigetnum
    #extern 'int tgetnum(char *str)'
    @tigetnum = Fiddle::Function.new(curses_dl['tgetnum'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
  end

  def self.setupterm(term, fildes)
    errret_int = Fiddle::Pointer.malloc(Fiddle::SIZEOF_INT, Fiddle::RUBY_FREE)
    ret = @setupterm.(term, fildes, errret_int)
    case ret
    when 0 # OK
      @term_supported = true
    when -1 # ERR
      @term_supported = false
    end
  end

  class StringWithTiparm < String
    def tiparm(*args) # for method chain
      Reline::Terminfo.tiparm(self, *args)
    end
  end

  def self.tigetstr(capname)
    raise TerminfoError, "capname is not String: #{capname.inspect}" unless capname.is_a?(String)
    capability = @tigetstr.(capname)
    case capability.to_i
    when 0, -1
      raise TerminfoError, "can't find capability: #{capname}"
    end
    StringWithTiparm.new(capability.to_s)
  end

  def self.tiparm(str, *args)
    new_args = []
    args.each do |a|
      new_args << Fiddle::TYPE_INT << a
    end
    @tiparm.(str, *new_args).to_s
  end

  def self.tigetflag(capname)
    raise TerminfoError, "capname is not String: #{capname.inspect}" unless capname.is_a?(String)
    flag = @tigetflag.(capname).to_i
    case flag
    when -1
      raise TerminfoError, "not boolean capability: #{capname}"
    when 0
      raise TerminfoError, "can't find capability: #{capname}"
    end
    flag
  end

  def self.tigetnum(capname)
    raise TerminfoError, "capname is not String: #{capname.inspect}" unless capname.is_a?(String)
    num = @tigetnum.(capname).to_i
    case num
    when -2
      raise TerminfoError, "not numeric capability: #{capname}"
    when -1
      raise TerminfoError, "can't find capability: #{capname}"
    end
    num
  end

  # NOTE: This means Fiddle and curses are enabled.
  def self.enabled?
    true
  end

  def self.term_supported?
    @term_supported
  end
end if Reline::Terminfo.curses_dl

module Reline::Terminfo
  def self.enabled?
    false
  end
end unless Reline::Terminfo.curses_dl
