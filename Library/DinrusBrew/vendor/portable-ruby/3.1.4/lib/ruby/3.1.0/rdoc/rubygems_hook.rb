# frozen_string_literal: true
require 'rubygems/user_interaction'
require 'fileutils'
require 'rdoc'

##
# Gem::RDoc provides methods to generate RDoc and ri data for installed gems
# upon gem installation.
#
# This file is automatically required by RubyGems 1.9 and newer.

class RDoc::RubygemsHook

  include Gem::UserInteraction
  extend  Gem::UserInteraction

  @rdoc_version = nil
  @specs = []

  ##
  # Force installation of documentation?

  attr_accessor :force

  ##
  # Generate rdoc?

  attr_accessor :generate_rdoc

  ##
  # Generate ri data?

  attr_accessor :generate_ri

  class << self

    ##
    # Loaded version of RDoc.  Set by ::load_rdoc

    attr_reader :rdoc_version

  end

  ##
  # Post installs hook that generates documentation for each specification in
  # +specs+

  def self.generation_hook installer, specs
    start = Time.now
    types = installer.document

    generate_rdoc = types.include? 'rdoc'
    generate_ri   = types.include? 'ri'

    specs.each do |spec|
      new(spec, generate_rdoc, generate_ri).generate
    end

    return unless generate_rdoc or generate_ri

    duration = (Time.now - start).to_i
    names    = specs.map(&:name).join ', '

    say "Done installing documentation for #{names} after #{duration} seconds"
  end

  ##
  # Loads the RDoc generator

  def self.load_rdoc
    return if @rdoc_version

    require_relative 'rdoc'

    @rdoc_version = Gem::Version.new ::RDoc::VERSION
  end

  ##
  # Creates a new documentation generator for +spec+.  RDoc and ri data
  # generation can be enabled or disabled through +generate_rdoc+ and
  # +generate_ri+ respectively.
  #
  # Only +generate_ri+ is enabled by default.

  def initialize spec, generate_rdoc = false, generate_ri = true
    @doc_dir   = spec.doc_dir
    @force     = false
    @rdoc      = nil
    @spec      = spec

    @generate_rdoc = generate_rdoc
    @generate_ri   = generate_ri

    @rdoc_dir = spec.doc_dir 'rdoc'
    @ri_dir   = spec.doc_dir 'ri'
  end

  ##
  # Removes legacy rdoc arguments from +args+
  #--
  # TODO move to RDoc::Options

  def delete_legacy_args args
    args.delete '--inline-source'
    args.delete '--promiscuous'
    args.delete '-p'
    args.delete '--one-file'
  end

  ##
  # Generates documentation using the named +generator+ ("darkfish" or "ri")
  # and following the given +options+.
  #
  # Documentation will be generated into +destination+

  def document generator, options, destination
    generator_name = generator

    options = options.dup
    options.exclude ||= [] # TODO maybe move to RDoc::Options#finish
    options.setup_generator generator
    options.op_dir = destination
    Dir.chdir @spec.full_gem_path do
      options.finish
    end

    generator = options.generator.new @rdoc.store, options

    @rdoc.options = options
    @rdoc.generator = generator

    say "Installing #{generator_name} documentation for #{@spec.full_name}"

    FileUtils.mkdir_p options.op_dir

    Dir.chdir options.op_dir do
      begin
        @rdoc.class.current = @rdoc
        @rdoc.generator.generate
      ensure
        @rdoc.class.current = nil
      end
    end
  end

  ##
  # Generates RDoc and ri data

  def generate
    return if @spec.default_gem?
    return unless @generate_ri or @generate_rdoc

    setup

    options = nil

    args = @spec.rdoc_options
    args.concat @spec.source_paths
    args.concat @spec.extra_rdoc_files

    case config_args = Gem.configuration[:rdoc]
    when String then
      args = args.concat config_args.split(' ')
    when Array then
      args = args.concat config_args
    end

    delete_legacy_args args

    Dir.chdir @spec.full_gem_path do
      options = ::RDoc::Options.new
      options.default_title = "#{@spec.full_name} Documentation"
      options.parse args
    end

    options.quiet = !Gem.configuration.really_verbose

    @rdoc = new_rdoc
    @rdoc.options = options

    store = RDoc::Store.new
    store.encoding = options.encoding
    store.dry_run  = options.dry_run
    store.main     = options.main_page
    store.title    = options.title

    @rdoc.store = store

    say "Parsing documentation for #{@spec.full_name}"

    Dir.chdir @spec.full_gem_path do
      @rdoc.parse_files options.files
    end

    document 'ri',       options, @ri_dir if
      @generate_ri   and (@force or not File.exist? @ri_dir)

    document 'darkfish', options, @rdoc_dir if
      @generate_rdoc and (@force or not File.exist? @rdoc_dir)
  end

  ##
  # #new_rdoc creates a new RDoc instance.  This method is provided only to
  # make testing easier.

  def new_rdoc # :nodoc:
    ::RDoc::RDoc.new
  end

  ##
  # Is rdoc documentation installed?

  def rdoc_installed?
    File.exist? @rdoc_dir
  end

  ##
  # Removes generated RDoc and ri data

  def remove
    base_dir = @spec.base_dir

    raise Gem::FilePermissionError, base_dir unless File.writable? base_dir

    FileUtils.rm_rf @rdoc_dir
    FileUtils.rm_rf @ri_dir
  end

  ##
  # Is ri data installed?

  def ri_installed?
    File.exist? @ri_dir
  end

  ##
  # Prepares the spec for documentation generation

  def setup
    self.class.load_rdoc

    raise Gem::FilePermissionError, @doc_dir if
      File.exist?(@doc_dir) and not File.writable?(@doc_dir)

    FileUtils.mkdir_p @doc_dir unless File.exist? @doc_dir
  end

end
