# frozen_string_literal: true
require 'optparse'
require 'pathname'

##
# RDoc::Options handles the parsing and storage of options
#
# == Saved Options
#
# You can save some options like the markup format in the
# <tt>.rdoc_options</tt> file in your gem.  The easiest way to do this is:
#
#   rdoc --markup tomdoc --write-options
#
# Which will automatically create the file and fill it with the options you
# specified.
#
# The following options will not be saved since they interfere with the user's
# preferences or with the normal operation of RDoc:
#
# * +--coverage-report+
# * +--dry-run+
# * +--encoding+
# * +--force-update+
# * +--format+
# * +--pipe+
# * +--quiet+
# * +--template+
# * +--verbose+
#
# == Custom Options
#
# Generators can hook into RDoc::Options to add generator-specific command
# line options.
#
# When <tt>--format</tt> is encountered in ARGV, RDoc calls ::setup_options on
# the generator class to add extra options to the option parser.  Options for
# custom generators must occur after <tt>--format</tt>.  <tt>rdoc --help</tt>
# will list options for all installed generators.
#
# Example:
#
#   class RDoc::Generator::Spellcheck
#     RDoc::RDoc.add_generator self
#
#     def self.setup_options rdoc_options
#       op = rdoc_options.option_parser
#
#       op.on('--spell-dictionary DICTIONARY',
#             RDoc::Options::Path) do |dictionary|
#         rdoc_options.spell_dictionary = dictionary
#       end
#     end
#   end
#
# Of course, RDoc::Options does not respond to +spell_dictionary+ by default
# so you will need to add it:
#
#   class RDoc::Options
#
#     ##
#     # The spell dictionary used by the spell-checking plugin.
#
#     attr_accessor :spell_dictionary
#
#   end
#
# == Option Validators
#
# OptionParser validators will validate and cast user input values.  In
# addition to the validators that ship with OptionParser (String, Integer,
# Float, TrueClass, FalseClass, Array, Regexp, Date, Time, URI, etc.),
# RDoc::Options adds Path, PathArray and Template.

class RDoc::Options

  ##
  # The deprecated options.

  DEPRECATED = {
    '--accessor'      => 'support discontinued',
    '--diagram'       => 'support discontinued',
    '--help-output'   => 'support discontinued',
    '--image-format'  => 'was an option for --diagram',
    '--inline-source' => 'source code is now always inlined',
    '--merge'         => 'ri now always merges class information',
    '--one-file'      => 'support discontinued',
    '--op-name'       => 'support discontinued',
    '--opname'        => 'support discontinued',
    '--promiscuous'   => 'files always only document their content',
    '--ri-system'     => 'Ruby installers use other techniques',
  }

  ##
  # RDoc options ignored (or handled specially) by --write-options

  SPECIAL = %w[
    coverage_report
    dry_run
    encoding
    files
    force_output
    force_update
    generator
    generator_name
    generator_options
    generators
    op_dir
    page_dir
    option_parser
    pipe
    rdoc_include
    root
    static_path
    stylesheet_url
    template
    template_dir
    update_output_dir
    verbosity
    write_options
  ]

  ##
  # Option validator for OptionParser that matches a directory that exists on
  # the filesystem.

  Directory = Object.new

  ##
  # Option validator for OptionParser that matches a file or directory that
  # exists on the filesystem.

  Path = Object.new

  ##
  # Option validator for OptionParser that matches a comma-separated list of
  # files or directories that exist on the filesystem.

  PathArray = Object.new

  ##
  # Option validator for OptionParser that matches a template directory for an
  # installed generator that lives in
  # <tt>"rdoc/generator/template/#{template_name}"</tt>

  Template = Object.new

  ##
  # Character-set for HTML output.  #encoding is preferred over #charset

  attr_accessor :charset

  ##
  # If true, RDoc will not write any files.

  attr_accessor :dry_run

  ##
  # The output encoding.  All input files will be transcoded to this encoding.
  #
  # The default encoding is UTF-8.  This is set via --encoding.

  attr_accessor :encoding

  ##
  # Files matching this pattern will be excluded

  attr_writer :exclude

  ##
  # The list of files to be processed

  attr_accessor :files

  ##
  # Create the output even if the output directory does not look
  # like an rdoc output directory

  attr_accessor :force_output

  ##
  # Scan newer sources than the flag file if true.

  attr_accessor :force_update

  ##
  # Formatter to mark up text with

  attr_accessor :formatter

  ##
  # Description of the output generator (set with the <tt>--format</tt> option)

  attr_accessor :generator

  ##
  # For #==

  attr_reader :generator_name # :nodoc:

  ##
  # Loaded generator options.  Used to prevent --help from loading the same
  # options multiple times.

  attr_accessor :generator_options

  ##
  # Old rdoc behavior: hyperlink all words that match a method name,
  # even if not preceded by '#' or '::'

  attr_accessor :hyperlink_all

  ##
  # Include line numbers in the source code

  attr_accessor :line_numbers

  ##
  # The output locale.

  attr_accessor :locale

  ##
  # The directory where locale data live.

  attr_accessor :locale_dir

  ##
  # Name of the file, class or module to display in the initial index page (if
  # not specified the first file we encounter is used)

  attr_accessor :main_page

  ##
  # The default markup format.  The default is 'rdoc'.  'markdown', 'tomdoc'
  # and 'rd' are also built-in.

  attr_accessor :markup

  ##
  # If true, only report on undocumented files

  attr_accessor :coverage_report

  ##
  # The name of the output directory

  attr_accessor :op_dir

  ##
  # The OptionParser for this instance

  attr_accessor :option_parser

  ##
  # Output heading decorations?
  attr_accessor :output_decoration

  ##
  # Directory where guides, FAQ, and other pages not associated with a class
  # live.  You may leave this unset if these are at the root of your project.

  attr_accessor :page_dir

  ##
  # Is RDoc in pipe mode?

  attr_accessor :pipe

  ##
  # Array of directories to search for files to satisfy an :include:

  attr_accessor :rdoc_include

  ##
  # Root of the source documentation will be generated for.  Set this when
  # building documentation outside the source directory.  Defaults to the
  # current directory.

  attr_accessor :root

  ##
  # Include the '#' at the front of hyperlinked instance method names

  attr_accessor :show_hash

  ##
  # Directory to copy static files from

  attr_accessor :static_path

  ##
  # The number of columns in a tab

  attr_accessor :tab_width

  ##
  # Template to be used when generating output

  attr_accessor :template

  ##
  # Directory the template lives in

  attr_accessor :template_dir

  ##
  # Additional template stylesheets

  attr_accessor :template_stylesheets

  ##
  # Documentation title

  attr_accessor :title

  ##
  # Should RDoc update the timestamps in the output dir?

  attr_accessor :update_output_dir

  ##
  # Verbosity, zero means quiet

  attr_accessor :verbosity

  ##
  # URL of web cvs frontend

  attr_accessor :webcvs

  ##
  # Minimum visibility of a documented method. One of +:public+, +:protected+,
  # +:private+ or +:nodoc+.
  #
  # The +:nodoc+ visibility ignores all directives related to visibility.  The
  # other visibilities may be overridden on a per-method basis with the :doc:
  # directive.

  attr_reader :visibility

  ##
  # Indicates if files of test suites should be skipped
  attr_accessor :skip_tests

  def initialize loaded_options = nil # :nodoc:
    init_ivars
    override loaded_options if loaded_options
  end

  def init_ivars # :nodoc:
    @dry_run = false
    @exclude = %w[
      ~\z \.orig\z \.rej\z \.bak\z
      \.gemspec\z
    ]
    @files = nil
    @force_output = false
    @force_update = true
    @generator = nil
    @generator_name = nil
    @generator_options = []
    @generators = RDoc::RDoc::GENERATORS
    @hyperlink_all = false
    @line_numbers = false
    @locale = nil
    @locale_name = nil
    @locale_dir = 'locale'
    @main_page = nil
    @markup = 'rdoc'
    @coverage_report = false
    @op_dir = nil
    @page_dir = nil
    @pipe = false
    @output_decoration = true
    @rdoc_include = []
    @root = Pathname(Dir.pwd)
    @show_hash = false
    @static_path = []
    @stylesheet_url = nil # TODO remove in RDoc 4
    @tab_width = 8
    @template = nil
    @template_dir = nil
    @template_stylesheets = []
    @title = nil
    @update_output_dir = true
    @verbosity = 1
    @visibility = :protected
    @webcvs = nil
    @write_options = false
    @encoding = Encoding::UTF_8
    @charset = @encoding.name
    @skip_tests = true
  end

  def init_with map # :nodoc:
    init_ivars

    encoding = map['encoding']
    @encoding = encoding ? Encoding.find(encoding) : encoding

    @charset        = map['charset']
    @exclude        = map['exclude']
    @generator_name = map['generator_name']
    @hyperlink_all  = map['hyperlink_all']
    @line_numbers   = map['line_numbers']
    @locale_name    = map['locale_name']
    @locale_dir     = map['locale_dir']
    @main_page      = map['main_page']
    @markup         = map['markup']
    @op_dir         = map['op_dir']
    @show_hash      = map['show_hash']
    @tab_width      = map['tab_width']
    @template_dir   = map['template_dir']
    @title          = map['title']
    @visibility     = map['visibility']
    @webcvs         = map['webcvs']

    @rdoc_include = sanitize_path map['rdoc_include']
    @static_path  = sanitize_path map['static_path']
  end

  def yaml_initialize tag, map # :nodoc:
    init_with map
  end

  def override map # :nodoc:
    if map.has_key?('encoding')
      encoding = map['encoding']
      @encoding = encoding ? Encoding.find(encoding) : encoding
    end

    @charset        = map['charset']        if map.has_key?('charset')
    @exclude        = map['exclude']        if map.has_key?('exclude')
    @generator_name = map['generator_name'] if map.has_key?('generator_name')
    @hyperlink_all  = map['hyperlink_all']  if map.has_key?('hyperlink_all')
    @line_numbers   = map['line_numbers']   if map.has_key?('line_numbers')
    @locale_name    = map['locale_name']    if map.has_key?('locale_name')
    @locale_dir     = map['locale_dir']     if map.has_key?('locale_dir')
    @main_page      = map['main_page']      if map.has_key?('main_page')
    @markup         = map['markup']         if map.has_key?('markup')
    @op_dir         = map['op_dir']         if map.has_key?('op_dir')
    @page_dir       = map['page_dir']       if map.has_key?('page_dir')
    @show_hash      = map['show_hash']      if map.has_key?('show_hash')
    @tab_width      = map['tab_width']      if map.has_key?('tab_width')
    @template_dir   = map['template_dir']   if map.has_key?('template_dir')
    @title          = map['title']          if map.has_key?('title')
    @visibility     = map['visibility']     if map.has_key?('visibility')
    @webcvs         = map['webcvs']         if map.has_key?('webcvs')

    if map.has_key?('rdoc_include')
      @rdoc_include = sanitize_path map['rdoc_include']
    end
    if map.has_key?('static_path')
      @static_path  = sanitize_path map['static_path']
    end
  end

  def == other # :nodoc:
    self.class === other and
      @encoding       == other.encoding       and
      @generator_name == other.generator_name and
      @hyperlink_all  == other.hyperlink_all  and
      @line_numbers   == other.line_numbers   and
      @locale         == other.locale         and
      @locale_dir     == other.locale_dir and
      @main_page      == other.main_page      and
      @markup         == other.markup         and
      @op_dir         == other.op_dir         and
      @rdoc_include   == other.rdoc_include   and
      @show_hash      == other.show_hash      and
      @static_path    == other.static_path    and
      @tab_width      == other.tab_width      and
      @template       == other.template       and
      @title          == other.title          and
      @visibility     == other.visibility     and
      @webcvs         == other.webcvs
  end

  ##
  # Check that the files on the command line exist

  def check_files
    @files.delete_if do |file|
      if File.exist? file then
        if File.readable? file then
          false
        else
          warn "file '#{file}' not readable"

          true
        end
      else
        warn "file '#{file}' not found"

        true
      end
    end
  end

  ##
  # Ensure only one generator is loaded

  def check_generator
    if @generator then
      raise OptionParser::InvalidOption,
        "generator already set to #{@generator_name}"
    end
  end

  ##
  # Set the title, but only if not already set. Used to set the title
  # from a source file, so that a title set from the command line
  # will have the priority.

  def default_title=(string)
    @title ||= string
  end

  ##
  # For dumping YAML

  def to_yaml(*options) # :nodoc:
    encoding = @encoding ? @encoding.name : nil

    yaml = {}
    yaml['encoding'] = encoding
    yaml['static_path'] = sanitize_path(@static_path)
    yaml['rdoc_include'] = sanitize_path(@rdoc_include)
    yaml['page_dir'] = (sanitize_path([@page_dir]).first if @page_dir)

    ivars = instance_variables.map { |ivar| ivar.to_s[1..-1] }
    ivars -= SPECIAL

    ivars.sort.each do |ivar|
      yaml[ivar] = instance_variable_get("@#{ivar}")
    end
    yaml.to_yaml
  end

  ##
  # Create a regexp for #exclude

  def exclude
    if @exclude.nil? or Regexp === @exclude then
      # done, #finish is being re-run
      @exclude
    elsif @exclude.empty? then
      nil
    else
      Regexp.new(@exclude.join("|"))
    end
  end

  ##
  # Completes any unfinished option setup business such as filtering for
  # existent files, creating a regexp for #exclude and setting a default
  # #template.

  def finish
    if @write_options then
      write_options
      exit
    end

    @op_dir ||= 'doc'

    root = @root.to_s
    if @rdoc_include.empty? || !@rdoc_include.include?(root)
      @rdoc_include << root
    end

    @exclude = self.exclude

    finish_page_dir

    check_files

    # If no template was specified, use the default template for the output
    # formatter

    unless @template then
      @template     = @generator_name
      @template_dir = template_dir_for @template
    end

    if @locale_name
      @locale = RDoc::I18n::Locale[@locale_name]
      @locale.load(@locale_dir)
    else
      @locale = nil
    end

    self
  end

  ##
  # Fixes the page_dir to be relative to the root_dir and adds the page_dir to
  # the files list.

  def finish_page_dir
    return unless @page_dir

    @files << @page_dir

    page_dir = Pathname(@page_dir)
    begin
      page_dir = page_dir.expand_path.relative_path_from @root
    rescue ArgumentError
      # On Windows, sometimes crosses different drive letters.
      page_dir = page_dir.expand_path
    end

    @page_dir = page_dir
  end

  ##
  # Returns a properly-space list of generators and their descriptions.

  def generator_descriptions
    lengths = []

    generators = RDoc::RDoc::GENERATORS.map do |name, generator|
      lengths << name.length

      description = generator::DESCRIPTION if
        generator.const_defined? :DESCRIPTION

      [name, description]
    end

    longest = lengths.max

    generators.sort.map do |name, description|
      if description then
        "  %-*s - %s" % [longest, name, description]
      else
        "  #{name}"
      end
    end.join "\n"
  end

  ##
  # Parses command line options.

  def parse argv
    ignore_invalid = true

    argv.insert(0, *ENV['RDOCOPT'].split) if ENV['RDOCOPT']

    opts = OptionParser.new do |opt|
      @option_parser = opt
      opt.program_name = File.basename $0
      opt.version = RDoc::VERSION
      opt.release = nil
      opt.summary_indent = ' ' * 4
      opt.banner = <<-EOF
Usage: #{opt.program_name} [options] [names...]

  Files are parsed, and the information they contain collected, before any
  output is produced. This allows cross references between all files to be
  resolved. If a name is a directory, it is traversed. If no names are
  specified, all Ruby files in the current directory (and subdirectories) are
  processed.

  How RDoc generates output depends on the output formatter being used, and on
  the options you give.

  Options can be specified via the RDOCOPT environment variable, which
  functions similar to the RUBYOPT environment variable for ruby.

    $ export RDOCOPT="--show-hash"

  will make rdoc show hashes in method links by default.  Command-line options
  always will override those in RDOCOPT.

  Available formatters:

#{generator_descriptions}

  RDoc understands the following file formats:

      EOF

      parsers = Hash.new { |h,parser| h[parser] = [] }

      RDoc::Parser.parsers.each do |regexp, parser|
        parsers[parser.name.sub('RDoc::Parser::', '')] << regexp.source
      end

      parsers.sort.each do |parser, regexp|
        opt.banner += "  - #{parser}: #{regexp.join ', '}\n"
      end
      opt.banner += "  - TomDoc:  Only in ruby files\n"

      opt.banner += "\n  The following options are deprecated:\n\n"

      name_length = DEPRECATED.keys.sort_by { |k| k.length }.last.length

      DEPRECATED.sort_by { |k,| k }.each do |name, reason|
        opt.banner += "    %*1$2$s  %3$s\n" % [-name_length, name, reason]
      end

      opt.accept Template do |template|
        template_dir = template_dir_for template

        unless template_dir then
          $stderr.puts "could not find template #{template}"
          nil
        else
          [template, template_dir]
        end
      end

      opt.accept Directory do |directory|
        directory = File.expand_path directory

        raise OptionParser::InvalidArgument unless File.directory? directory

        directory
      end

      opt.accept Path do |path|
        path = File.expand_path path

        raise OptionParser::InvalidArgument unless File.exist? path

        path
      end

      opt.accept PathArray do |paths,|
        paths = if paths then
                  paths.split(',').map { |d| d unless d.empty? }
                end

        paths.map do |path|
          path = File.expand_path path

          raise OptionParser::InvalidArgument unless File.exist? path

          path
        end
      end

      opt.separator nil
      opt.separator "Parsing options:"
      opt.separator nil

      opt.on("--encoding=ENCODING", "-e", Encoding.list.map { |e| e.name },
             "Specifies the output encoding.  All files",
             "read will be converted to this encoding.",
             "The default encoding is UTF-8.",
             "--encoding is preferred over --charset") do |value|
               @encoding = Encoding.find value
               @charset = @encoding.name # may not be valid value
             end

      opt.separator nil

      opt.on("--locale=NAME",
             "Specifies the output locale.") do |value|
        @locale_name = value
      end

      opt.on("--locale-data-dir=DIR",
             "Specifies the directory where locale data live.") do |value|
        @locale_dir = value
      end

      opt.separator nil

      opt.on("--all", "-a",
             "Synonym for --visibility=private.") do |value|
        @visibility = :private
      end

      opt.separator nil

      opt.on("--exclude=PATTERN", "-x", Regexp,
             "Do not process files or directories",
             "matching PATTERN.") do |value|
        @exclude << value
      end

      opt.separator nil

      opt.on("--no-skipping-tests", nil,
             "Don't skip generating documentation for test and spec files") do |value|
        @skip_tests = false
      end

      opt.separator nil

      opt.on("--extension=NEW=OLD", "-E",
             "Treat files ending with .new as if they",
             "ended with .old. Using '-E cgi=rb' will",
             "cause xxx.cgi to be parsed as a Ruby file.") do |value|
        new, old = value.split(/=/, 2)

        unless new and old then
          raise OptionParser::InvalidArgument, "Invalid parameter to '-E'"
        end

        unless RDoc::Parser.alias_extension old, new then
          raise OptionParser::InvalidArgument, "Unknown extension .#{old} to -E"
        end
      end

      opt.separator nil

      opt.on("--[no-]force-update", "-U",
             "Forces rdoc to scan all sources even if",
             "no files are newer than the flag file.") do |value|
        @force_update = value
      end

      opt.separator nil

      opt.on("--pipe", "-p",
             "Convert RDoc on stdin to HTML") do
        @pipe = true
      end

      opt.separator nil

      opt.on("--tab-width=WIDTH", "-w", Integer,
             "Set the width of tab characters.") do |value|
        raise OptionParser::InvalidArgument,
              "#{value} is an invalid tab width" if value <= 0
        @tab_width = value
      end

      opt.separator nil

      opt.on("--visibility=VISIBILITY", "-V", RDoc::VISIBILITIES + [:nodoc],
             "Minimum visibility to document a method.",
             "One of 'public', 'protected' (the default),",
             "'private' or 'nodoc' (show everything)") do |value|
        @visibility = value
      end

      opt.separator nil

      markup_formats = RDoc::Text::MARKUP_FORMAT.keys.sort

      opt.on("--markup=MARKUP", markup_formats,
             "The markup format for the named files.",
             "The default is rdoc.  Valid values are:",
             markup_formats.join(', ')) do |value|
        @markup = value
      end

      opt.separator nil

      opt.on("--root=ROOT", Directory,
             "Root of the source tree documentation",
             "will be generated for.  Set this when",
             "building documentation outside the",
             "source directory.  Default is the",
             "current directory.") do |root|
        @root = Pathname(root)
      end

      opt.separator nil

      opt.on("--page-dir=DIR", Directory,
             "Directory where guides, your FAQ or",
             "other pages not associated with a class",
             "live.  Set this when you don't store",
             "such files at your project root.",
             "NOTE: Do not use the same file name in",
             "the page dir and the root of your project") do |page_dir|
        @page_dir = page_dir
      end

      opt.separator nil
      opt.separator "Common generator options:"
      opt.separator nil

      opt.on("--force-output", "-O",
             "Forces rdoc to write the output files,",
             "even if the output directory exists",
             "and does not seem to have been created",
             "by rdoc.") do |value|
        @force_output = value
      end

      opt.separator nil

      generator_text = @generators.keys.map { |name| "  #{name}" }.sort

      opt.on("-f", "--fmt=FORMAT", "--format=FORMAT", @generators.keys,
             "Set the output formatter.  One of:", *generator_text) do |value|
        check_generator

        @generator_name = value.downcase
        setup_generator
      end

      opt.separator nil

      opt.on("--include=DIRECTORIES", "-i", PathArray,
             "Set (or add to) the list of directories to",
             "be searched when satisfying :include:",
             "requests. Can be used more than once.") do |value|
        @rdoc_include.concat value.map { |dir| dir.strip }
      end

      opt.separator nil

      opt.on("--[no-]coverage-report=[LEVEL]", "--[no-]dcov", "-C", Integer,
             "Prints a report on undocumented items.",
             "Does not generate files.") do |value|
        value = 0 if value.nil? # Integer converts -C to nil

        @coverage_report = value
        @force_update = true if value
      end

      opt.separator nil

      opt.on("--output=DIR", "--op", "-o",
             "Set the output directory.") do |value|
        @op_dir = value
      end

      opt.separator nil

      opt.on("-d",
             "Deprecated --diagram option.",
             "Prevents firing debug mode",
             "with legacy invocation.") do |value|
      end

      opt.separator nil
      opt.separator 'HTML generator options:'
      opt.separator nil

      opt.on("--charset=CHARSET", "-c",
             "Specifies the output HTML character-set.",
             "Use --encoding instead of --charset if",
             "available.") do |value|
        @charset = value
      end

      opt.separator nil

      opt.on("--hyperlink-all", "-A",
             "Generate hyperlinks for all words that",
             "correspond to known methods, even if they",
             "do not start with '#' or '::' (legacy",
             "behavior).") do |value|
        @hyperlink_all = value
      end

      opt.separator nil

      opt.on("--main=NAME", "-m",
             "NAME will be the initial page displayed.") do |value|
        @main_page = value
      end

      opt.separator nil

      opt.on("--[no-]line-numbers", "-N",
             "Include line numbers in the source code.",
             "By default, only the number of the first",
             "line is displayed, in a leading comment.") do |value|
        @line_numbers = value
      end

      opt.separator nil

      opt.on("--show-hash", "-H",
             "A name of the form #name in a comment is a",
             "possible hyperlink to an instance method",
             "name. When displayed, the '#' is removed",
             "unless this option is specified.") do |value|
        @show_hash = value
      end

      opt.separator nil

      opt.on("--template=NAME", "-T", Template,
             "Set the template used when generating",
             "output. The default depends on the",
             "formatter used.") do |(template, template_dir)|
        @template     = template
        @template_dir = template_dir
      end

      opt.separator nil

      opt.on("--template-stylesheets=FILES", PathArray,
             "Set (or add to) the list of files to",
             "include with the html template.") do |value|
        @template_stylesheets.concat value
      end

      opt.separator nil

      opt.on("--title=TITLE", "-t",
             "Set TITLE as the title for HTML output.") do |value|
        @title = value
      end

      opt.separator nil

      opt.on("--copy-files=PATH", Path,
             "Specify a file or directory to copy static",
             "files from.",
             "If a file is given it will be copied into",
             "the output dir.  If a directory is given the",
             "entire directory will be copied.",
             "You can use this multiple times") do |value|
        @static_path << value
      end

      opt.separator nil

      opt.on("--webcvs=URL", "-W",
             "Specify a URL for linking to a web frontend",
             "to CVS. If the URL contains a '\%s', the",
             "name of the current file will be",
             "substituted; if the URL doesn't contain a",
             "'\%s', the filename will be appended to it.") do |value|
        @webcvs = value
      end

      opt.separator nil
      opt.separator "ri generator options:"
      opt.separator nil

      opt.on("--ri", "-r",
             "Generate output for use by `ri`. The files",
             "are stored in the '.rdoc' directory under",
             "your home directory unless overridden by a",
             "subsequent --op parameter, so no special",
             "privileges are needed.") do |value|
        check_generator

        @generator_name = "ri"
        @op_dir ||= RDoc::RI::Paths::HOMEDIR
        setup_generator
      end

      opt.separator nil

      opt.on("--ri-site", "-R",
             "Generate output for use by `ri`. The files",
             "are stored in a site-wide directory,",
             "making them accessible to others, so",
             "special privileges are needed.") do |value|
        check_generator

        @generator_name = "ri"
        @op_dir = RDoc::RI::Paths.site_dir
        setup_generator
      end

      opt.separator nil
      opt.separator "Generic options:"
      opt.separator nil

      opt.on("--write-options",
             "Write .rdoc_options to the current",
             "directory with the given options.  Not all",
             "options will be used.  See RDoc::Options",
             "for details.") do |value|
        @write_options = true
      end

      opt.separator nil

      opt.on("--[no-]dry-run",
             "Don't write any files") do |value|
        @dry_run = value
      end

      opt.separator nil

      opt.on("-D", "--[no-]debug",
             "Displays lots on internal stuff.") do |value|
        $DEBUG_RDOC = value
      end

      opt.separator nil

      opt.on("--[no-]ignore-invalid",
             "Ignore invalid options and continue",
             "(default true).") do |value|
        ignore_invalid = value
      end

      opt.separator nil

      opt.on("--quiet", "-q",
             "Don't show progress as we parse.") do |value|
        @verbosity = 0
      end

      opt.separator nil

      opt.on("--verbose", "-V",
             "Display extra progress as RDoc parses") do |value|
        @verbosity = 2
      end

      opt.separator nil

      opt.on("--version", "-v", "print the version") do
        puts opt.version
        exit
      end

      opt.separator nil

      opt.on("--help", "-h", "Display this help") do
        RDoc::RDoc::GENERATORS.each_key do |generator|
          setup_generator generator
        end

        puts opt.help
        exit
      end

      opt.separator nil
    end

    setup_generator 'darkfish' if
      argv.grep(/\A(-f|--fmt|--format|-r|-R|--ri|--ri-site)\b/).empty?

    deprecated = []
    invalid = []

    begin
      opts.parse! argv
    rescue OptionParser::ParseError => e
      if DEPRECATED[e.args.first] then
        deprecated << e.args.first
      elsif %w[--format --ri -r --ri-site -R].include? e.args.first then
        raise
      else
        invalid << e.args.join(' ')
      end

      retry
    end

    unless @generator then
      @generator = RDoc::Generator::Darkfish
      @generator_name = 'darkfish'
    end

    if @pipe and not argv.empty? then
      @pipe = false
      invalid << '-p (with files)'
    end

    unless quiet then
      deprecated.each do |opt|
        $stderr.puts 'option ' + opt + ' is deprecated: ' + DEPRECATED[opt]
      end
    end

    unless invalid.empty? then
      invalid = "invalid options: #{invalid.join ', '}"

      if ignore_invalid then
        unless quiet then
          $stderr.puts invalid
          $stderr.puts '(invalid options are ignored)'
        end
      else
        unless quiet then
          $stderr.puts opts
        end
        $stderr.puts invalid
        exit 1
      end
    end

    @files = argv.dup

    self
  end

  ##
  # Don't display progress as we process the files

  def quiet
    @verbosity.zero?
  end

  ##
  # Set quietness to +bool+

  def quiet= bool
    @verbosity = bool ? 0 : 1
  end

  ##
  # Removes directories from +path+ that are outside the current directory

  def sanitize_path path
    require 'pathname'
    dot = Pathname.new('.').expand_path

    path.reject do |item|
      path = Pathname.new(item).expand_path
      is_reject = nil
      relative = nil
      begin
        relative = path.relative_path_from(dot).to_s
      rescue ArgumentError
        # On Windows, sometimes crosses different drive letters.
        is_reject = true
      else
        is_reject = relative.start_with? '..'
      end
      is_reject
    end
  end

  ##
  # Set up an output generator for the named +generator_name+.
  #
  # If the found generator responds to :setup_options it will be called with
  # the options instance.  This allows generators to add custom options or set
  # default options.

  def setup_generator generator_name = @generator_name
    @generator = @generators[generator_name]

    unless @generator then
      raise OptionParser::InvalidArgument,
            "Invalid output formatter #{generator_name}"
    end

    return if @generator_options.include? @generator

    @generator_name = generator_name
    @generator_options << @generator

    if @generator.respond_to? :setup_options then
      @option_parser ||= OptionParser.new
      @generator.setup_options self
    end
  end

  ##
  # Finds the template dir for +template+

  def template_dir_for template
    template_path = File.join 'rdoc', 'generator', 'template', template

    $LOAD_PATH.map do |path|
      File.join File.expand_path(path), template_path
    end.find do |dir|
      File.directory? dir
    end
  end

  # Sets the minimum visibility of a documented method.
  #
  # Accepts +:public+, +:protected+, +:private+, +:nodoc+, or +:all+.
  #
  # When +:all+ is passed, visibility is set to +:private+, similarly to
  # RDOCOPT="--all", see #visibility for more information.

  def visibility= visibility
    case visibility
    when :all
      @visibility = :private
    else
      @visibility = visibility
    end
  end

  ##
  # Displays a warning using Kernel#warn if we're being verbose

  def warn message
    super message if @verbosity > 1
  end

  ##
  # Writes the YAML file .rdoc_options to the current directory containing the
  # parsed options.

  def write_options
    RDoc.load_yaml

    File.open '.rdoc_options', 'w' do |io|
      io.set_encoding Encoding::UTF_8

      io.print to_yaml
    end
  end

  ##
  # Loads options from .rdoc_options if the file exists, otherwise creates a
  # new RDoc::Options instance.

  def self.load_options
    options_file = File.expand_path '.rdoc_options'
    return RDoc::Options.new unless File.exist? options_file

    RDoc.load_yaml

    begin
      options = YAML.safe_load File.read('.rdoc_options'), permitted_classes: [RDoc::Options, Symbol]
    rescue Psych::SyntaxError
      raise RDoc::Error, "#{options_file} is not a valid rdoc options file"
    end

    return RDoc::Options.new unless options # Allow empty file.

    raise RDoc::Error, "#{options_file} is not a valid rdoc options file" unless
      RDoc::Options === options or Hash === options

    if Hash === options
      # Override the default values with the contents of YAML file.
      options = RDoc::Options.new options
    end

    options
  end

end
