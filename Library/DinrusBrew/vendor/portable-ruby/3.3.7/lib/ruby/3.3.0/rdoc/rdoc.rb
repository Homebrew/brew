# frozen_string_literal: true
require_relative '../rdoc'

require 'find'
require 'fileutils'
require 'pathname'
require 'time'

##
# This is the driver for generating RDoc output.  It handles file parsing and
# generation of output.
#
# To use this class to generate RDoc output via the API, the recommended way
# is:
#
#   rdoc = RDoc::RDoc.new
#   options = RDoc::Options.load_options # returns an RDoc::Options instance
#   # set extra options
#   rdoc.document options
#
# You can also generate output like the +rdoc+ executable:
#
#   rdoc = RDoc::RDoc.new
#   rdoc.document argv
#
# Where +argv+ is an array of strings, each corresponding to an argument you'd
# give rdoc on the command line.  See <tt>rdoc --help</tt> for details.

class RDoc::RDoc

  @current = nil

  ##
  # This is the list of supported output generators

  GENERATORS = {}

  ##
  # List of directory names always skipped

  UNCONDITIONALLY_SKIPPED_DIRECTORIES = %w[CVS .svn .git].freeze

  ##
  # List of directory names skipped if test suites should be skipped

  TEST_SUITE_DIRECTORY_NAMES = %w[spec test].freeze


  ##
  # Generator instance used for creating output

  attr_accessor :generator

  ##
  # Hash of files and their last modified times.

  attr_reader :last_modified

  ##
  # RDoc options

  attr_accessor :options

  ##
  # Accessor for statistics.  Available after each call to parse_files

  attr_reader :stats

  ##
  # The current documentation store

  attr_reader :store

  ##
  # Add +klass+ that can generate output after parsing

  def self.add_generator(klass)
    name = klass.name.sub(/^RDoc::Generator::/, '').downcase
    GENERATORS[name] = klass
  end

  ##
  # Active RDoc::RDoc instance

  def self.current
    @current
  end

  ##
  # Sets the active RDoc::RDoc instance

  def self.current= rdoc
    @current = rdoc
  end

  ##
  # Creates a new RDoc::RDoc instance.  Call #document to parse files and
  # generate documentation.

  def initialize
    @current       = nil
    @generator     = nil
    @last_modified = {}
    @old_siginfo   = nil
    @options       = nil
    @stats         = nil
    @store         = nil
  end

  ##
  # Report an error message and exit

  def error(msg)
    raise RDoc::Error, msg
  end

  ##
  # Gathers a set of parseable files from the files and directories listed in
  # +files+.

  def gather_files files
    files = [@options.root.to_s] if files.empty?

    file_list = normalized_file_list files, true, @options.exclude

    file_list = remove_unparseable(file_list)

    if file_list.count {|name, mtime|
         file_list[name] = @last_modified[name] unless mtime
         mtime
       } > 0
      @last_modified.replace file_list
      file_list.keys.sort
    else
      []
    end
  end

  ##
  # Turns RDoc from stdin into HTML

  def handle_pipe
    @html = RDoc::Markup::ToHtml.new @options

    parser = RDoc::Text::MARKUP_FORMAT[@options.markup]

    document = parser.parse $stdin.read

    out = @html.convert document

    $stdout.write out
  end

  ##
  # Installs a siginfo handler that prints the current filename.

  def install_siginfo_handler
    return unless Signal.list.include? 'INFO'

    @old_siginfo = trap 'INFO' do
      puts @current if @current
    end
  end

  ##
  # Create an output dir if it doesn't exist. If it does exist, but doesn't
  # contain the flag file <tt>created.rid</tt> then we refuse to use it, as
  # we may clobber some manually generated documentation

  def setup_output_dir(dir, force)
    flag_file = output_flag_file dir

    last = {}

    if @options.dry_run then
      # do nothing
    elsif File.exist? dir then
      error "#{dir} exists and is not a directory" unless File.directory? dir

      begin
        File.open flag_file do |io|
          unless force then
            Time.parse io.gets

            io.each do |line|
              file, time = line.split "\t", 2
              time = Time.parse(time) rescue next
              last[file] = time
            end
          end
        end
      rescue SystemCallError, TypeError
        error <<-ERROR

Directory #{dir} already exists, but it looks like it isn't an RDoc directory.

Because RDoc doesn't want to risk destroying any of your existing files,
you'll need to specify a different output directory name (using the --op <dir>
option)

        ERROR
      end unless @options.force_output
    else
      FileUtils.mkdir_p dir
      FileUtils.touch flag_file
    end

    last
  end

  ##
  # Sets the current documentation tree to +store+ and sets the store's rdoc
  # driver to this instance.

  def store= store
    @store = store
    @store.rdoc = self
  end

  ##
  # Update the flag file in an output directory.

  def update_output_dir(op_dir, time, last = {})
    return if @options.dry_run or not @options.update_output_dir
    unless ENV['SOURCE_DATE_EPOCH'].nil?
      time = Time.at(ENV['SOURCE_DATE_EPOCH'].to_i).gmtime
    end

    File.open output_flag_file(op_dir), "w" do |f|
      f.puts time.rfc2822
      last.each do |n, t|
        f.puts "#{n}\t#{t.rfc2822}"
      end
    end
  end

  ##
  # Return the path name of the flag file in an output directory.

  def output_flag_file(op_dir)
    File.join op_dir, "created.rid"
  end

  ##
  # The .document file contains a list of file and directory name patterns,
  # representing candidates for documentation. It may also contain comments
  # (starting with '#')

  def parse_dot_doc_file in_dir, filename
    # read and strip comments
    patterns = File.read(filename).gsub(/#.*/, '')

    result = {}

    patterns.split(' ').each do |patt|
      candidates = Dir.glob(File.join(in_dir, patt))
      result.update normalized_file_list(candidates, false, @options.exclude)
    end

    result
  end

  ##
  # Given a list of files and directories, create a list of all the Ruby
  # files they contain.
  #
  # If +force_doc+ is true we always add the given files, if false, only
  # add files that we guarantee we can parse.  It is true when looking at
  # files given on the command line, false when recursing through
  # subdirectories.
  #
  # The effect of this is that if you want a file with a non-standard
  # extension parsed, you must name it explicitly.

  def normalized_file_list(relative_files, force_doc = false,
                           exclude_pattern = nil)
    file_list = {}

    relative_files.each do |rel_file_name|
      rel_file_name = rel_file_name.sub(/^\.\//, '')
      next if rel_file_name.end_with? 'created.rid'
      next if exclude_pattern && exclude_pattern =~ rel_file_name
      stat = File.stat rel_file_name rescue next

      case type = stat.ftype
      when "file" then
        mtime = (stat.mtime unless (last_modified = @last_modified[rel_file_name] and
                                    stat.mtime.to_i <= last_modified.to_i))

        if force_doc or RDoc::Parser.can_parse(rel_file_name) then
          file_list[rel_file_name] = mtime
        end
      when "directory" then
        next if UNCONDITIONALLY_SKIPPED_DIRECTORIES.include?(rel_file_name)

        basename = File.basename(rel_file_name)
        next if options.skip_tests && TEST_SUITE_DIRECTORY_NAMES.include?(basename)

        created_rid = File.join rel_file_name, "created.rid"
        next if File.file? created_rid

        dot_doc = File.join rel_file_name, RDoc::DOT_DOC_FILENAME

        if File.file? dot_doc then
          file_list.update(parse_dot_doc_file(rel_file_name, dot_doc))
        else
          file_list.update(list_files_in_directory(rel_file_name))
        end
      else
        warn "rdoc can't parse the #{type} #{rel_file_name}"
      end
    end

    file_list
  end

  ##
  # Return a list of the files to be processed in a directory. We know that
  # this directory doesn't have a .document file, so we're looking for real
  # files. However we may well contain subdirectories which must be tested
  # for .document files.

  def list_files_in_directory dir
    files = Dir.glob File.join(dir, "*")

    normalized_file_list files, false, @options.exclude
  end

  ##
  # Parses +filename+ and returns an RDoc::TopLevel

  def parse_file filename
    encoding = @options.encoding
    filename = filename.encode encoding

    @stats.add_file filename

    return if RDoc::Parser.binary? filename

    content = RDoc::Encoding.read_file filename, encoding

    return unless content

    filename_path = Pathname(filename).expand_path
    begin
      relative_path = filename_path.relative_path_from @options.root
    rescue ArgumentError
      relative_path = filename_path
    end

    if @options.page_dir and
       relative_path.to_s.start_with? @options.page_dir.to_s then
      relative_path =
        relative_path.relative_path_from @options.page_dir
    end

    top_level = @store.add_file filename, relative_name: relative_path.to_s

    parser = RDoc::Parser.for top_level, filename, content, @options, @stats

    return unless parser

    parser.scan

    # restart documentation for the classes & modules found
    top_level.classes_or_modules.each do |cm|
      cm.done_documenting = false
    end

    top_level

  rescue Errno::EACCES => e
    $stderr.puts <<-EOF
Unable to read #{filename}, #{e.message}

Please check the permissions for this file.  Perhaps you do not have access to
it or perhaps the original author's permissions are to restrictive.  If the
this is not your library please report a bug to the author.
    EOF
  rescue => e
    $stderr.puts <<-EOF
Before reporting this, could you check that the file you're documenting
has proper syntax:

  #{Gem.ruby} -c #{filename}

RDoc is not a full Ruby parser and will fail when fed invalid ruby programs.

The internal error was:

\t(#{e.class}) #{e.message}

    EOF

    $stderr.puts e.backtrace.join("\n\t") if $DEBUG_RDOC

    raise e
    nil
  end

  ##
  # Parse each file on the command line, recursively entering directories.

  def parse_files files
    file_list = gather_files files
    @stats = RDoc::Stats.new @store, file_list.length, @options.verbosity

    return [] if file_list.empty?

    original_options = @options.dup
    @stats.begin_adding

    file_info = file_list.map do |filename|
      @current = filename
      parse_file filename
    end.compact

    @stats.done_adding
    @options = original_options

    file_info
  end

  ##
  # Removes file extensions known to be unparseable from +files+ and TAGS
  # files for emacs and vim.

  def remove_unparseable files
    files.reject do |file, *|
      file =~ /\.(?:class|eps|erb|scpt\.txt|svg|ttf|yml)$/i or
        (file =~ /tags$/i and
         /\A(\f\n[^,]+,\d+$|!_TAG_)/.match?(File.binread(file, 100)))
    end
  end

  ##
  # Generates documentation or a coverage report depending upon the settings
  # in +options+.
  #
  # +options+ can be either an RDoc::Options instance or an array of strings
  # equivalent to the strings that would be passed on the command line like
  # <tt>%w[-q -o doc -t My\ Doc\ Title]</tt>.  #document will automatically
  # call RDoc::Options#finish if an options instance was given.
  #
  # For a list of options, see either RDoc::Options or <tt>rdoc --help</tt>.
  #
  # By default, output will be stored in a directory called "doc" below the
  # current directory, so make sure you're somewhere writable before invoking.

  def document options
    self.store = RDoc::Store.new

    if RDoc::Options === options then
      @options = options
    else
      @options = RDoc::Options.load_options
      @options.parse options
    end
    @options.finish

    if @options.pipe then
      handle_pipe
      exit
    end

    unless @options.coverage_report then
      @last_modified = setup_output_dir @options.op_dir, @options.force_update
    end

    @store.encoding = @options.encoding
    @store.dry_run  = @options.dry_run
    @store.main     = @options.main_page
    @store.title    = @options.title
    @store.path     = @options.op_dir

    @start_time = Time.now

    @store.load_cache

    file_info = parse_files @options.files

    @options.default_title = "RDoc Documentation"

    @store.complete @options.visibility

    @stats.coverage_level = @options.coverage_report

    if @options.coverage_report then
      puts

      puts @stats.report.accept RDoc::Markup::ToRdoc.new
    elsif file_info.empty? then
      $stderr.puts "\nNo newer files." unless @options.quiet
    else
      gen_klass = @options.generator

      @generator = gen_klass.new @store, @options

      generate
    end

    if @stats and (@options.coverage_report or not @options.quiet) then
      puts
      puts @stats.summary.accept RDoc::Markup::ToRdoc.new
    end

    exit @stats.fully_documented? if @options.coverage_report
  end

  ##
  # Generates documentation for +file_info+ (from #parse_files) into the
  # output dir using the generator selected
  # by the RDoc options

  def generate
    if @options.dry_run then
      # do nothing
      @generator.generate
    else
      Dir.chdir @options.op_dir do
        unless @options.quiet then
          $stderr.puts "\nGenerating #{@generator.class.name.sub(/^.*::/, '')} format into #{Dir.pwd}..."
        end

        @generator.generate
        update_output_dir '.', @start_time, @last_modified
      end
    end
  end

  ##
  # Removes a siginfo handler and replaces the previous

  def remove_siginfo_handler
    return unless Signal.list.key? 'INFO'

    handler = @old_siginfo || 'DEFAULT'

    trap 'INFO', handler
  end

end

begin
  require 'rubygems'

  rdoc_extensions = Gem.find_files 'rdoc/discover'

  rdoc_extensions.each do |extension|
    begin
      load extension
    rescue => e
      warn "error loading #{extension.inspect}: #{e.message} (#{e.class})"
      warn "\t#{e.backtrace.join "\n\t"}" if $DEBUG
    end
  end
rescue LoadError
end

# require built-in generators after discovery in case they've been replaced
require_relative 'generator/darkfish'
require_relative 'generator/ri'
require_relative 'generator/pot'
