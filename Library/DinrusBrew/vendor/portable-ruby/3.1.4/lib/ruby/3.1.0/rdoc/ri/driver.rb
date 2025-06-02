# frozen_string_literal: true
require 'abbrev'
require 'optparse'

begin
  require 'readline'
rescue LoadError
end

begin
  require 'win32console'
rescue LoadError
end

require 'rdoc'

##
# For RubyGems backwards compatibility

require_relative 'formatter'

##
# The RI driver implements the command-line ri tool.
#
# The driver supports:
# * loading RI data from:
#   * Ruby's standard library
#   * RubyGems
#   * ~/.rdoc
#   * A user-supplied directory
# * Paging output (uses RI_PAGER environment variable, PAGER environment
#   variable or the less, more and pager programs)
# * Interactive mode with tab-completion
# * Abbreviated names (ri Zl shows Zlib documentation)
# * Colorized output
# * Merging output from multiple RI data sources

class RDoc::RI::Driver

  ##
  # Base Driver error class

  class Error < RDoc::RI::Error; end

  ##
  # Raised when a name isn't found in the ri data stores

  class NotFoundError < Error

    def initialize(klass, suggestions = nil) # :nodoc:
      @klass = klass
      @suggestions = suggestions
    end

    ##
    # Name that wasn't found

    def name
      @klass
    end

    def message # :nodoc:
      str = "Nothing known about #{@klass}"
      if @suggestions and !@suggestions.empty?
        str += "\nDid you mean?  #{@suggestions.join("\n               ")}"
      end
      str
    end
  end

  ##
  # Show all method documentation following a class or module

  attr_accessor :show_all

  ##
  # An RDoc::RI::Store for each entry in the RI path

  attr_accessor :stores

  ##
  # Controls the user of the pager vs $stdout

  attr_accessor :use_stdout

  ##
  # Default options for ri

  def self.default_options
    options = {}
    options[:interactive] = false
    options[:profile]     = false
    options[:show_all]    = false
    options[:use_stdout]  = !$stdout.tty?
    options[:width]       = 72

    # By default all standard paths are used.
    options[:use_system]     = true
    options[:use_site]       = true
    options[:use_home]       = true
    options[:use_gems]       = true
    options[:extra_doc_dirs] = []

    return options
  end

  ##
  # Dump +data_path+ using pp

  def self.dump data_path
    require 'pp'

    File.open data_path, 'rb' do |io|
      pp Marshal.load(io.read)
    end
  end

  ##
  # Parses +argv+ and returns a Hash of options

  def self.process_args argv
    options = default_options

    opts = OptionParser.new do |opt|
      opt.accept File do |file,|
        File.readable?(file) and not File.directory?(file) and file
      end

      opt.program_name = File.basename $0
      opt.version = RDoc::VERSION
      opt.release = nil
      opt.summary_indent = ' ' * 4

      opt.banner = <<-EOT
Usage: #{opt.program_name} [options] [name ...]

Where name can be:

  Class | Module | Module::Class

  Class::method | Class#method | Class.method | method

  gem_name: | gem_name:README | gem_name:History

  ruby: | ruby:NEWS | ruby:globals

All class names may be abbreviated to their minimum unambiguous form.
If a name is ambiguous, all valid options will be listed.

A '.' matches either class or instance methods, while #method
matches only instance and ::method matches only class methods.

README and other files may be displayed by prefixing them with the gem name
they're contained in.  If the gem name is followed by a ':' all files in the
gem will be shown.  The file name extension may be omitted where it is
unambiguous.

'ruby' can be used as a pseudo gem name to display files from the Ruby
core documentation. Use 'ruby:' by itself to get a list of all available
core documentation files.

For example:

    #{opt.program_name} Fil
    #{opt.program_name} File
    #{opt.program_name} File.new
    #{opt.program_name} zip
    #{opt.program_name} rdoc:README
    #{opt.program_name} ruby:comments

Note that shell quoting or escaping may be required for method names
containing punctuation:

    #{opt.program_name} 'Array.[]'
    #{opt.program_name} compact\\!

To see the default directories #{opt.program_name} will search, run:

    #{opt.program_name} --list-doc-dirs

Specifying the --system, --site, --home, --gems, or --doc-dir options
will limit ri to searching only the specified directories.

ri options may be set in the RI environment variable.

The ri pager can be set with the RI_PAGER environment variable
or the PAGER environment variable.
      EOT

      opt.separator nil
      opt.separator "Options:"

      opt.separator nil

      opt.on("--[no-]interactive", "-i",
             "In interactive mode you can repeatedly",
             "look up methods with autocomplete.") do |interactive|
        options[:interactive] = interactive
      end

      opt.separator nil

      opt.on("--[no-]all", "-a",
             "Show all documentation for a class or",
             "module.") do |show_all|
        options[:show_all] = show_all
      end

      opt.separator nil

      opt.on("--[no-]list", "-l",
             "List classes ri knows about.") do |list|
        options[:list] = list
      end

      opt.separator nil

      opt.on("--[no-]pager",
             "Send output to a pager,",
             "rather than directly to stdout.") do |use_pager|
        options[:use_stdout] = !use_pager
      end

      opt.separator nil

      opt.on("-T",
             "Synonym for --no-pager.") do
        options[:use_stdout] = true
      end

      opt.separator nil

      opt.on("--width=WIDTH", "-w", OptionParser::DecimalInteger,
             "Set the width of the output.") do |width|
        options[:width] = width
      end

      opt.separator nil

      opt.on("--server[=PORT]", Integer,
             "Run RDoc server on the given port.",
             "The default port is 8214.") do |port|
        options[:server] = port || 8214
      end

      opt.separator nil

      formatters = RDoc::Markup.constants.grep(/^To[A-Z][a-z]+$/).sort
      formatters = formatters.sort.map do |formatter|
        formatter.to_s.sub('To', '').downcase
      end
      formatters -= %w[html label test] # remove useless output formats

      opt.on("--format=NAME", "-f",
             "Use the selected formatter.  The default",
             "formatter is bs for paged output and ansi",
             "otherwise.  Valid formatters are:",
             "#{formatters.join(', ')}.", formatters) do |value|
        options[:formatter] = RDoc::Markup.const_get "To#{value.capitalize}"
      end

      opt.separator nil

      opt.on("--help", "-h",
             "Show help and exit.") do
        puts opts
        exit
      end

      opt.separator nil

      opt.on("--version", "-v",
             "Output version information and exit.") do
        puts "#{opts.program_name} #{opts.version}"
        exit
      end

      opt.separator nil
      opt.separator "Data source options:"
      opt.separator nil

      opt.on("--[no-]list-doc-dirs",
             "List the directories from which ri will",
             "source documentation on stdout and exit.") do |list_doc_dirs|
        options[:list_doc_dirs] = list_doc_dirs
      end

      opt.separator nil

      opt.on("--doc-dir=DIRNAME", "-d", Array,
             "List of directories from which to source",
             "documentation in addition to the standard",
             "directories.  May be repeated.") do |value|
        value.each do |dir|
          unless File.directory? dir then
            raise OptionParser::InvalidArgument, "#{dir} is not a directory"
          end

          options[:extra_doc_dirs] << File.expand_path(dir)
        end
      end

      opt.separator nil

      opt.on("--no-standard-docs",
             "Do not include documentation from",
             "the Ruby standard library, site_lib,",
             "installed gems, or ~/.rdoc.",
             "Use with --doc-dir.") do
        options[:use_system] = false
        options[:use_site] = false
        options[:use_gems] = false
        options[:use_home] = false
      end

      opt.separator nil

      opt.on("--[no-]system",
             "Include documentation from Ruby's",
             "standard library.  Defaults to true.") do |value|
        options[:use_system] = value
      end

      opt.separator nil

      opt.on("--[no-]site",
             "Include documentation from libraries",
             "installed in site_lib.",
             "Defaults to true.") do |value|
        options[:use_site] = value
      end

      opt.separator nil

      opt.on("--[no-]gems",
             "Include documentation from RubyGems.",
             "Defaults to true.") do |value|
        options[:use_gems] = value
      end

      opt.separator nil

      opt.on("--[no-]home",
             "Include documentation stored in ~/.rdoc.",
             "Defaults to true.") do |value|
        options[:use_home] = value
      end

      opt.separator nil
      opt.separator "Debug options:"
      opt.separator nil

      opt.on("--[no-]profile",
             "Run with the ruby profiler.") do |value|
        options[:profile] = value
      end

      opt.separator nil

      opt.on("--dump=CACHE", File,
             "Dump data from an ri cache or data file.") do |value|
        options[:dump_path] = value
      end
    end

    argv = ENV['RI'].to_s.split(' ').concat argv

    opts.parse! argv

    options[:names] = argv

    options[:use_stdout] ||= !$stdout.tty?
    options[:use_stdout] ||= options[:interactive]
    options[:width] ||= 72

    options

  rescue OptionParser::InvalidArgument, OptionParser::InvalidOption => e
    puts opts
    puts
    puts e
    exit 1
  end

  ##
  # Runs the ri command line executable using +argv+

  def self.run argv = ARGV
    options = process_args argv

    if options[:dump_path] then
      dump options[:dump_path]
      return
    end

    ri = new options
    ri.run
  end

  ##
  # Creates a new driver using +initial_options+ from ::process_args

  def initialize initial_options = {}
    @paging = false
    @classes = nil

    options = self.class.default_options.update(initial_options)

    @formatter_klass = options[:formatter]

    require 'profile' if options[:profile]

    @names = options[:names]
    @list = options[:list]

    @doc_dirs = []
    @stores   = []

    RDoc::RI::Paths.each(options[:use_system], options[:use_site],
                         options[:use_home], options[:use_gems],
                         *options[:extra_doc_dirs]) do |path, type|
      @doc_dirs << path

      store = RDoc::RI::Store.new path, type
      store.load_cache
      @stores << store
    end

    @list_doc_dirs = options[:list_doc_dirs]

    @interactive = options[:interactive]
    @server      = options[:server]
    @use_stdout  = options[:use_stdout]
    @show_all    = options[:show_all]
    @width       = options[:width]

    # pager process for jruby
    @jruby_pager_process = nil
  end

  ##
  # Adds paths for undocumented classes +also_in+ to +out+

  def add_also_in out, also_in
    return if also_in.empty?

    out << RDoc::Markup::Rule.new(1)
    out << RDoc::Markup::Paragraph.new("Also found in:")

    paths = RDoc::Markup::Verbatim.new
    also_in.each do |store|
      paths.parts.push store.friendly_path, "\n"
    end
    out << paths
  end

  ##
  # Adds a class header to +out+ for class +name+ which is described in
  # +classes+.

  def add_class out, name, classes
    heading = if classes.all? { |klass| klass.module? } then
                name
              else
                superclass = classes.map do |klass|
                  klass.superclass unless klass.module?
                end.compact.shift || 'Object'

                superclass = superclass.full_name unless String === superclass

                "#{name} < #{superclass}"
              end

    out << RDoc::Markup::Heading.new(1, heading)
    out << RDoc::Markup::BlankLine.new
  end

  ##
  # Adds "(from ...)" to +out+ for +store+

  def add_from out, store
    out << RDoc::Markup::Paragraph.new("(from #{store.friendly_path})")
  end

  ##
  # Adds +extends+ to +out+

  def add_extends out, extends
    add_extension_modules out, 'Extended by', extends
  end

  ##
  # Adds a list of +extensions+ to this module of the given +type+ to +out+.
  # add_includes and add_extends call this, so you should use those directly.

  def add_extension_modules out, type, extensions
    return if extensions.empty?

    out << RDoc::Markup::Rule.new(1)
    out << RDoc::Markup::Heading.new(1, "#{type}:")

    extensions.each do |modules, store|
      if modules.length == 1 then
        add_extension_modules_single out, store, modules.first
      else
        add_extension_modules_multiple out, store, modules
      end
    end
  end

  ##
  # Renders multiple included +modules+ from +store+ to +out+.

  def add_extension_modules_multiple out, store, modules # :nodoc:
    out << RDoc::Markup::Paragraph.new("(from #{store.friendly_path})")

    wout, with = modules.partition { |incl| incl.comment.empty? }

    out << RDoc::Markup::BlankLine.new unless with.empty?

    with.each do |incl|
      out << RDoc::Markup::Paragraph.new(incl.name)
      out << RDoc::Markup::BlankLine.new
      out << incl.comment
    end

    unless wout.empty? then
      verb = RDoc::Markup::Verbatim.new

      wout.each do |incl|
        verb.push incl.name, "\n"
      end

      out << verb
    end
  end

  ##
  # Adds a single extension module +include+ from +store+ to +out+

  def add_extension_modules_single out, store, include # :nodoc:
    name = include.name
    path = store.friendly_path
    out << RDoc::Markup::Paragraph.new("#{name} (from #{path})")

    if include.comment then
      out << RDoc::Markup::BlankLine.new
      out << include.comment
    end
  end

  ##
  # Adds +includes+ to +out+

  def add_includes out, includes
    add_extension_modules out, 'Includes', includes
  end

  ##
  # Looks up the method +name+ and adds it to +out+

  def add_method out, name
    filtered   = lookup_method name

    method_out = method_document name, filtered

    out.concat method_out.parts
  end

  ##
  # Adds documentation for all methods in +klass+ to +out+

  def add_method_documentation out, klass
    klass.method_list.each do |method|
      begin
        add_method out, method.full_name
      rescue NotFoundError
        next
      end
    end
  end

  ##
  # Adds a list of +methods+ to +out+ with a heading of +name+

  def add_method_list out, methods, name
    return if methods.empty?

    out << RDoc::Markup::Heading.new(1, "#{name}:")
    out << RDoc::Markup::BlankLine.new

    if @use_stdout and !@interactive then
      out.concat methods.map { |method|
        RDoc::Markup::Verbatim.new method
      }
    else
      out << RDoc::Markup::IndentedParagraph.new(2, methods.join(', '))
    end

    out << RDoc::Markup::BlankLine.new
  end

  ##
  # Returns ancestor classes of +klass+

  def ancestors_of klass
    ancestors = []

    unexamined = [klass]
    seen = []

    loop do
      break if unexamined.empty?
      current = unexamined.shift
      seen << current

      stores = classes[current]

      next unless stores and not stores.empty?

      klasses = stores.flat_map do |store|
        store.ancestors[current] || []
      end.uniq

      klasses = klasses - seen

      ancestors.concat klasses
      unexamined.concat klasses
    end

    ancestors.reverse
  end

  ##
  # For RubyGems backwards compatibility

  def class_cache # :nodoc:
  end

  ##
  # Builds a RDoc::Markup::Document from +found+, +klasess+ and +includes+

  def class_document name, found, klasses, includes, extends
    also_in = []

    out = RDoc::Markup::Document.new

    add_class out, name, klasses

    add_includes out, includes
    add_extends  out, extends

    found.each do |store, klass|
      render_class out, store, klass, also_in
    end

    add_also_in out, also_in

    out
  end

  ##
  # Adds the class +comment+ to +out+.

  def class_document_comment out, comment # :nodoc:
    unless comment.empty? then
      out << RDoc::Markup::Rule.new(1)

      if comment.merged? then
        parts = comment.parts
        parts = parts.zip [RDoc::Markup::BlankLine.new] * parts.length
        parts.flatten!
        parts.pop

        out.concat parts
      else
        out << comment
      end
    end
  end

  ##
  # Adds the constants from +klass+ to the Document +out+.

  def class_document_constants out, klass # :nodoc:
    return if klass.constants.empty?

    out << RDoc::Markup::Heading.new(1, "Constants:")
    out << RDoc::Markup::BlankLine.new
    list = RDoc::Markup::List.new :NOTE

    constants = klass.constants.sort_by { |constant| constant.name }

    list.items.concat constants.map { |constant|
      parts = constant.comment.parts if constant.comment
      parts << RDoc::Markup::Paragraph.new('[not documented]') if
        parts.empty?

      RDoc::Markup::ListItem.new(constant.name, *parts)
    }

    out << list
    out << RDoc::Markup::BlankLine.new
  end

  ##
  # Hash mapping a known class or module to the stores it can be loaded from

  def classes
    return @classes if @classes

    @classes = {}

    @stores.each do |store|
      store.cache[:modules].each do |mod|
        # using default block causes searched-for modules to be added
        @classes[mod] ||= []
        @classes[mod] << store
      end
    end

    @classes
  end

  ##
  # Returns the stores wherein +name+ is found along with the classes,
  # extends and includes that match it

  def classes_and_includes_and_extends_for name
    klasses = []
    extends = []
    includes = []

    found = @stores.map do |store|
      begin
        klass = store.load_class name
        klasses  << klass
        extends  << [klass.extends,  store] if klass.extends
        includes << [klass.includes, store] if klass.includes
        [store, klass]
      rescue RDoc::Store::MissingFileError
      end
    end.compact

    extends.reject!  do |modules,| modules.empty? end
    includes.reject! do |modules,| modules.empty? end

    [found, klasses, includes, extends]
  end

  ##
  # Completes +name+ based on the caches.  For Readline

  def complete name
    completions = []

    klass, selector, method = parse_name name

    complete_klass  name, klass, selector, method, completions
    complete_method name, klass, selector,         completions

    completions.sort.uniq
  end

  def complete_klass name, klass, selector, method, completions # :nodoc:
    klasses = classes.keys

    # may need to include Foo when given Foo::
    klass_name = method ? name : klass

    if name !~ /#|\./ then
      completions.replace klasses.grep(/^#{Regexp.escape klass_name}[^:]*$/)
      completions.concat klasses.grep(/^#{Regexp.escape name}[^:]*$/) if
        name =~ /::$/

      completions << klass if classes.key? klass # to complete a method name
    elsif selector then
      completions << klass if classes.key? klass
    elsif classes.key? klass_name then
      completions << klass_name
    end
  end

  def complete_method name, klass, selector, completions # :nodoc:
    if completions.include? klass and name =~ /#|\.|::/ then
      methods = list_methods_matching name

      if not methods.empty? then
        # remove Foo if given Foo:: and a method was found
        completions.delete klass
      elsif selector then
        # replace Foo with Foo:: as given
        completions.delete klass
        completions << "#{klass}#{selector}"
      end

      completions.concat methods
    end
  end

  ##
  # Converts +document+ to text and writes it to the pager

  def display document
    page do |io|
      f = formatter(io)
      f.width = @width if @width and f.respond_to?(:width)
      text = document.accept f

      io.write text
    end
  end

  ##
  # Outputs formatted RI data for class +name+.  Groups undocumented classes

  def display_class name
    return if name =~ /#|\./

    found, klasses, includes, extends =
      classes_and_includes_and_extends_for name

    return if found.empty?

    out = class_document name, found, klasses, includes, extends

    display out
  end

  ##
  # Outputs formatted RI data for method +name+

  def display_method name
    out = RDoc::Markup::Document.new

    add_method out, name

    display out
  end

  ##
  # Outputs formatted RI data for the class or method +name+.
  #
  # Returns true if +name+ was found, false if it was not an alternative could
  # be guessed, raises an error if +name+ couldn't be guessed.

  def display_name name
    if name =~ /\w:(\w|$)/ then
      display_page name
      return true
    end

    return true if display_class name

    display_method name if name =~ /::|#|\./

    true
  rescue NotFoundError
    matches = list_methods_matching name if name =~ /::|#|\./
    matches = classes.keys.grep(/^#{Regexp.escape name}/) if matches.empty?

    raise if matches.empty?

    page do |io|
      io.puts "#{name} not found, maybe you meant:"
      io.puts
      io.puts matches.sort.join("\n")
    end

    false
  end

  ##
  # Displays each name in +name+

  def display_names names
    names.each do |name|
      name = expand_name name

      display_name name
    end
  end

  ##
  # Outputs formatted RI data for page +name+.

  def display_page name
    store_name, page_name = name.split ':', 2

    store = @stores.find { |s| s.source == store_name }

    return display_page_list store if page_name.empty?

    pages = store.cache[:pages]

    unless pages.include? page_name then
      found_names = pages.select do |n|
        n =~ /#{Regexp.escape page_name}\.[^.]+$/
      end

      if found_names.length.zero? then
        return display_page_list store, pages
      elsif found_names.length > 1 then
        return display_page_list store, found_names, page_name
      end

      page_name = found_names.first
    end

    page = store.load_page page_name

    display page.comment
  end

  ##
  # Outputs a formatted RI page list for the pages in +store+.

  def display_page_list store, pages = store.cache[:pages], search = nil
    out = RDoc::Markup::Document.new

    title = if search then
              "#{search} pages"
            else
              'Pages'
            end

    out << RDoc::Markup::Heading.new(1, "#{title} in #{store.friendly_path}")
    out << RDoc::Markup::BlankLine.new

    list = RDoc::Markup::List.new(:BULLET)

    pages.each do |page|
      list << RDoc::Markup::Paragraph.new(page)
    end

    out << list

    display out
  end

  def check_did_you_mean # :nodoc:
    if defined? DidYouMean::SpellChecker
      true
    else
      begin
        require 'did_you_mean'
        if defined? DidYouMean::SpellChecker
          true
        else
          false
        end
      rescue LoadError
        false
      end
    end
  end

  ##
  # Expands abbreviated klass +klass+ into a fully-qualified class.  "Zl::Da"
  # will be expanded to Zlib::DataError.

  def expand_class klass
    class_names = classes.keys
    ary = class_names.grep(Regexp.new("\\A#{klass.gsub(/(?=::|\z)/, '[^:]*')}\\z"))
    if ary.length != 1 && ary.first != klass
      if check_did_you_mean
        suggestions = DidYouMean::SpellChecker.new(dictionary: class_names).correct(klass)
        raise NotFoundError.new(klass, suggestions)
      else
        raise NotFoundError, klass
      end
    end
    ary.first
  end

  ##
  # Expands the class portion of +name+ into a fully-qualified class.  See
  # #expand_class.

  def expand_name name
    klass, selector, method = parse_name name

    return [selector, method].join if klass.empty?

    case selector
    when ':' then
      [find_store(klass),   selector, method]
    else
      [expand_class(klass), selector, method]
    end.join
  end

  ##
  # Filters the methods in +found+ trying to find a match for +name+.

  def filter_methods found, name
    regexp = name_regexp name

    filtered = found.find_all do |store, methods|
      methods.any? { |method| method.full_name =~ regexp }
    end

    return filtered unless filtered.empty?

    found
  end

  ##
  # Yields items matching +name+ including the store they were found in, the
  # class being searched for, the class they were found in (an ancestor) the
  # types of methods to look up (from #method_type), and the method name being
  # searched for

  def find_methods name
    klass, selector, method = parse_name name

    types = method_type selector

    klasses = nil
    ambiguous = klass.empty?

    if ambiguous then
      klasses = classes.keys
    else
      klasses = ancestors_of klass
      klasses.unshift klass
    end

    methods = []

    klasses.each do |ancestor|
      ancestors = classes[ancestor]

      next unless ancestors

      klass = ancestor if ambiguous

      ancestors.each do |store|
        methods << [store, klass, ancestor, types, method]
      end
    end

    methods = methods.sort_by do |_, k, a, _, m|
      [k, a, m].compact
    end

    methods.each do |item|
      yield(*item) # :yields: store, klass, ancestor, types, method
    end

    self
  end

  ##
  # Finds the given +pager+ for jruby.  Returns an IO if +pager+ was found.
  #
  # Returns false if +pager+ does not exist.
  #
  # Returns nil if the jruby JVM doesn't support ProcessBuilder redirection
  # (1.6 and older).

  def find_pager_jruby pager
    require 'java'
    require 'shellwords'

    return nil unless java.lang.ProcessBuilder.constants.include? :Redirect

    pager = Shellwords.split pager

    pb = java.lang.ProcessBuilder.new(*pager)
    pb = pb.redirect_output java.lang.ProcessBuilder::Redirect::INHERIT

    @jruby_pager_process = pb.start

    input = @jruby_pager_process.output_stream

    io = input.to_io
    io.sync = true
    io
  rescue java.io.IOException
    false
  end

  ##
  # Finds a store that matches +name+ which can be the name of a gem, "ruby",
  # "home" or "site".
  #
  # See also RDoc::Store#source

  def find_store name
    @stores.each do |store|
      source = store.source

      return source if source == name

      return source if
        store.type == :gem and source =~ /^#{Regexp.escape name}-\d/
    end

    raise RDoc::RI::Driver::NotFoundError, name
  end

  ##
  # Creates a new RDoc::Markup::Formatter.  If a formatter is given with -f,
  # use it.  If we're outputting to a pager, use bs, otherwise ansi.

  def formatter(io)
    if @formatter_klass then
      @formatter_klass.new
    elsif paging? or !io.tty? then
      RDoc::Markup::ToBs.new
    else
      RDoc::Markup::ToAnsi.new
    end
  end

  ##
  # Runs ri interactively using Readline if it is available.

  def interactive
    puts "\nEnter the method name you want to look up."

    if defined? Readline then
      Readline.completion_proc = method :complete
      puts "You can use tab to autocomplete."
    end

    puts "Enter a blank line to exit.\n\n"

    loop do
      name = if defined? Readline then
               Readline.readline ">> "
             else
               print ">> "
               $stdin.gets
             end

      return if name.nil? or name.empty?

      begin
        display_name expand_name(name.strip)
      rescue NotFoundError => e
        puts e.message
      end
    end

  rescue Interrupt
    exit
  end

  ##
  # Is +file+ in ENV['PATH']?

  def in_path? file
    return true if file =~ %r%\A/% and File.exist? file

    ENV['PATH'].split(File::PATH_SEPARATOR).any? do |path|
      File.exist? File.join(path, file)
    end
  end

  ##
  # Lists classes known to ri starting with +names+.  If +names+ is empty all
  # known classes are shown.

  def list_known_classes names = []
    classes = []

    stores.each do |store|
      classes << store.module_names
    end

    classes = classes.flatten.uniq.sort

    unless names.empty? then
      filter = Regexp.union names.map { |name| /^#{name}/ }

      classes = classes.grep filter
    end

    page do |io|
      if paging? or io.tty? then
        if names.empty? then
          io.puts "Classes and Modules known to ri:"
        else
          io.puts "Classes and Modules starting with #{names.join ', '}:"
        end
        io.puts
      end

      io.puts classes.join("\n")
    end
  end

  ##
  # Returns an Array of methods matching +name+

  def list_methods_matching name
    found = []

    find_methods name do |store, klass, ancestor, types, method|
      if types == :instance or types == :both then
        methods = store.instance_methods[ancestor]

        if methods then
          matches = methods.grep(/^#{Regexp.escape method.to_s}/)

          matches = matches.map do |match|
            "#{klass}##{match}"
          end

          found.concat matches
        end
      end

      if types == :class or types == :both then
        methods = store.class_methods[ancestor]

        next unless methods
        matches = methods.grep(/^#{Regexp.escape method.to_s}/)

        matches = matches.map do |match|
          "#{klass}::#{match}"
        end

        found.concat matches
      end
    end

    found.uniq
  end

  ##
  # Loads RI data for method +name+ on +klass+ from +store+.  +type+ and
  # +cache+ indicate if it is a class or instance method.

  def load_method store, cache, klass, type, name
    methods = store.public_send(cache)[klass]

    return unless methods

    method = methods.find do |method_name|
      method_name == name
    end

    return unless method

    store.load_method klass, "#{type}#{method}"
  rescue RDoc::Store::MissingFileError => e
    comment = RDoc::Comment.new("missing documentation at #{e.file}").parse

    method = RDoc::AnyMethod.new nil, name
    method.comment = comment
    method
  end

  ##
  # Returns an Array of RI data for methods matching +name+

  def load_methods_matching name
    found = []

    find_methods name do |store, klass, ancestor, types, method|
      methods = []

      methods << load_method(store, :class_methods, ancestor, '::',  method) if
        [:class, :both].include? types

      methods << load_method(store, :instance_methods, ancestor, '#',  method) if
        [:instance, :both].include? types

      found << [store, methods.compact]
    end

    found.reject do |path, methods| methods.empty? end
  end

  ##
  # Returns a filtered list of methods matching +name+

  def lookup_method name
    found = load_methods_matching name

    if found.empty?
      if check_did_you_mean
        methods = []
        _, _, method_name = parse_name name
        find_methods name do |store, klass, ancestor, types, method|
          methods.push(*store.class_methods[klass]) if [:class, :both].include? types
          methods.push(*store.instance_methods[klass]) if [:instance, :both].include? types
        end
        methods = methods.uniq
        suggestions = DidYouMean::SpellChecker.new(dictionary: methods).correct(method_name)
        raise NotFoundError.new(name, suggestions)
      else
        raise NotFoundError, name
      end
    end

    filter_methods found, name
  end

  ##
  # Builds a RDoc::Markup::Document from +found+, +klasses+ and +includes+

  def method_document name, filtered
    out = RDoc::Markup::Document.new

    out << RDoc::Markup::Heading.new(1, name)
    out << RDoc::Markup::BlankLine.new

    filtered.each do |store, methods|
      methods.each do |method|
        render_method out, store, method, name
      end
    end

    out
  end

  ##
  # Returns the type of method (:both, :instance, :class) for +selector+

  def method_type selector
    case selector
    when '.', nil then :both
    when '#'      then :instance
    else               :class
    end
  end

  ##
  # Returns a regular expression for +name+ that will match an
  # RDoc::AnyMethod's name.

  def name_regexp name
    klass, type, name = parse_name name

    case type
    when '#', '::' then
      /^#{klass}#{type}#{Regexp.escape name}$/
    else
      /^#{klass}(#|::)#{Regexp.escape name}$/
    end
  end

  ##
  # Paginates output through a pager program.

  def page
    if pager = setup_pager then
      begin
        yield pager
      ensure
        pager.close
        @jruby_pager_process.wait_for if @jruby_pager_process
      end
    else
      yield $stdout
    end
  rescue Errno::EPIPE
  ensure
    @paging = false
  end

  ##
  # Are we using a pager?

  def paging?
    @paging
  end

  ##
  # Extracts the class, selector and method name parts from +name+ like
  # Foo::Bar#baz.
  #
  # NOTE: Given Foo::Bar, Bar is considered a class even though it may be a
  # method

  def parse_name name
    parts = name.split(/(::?|#|\.)/)

    if parts.length == 1 then
      if parts.first =~ /^[a-z]|^([%&*+\/<>^`|~-]|\+@|-@|<<|<=>?|===?|=>|=~|>>|\[\]=?|~@)$/ then
        type = '.'
        meth = parts.pop
      else
        type = nil
        meth = nil
      end
    elsif parts.length == 2 or parts.last =~ /::|#|\./ then
      type = parts.pop
      meth = nil
    elsif parts[1] == ':' then
      klass = parts.shift
      type  = parts.shift
      meth  = parts.join
    elsif parts[-2] != '::' or parts.last !~ /^[A-Z]/ then
      meth = parts.pop
      type = parts.pop
    end

    klass ||= parts.join

    [klass, type, meth]
  end

  ##
  # Renders the +klass+ from +store+ to +out+.  If the klass has no
  # documentable items the class is added to +also_in+ instead.

  def render_class out, store, klass, also_in # :nodoc:
    comment = klass.comment
    # TODO the store's cache should always return an empty Array
    class_methods    = store.class_methods[klass.full_name]    || []
    instance_methods = store.instance_methods[klass.full_name] || []
    attributes       = store.attributes[klass.full_name]       || []

    if comment.empty? and
       instance_methods.empty? and class_methods.empty? then
      also_in << store
      return
    end

    add_from out, store

    class_document_comment out, comment

    if class_methods or instance_methods or not klass.constants.empty? then
      out << RDoc::Markup::Rule.new(1)
    end

    class_document_constants out, klass

    add_method_list out, class_methods,    'Class methods'
    add_method_list out, instance_methods, 'Instance methods'
    add_method_list out, attributes,       'Attributes'

    add_method_documentation out, klass if @show_all
  end

  def render_method out, store, method, name # :nodoc:
    out << RDoc::Markup::Paragraph.new("(from #{store.friendly_path})")

    unless name =~ /^#{Regexp.escape method.parent_name}/ then
      out << RDoc::Markup::Heading.new(3, "Implementation from #{method.parent_name}")
    end

    out << RDoc::Markup::Rule.new(1)

    render_method_arguments out, method.arglists
    render_method_superclass out, method
    if method.is_alias_for
      al = method.is_alias_for
      alias_for = store.load_method al.parent_name, "#{al.name_prefix}#{al.name}"
      render_method_comment out, method, alias_for
    else
      render_method_comment out, method
    end
  end

  def render_method_arguments out, arglists # :nodoc:
    return unless arglists

    arglists = arglists.chomp.split "\n"
    arglists = arglists.map { |line| line + "\n" }
    out << RDoc::Markup::Verbatim.new(*arglists)
    out << RDoc::Markup::Rule.new(1)
  end

  def render_method_comment out, method, alias_for = nil# :nodoc:
    if alias_for
      unless method.comment.nil? or method.comment.empty?
        out << RDoc::Markup::BlankLine.new
        out << method.comment
      end
      out << RDoc::Markup::BlankLine.new
      out << RDoc::Markup::Paragraph.new("(This method is an alias for #{alias_for.full_name}.)")
      out << RDoc::Markup::BlankLine.new
      out << alias_for.comment
      out << RDoc::Markup::BlankLine.new
    else
      out << RDoc::Markup::BlankLine.new
      out << method.comment
      out << RDoc::Markup::BlankLine.new
    end
  end

  def render_method_superclass out, method # :nodoc:
    return unless
      method.respond_to?(:superclass_method) and method.superclass_method

    out << RDoc::Markup::BlankLine.new
    out << RDoc::Markup::Heading.new(4, "(Uses superclass method #{method.superclass_method})")
    out << RDoc::Markup::Rule.new(1)
  end

  ##
  # Looks up and displays ri data according to the options given.

  def run
    if @list_doc_dirs then
      puts @doc_dirs
    elsif @list then
      list_known_classes @names
    elsif @server then
      start_server
    elsif @interactive or @names.empty? then
      interactive
    else
      display_names @names
    end
  rescue NotFoundError => e
    abort e.message
  end

  ##
  # Sets up a pager program to pass output through.  Tries the RI_PAGER and
  # PAGER environment variables followed by pager, less then more.

  def setup_pager
    return if @use_stdout

    jruby = RUBY_ENGINE == 'jruby'

    pagers = [ENV['RI_PAGER'], ENV['PAGER'], 'pager', 'less', 'more']

    pagers.compact.uniq.each do |pager|
      next unless pager

      pager_cmd = pager.split(' ').first

      next unless in_path? pager_cmd

      if jruby then
        case io = find_pager_jruby(pager)
        when nil   then break
        when false then next
        else            io
        end
      else
        io = IO.popen(pager, 'w') rescue next
      end

      next if $? and $?.pid == io.pid and $?.exited? # pager didn't work

      @paging = true

      return io
    end

    @use_stdout = true

    nil
  end

  ##
  # Starts a WEBrick server for ri.

  def start_server
    begin
      require 'webrick'
    rescue LoadError
      abort "webrick is not found. You may need to `gem install webrick` to install webrick."
    end

    server = WEBrick::HTTPServer.new :Port => @server

    extra_doc_dirs = @stores.map {|s| s.type == :extra ? s.path : nil}.compact

    server.mount '/', RDoc::Servlet, nil, extra_doc_dirs

    trap 'INT'  do server.shutdown end
    trap 'TERM' do server.shutdown end

    server.start
  end

end
