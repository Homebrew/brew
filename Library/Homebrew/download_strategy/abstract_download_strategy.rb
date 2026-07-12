# typed: strict
# frozen_string_literal: true

# @abstract Abstract superclass for all download strategies.
class AbstractDownloadStrategy
  extend T::Helpers
  include FileUtils
  include Context
  include SystemCommand::Mixin
  include Utils::Output::Mixin

  abstract!

  # The download URL.
  #
  # @api public
  sig { returns(String) }
  attr_reader :url

  sig { returns(Pathname) }
  attr_reader :cache

  sig { returns(T::Hash[Symbol, T.untyped]) }
  attr_reader :meta

  sig { returns(String) }
  attr_reader :name

  sig { returns(T.nilable(T.any(String, Version))) }
  attr_reader :version

  private :meta, :name, :version

  sig { params(url: String, name: String, version: T.nilable(T.any(String, Version)), meta: T.untyped).void }
  def initialize(url, name, version, **meta)
    @cached_location = T.let(nil, T.nilable(Pathname))
    @ref_type = T.let(nil, T.nilable(Symbol))
    @ref = T.let(nil, T.untyped)
    @url = url
    @name = name
    @version = version
    @cache = T.let(meta.fetch(:cache, HOMEBREW_CACHE), Pathname)
    @meta = meta
    @quiet = T.let(false, T.nilable(T::Boolean))
  end

  # Download and cache the resource at {#cached_location}.
  #
  # @api public
  sig { overridable.params(timeout: T.nilable(T.any(Float, Integer))).void }
  def fetch(timeout: nil); end

  # Total bytes downloaded if available.
  sig { overridable.returns(T.nilable(Integer)) }
  def fetched_size; end

  # Total download size if available.
  sig { overridable.returns(T.nilable(Integer)) }
  def total_size; end

  # Location of the cached download.
  #
  # @api public
  sig { abstract.returns(Pathname) }
  def cached_location; end

  # Disable any output during downloading.
  #
  # @api public
  sig { void }
  def quiet!
    @quiet = T.let(true, T.nilable(T::Boolean))
  end

  sig { returns(T::Boolean) }
  def quiet?
    Context.current.quiet? || @quiet || false
  end

  sig { params(downloader: AbstractDownloadStrategy).returns(T::Boolean) }
  def self.expand_deferred_environment_for?(downloader)
    HOMEBREW_CONTROLLED_STRATEGIES.include?(downloader.class)
  end

  # Unpack {#cached_location} into the current working directory.
  #
  # Additionally, if a block is given, the working directory was previously empty
  # and a single directory is extracted from the archive, the block will be called
  # with the working directory changed to that directory. Otherwise this method
  # will return, or the block will be called, without changing the current working
  # directory.
  #
  # @api public
  sig { overridable.params(block: T.nilable(T.proc.void)).void }
  def stage(&block)
    UnpackStrategy.detect(cached_location,
                          prioritize_extension: true,
                          ref_type: @ref_type, ref: @ref)
                  .extract_nestedly(basename:,
                                    prioritize_extension: true,
                                    verbose:              verbose? && !quiet?)
    chdir(&block) if block
  end

  sig { params(block: T.proc.void).void }
  def chdir(&block)
    entries = Dir["*"]
    raise "Empty archive" if entries.empty?

    if entries.length != 1
      yield
      return
    end

    if File.directory? entries.fetch(0)
      # chdir yields the directory name as an argument, which is unused in our case
      # However, sorbet requires us to pass a block with matching arity, so we use T.unsafe here
      Dir.chdir(entries.fetch(0), &T.unsafe(block))
    else
      yield
    end
  end
  private :chdir

  # Returns the most recent modified time for all files in the current working directory after stage.
  #
  # @api public
  sig { overridable.returns(Time) }
  def source_modified_time
    Pathname.pwd.to_enum(:find).select(&:file?).map(&:mtime).max
  end

  # Return the checked out source revision for version control downloads.
  #
  # @api public
  sig { overridable.returns(T.nilable(String)) }
  def source_revision; end

  # Remove {#cached_location} and any other files associated with the resource
  # from the cache.
  #
  # @api public
  sig { overridable.void }
  def clear_cache
    rm_rf(cached_location)
  end

  sig { returns(Pathname) }
  def basename
    cached_location.basename
  end

  sig { override.params(title: T.any(String, Exception), sput: T.anything).void }
  def ohai(title, *sput)
    super unless quiet?
  end

  private

  sig { params(args: T.anything).void }
  def puts(*args)
    super unless quiet?
  end

  sig { params(args: String, options: T.untyped).returns(SystemCommand::Result) }
  def silent_command(*args, **options)
    system_command(*args, print_stderr: false, env:, **options)
  end

  sig { params(args: String, options: T.untyped).returns(SystemCommand::Result) }
  def command!(*args, **options)
    system_command!(
      *args,
      env: env.merge(options.fetch(:env, {})),
      **command_output_options,
      **options,
    )
  end

  sig { returns(T::Hash[Symbol, T::Boolean]) }
  def command_output_options
    {
      print_stdout: !quiet?,
      print_stderr: !quiet?,
      verbose:      verbose? && !quiet?,
    }
  end

  sig { overridable.returns(T::Hash[String, String]) }
  def env
    {}
  end
end
