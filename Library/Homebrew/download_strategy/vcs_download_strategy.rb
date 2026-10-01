# typed: strict
# frozen_string_literal: true

require "sandbox"

# @abstract Abstract superclass for all download strategies downloading from a version control system.
class VCSDownloadStrategy < AbstractDownloadStrategy
  abstract!

  sig { override.returns(Pathname) }
  attr_reader :cached_location

  REF_TYPES = [:tag, :branch, :revisions, :revision].freeze

  sig { params(url: String, name: String, version: T.nilable(T.any(String, Version)), meta: T.untyped).void }
  def initialize(url, name, version, **meta)
    super
    extracted_ref = extract_ref(meta)
    @ref_type = T.let(extracted_ref.fetch(0), T.nilable(Symbol))
    @ref = T.let(extracted_ref.fetch(1), T.untyped)
    @revision = T.let(meta[:revision], T.nilable(String))
    @cached_location = T.let(@cache/Utils.safe_filename("#{name}--#{cache_tag}"), Pathname)
    @fetching = T.let(false, T::Boolean)
  end

  # Download and cache the repository at {#cached_location}.
  #
  # @api public
  sig { override.params(timeout: T.nilable(T.any(Float, Integer))).void }
  def fetch(timeout: nil)
    @fetching = true
    end_time = Time.now + timeout if timeout

    ohai "Cloning #{url}"

    if cached_location.exist? && repo_valid?
      puts "Updating #{cached_location}"
      update(timeout: end_time)
    elsif cached_location.exist?
      puts "Removing invalid repository from cache"
      clear_cache
      clone_repo(timeout: end_time)
    else
      clone_repo(timeout: end_time)
    end

    v = version
    v.update_commit(last_commit) if v.is_a?(Version) && head?

    return if @ref_type != :tag || @revision.blank? || current_revision.blank? || current_revision == @revision

    raise <<~EOS
      #{@ref} tag should be #{@revision}
      but is actually #{current_revision}
    EOS
  ensure
    @fetching = false
  end

  sig { returns(String) }
  def fetch_last_commit
    fetch
    last_commit
  end

  sig { overridable.params(commit: T.nilable(String)).returns(T::Boolean) }
  def commit_outdated?(commit)
    @last_commit ||= T.let(fetch_last_commit, T.nilable(String))
    commit != @last_commit
  end

  sig { returns(T::Boolean) }
  def head?
    v = version
    v.is_a?(Version) ? v.head? : false
  end

  sig { returns(T::Boolean) }
  def fetching? = @fetching

  sig { override.returns(T.nilable(Sandbox)) }
  def command_sandbox
    return unless Sandbox.isolate_operation?

    # Reject symlinks before the sandbox resolves its writable paths.
    if cached_location.symlink? || sandbox_write_path.symlink?
      raise "VCS download path is a symlink: #{cached_location}"
    end

    Sandbox.for_operation(write_paths: [sandbox_write_path], network_access: fetching?,
                          home_read_exception: (fetch_home_read_exception if fetching?)).tap do |sandbox|
      allow_fetch_credentials(sandbox) if fetching?
    end
  end

  sig { overridable.returns(Pathname) }
  def sandbox_write_path = cached_location

  # Return the most recent modified timestamp.
  #
  # @api public
  sig { overridable.returns(String) }
  def last_commit
    source_modified_time.to_i.to_s
  end

  private

  sig { overridable.returns(T.nilable(Symbol)) }
  def fetch_home_read_exception = nil

  sig { overridable.params(sandbox: Sandbox).void }
  def allow_fetch_credentials(sandbox); end

  sig { abstract.returns(String) }
  def cache_tag; end

  sig { abstract.returns(T::Boolean) }
  def repo_valid?; end

  sig { abstract.params(timeout: T.nilable(Time)).void }
  def clone_repo(timeout: nil); end

  sig { abstract.params(timeout: T.nilable(Time)).void }
  def update(timeout: nil); end

  sig { overridable.returns(T.nilable(String)) }
  def current_revision; end

  sig { params(specs: T::Hash[T.nilable(Symbol), T.untyped]).returns([T.nilable(Symbol), T.untyped]) }
  def extract_ref(specs)
    key = REF_TYPES.find { |type| specs.key?(type) }
    [key, specs[key]]
  end
end
