# typed: strict
# frozen_string_literal: true

# A specialized {Tap} class for the core formulae.
class CoreTap < AbstractCoreTap
  class << self
    Cache = type_member { { fixed: T::Hash[T.any(String, Symbol), T.untyped] } }
    Elem = type_member(:out) { { fixed: Tap } }
  end

  sig { void }
  def initialize
    super "Homebrew", "core"
  end

  sig { override.void }
  def ensure_installed!
    return if ENV["HOMEBREW_TESTS"]

    super
  end

  sig { override.returns(T.nilable(String)) }
  def remote
    return super if Homebrew::EnvConfig.no_install_from_api?

    Homebrew::EnvConfig.core_git_remote
  end

  # The configured `HOMEBREW_CORE_GIT_REMOTE` is the official remote for this tap.
  sig { override.params(remote: T.nilable(String)).returns(T::Boolean) }
  def canonical_remote?(remote = self.remote)
    remote.blank? || self.class.same_remote?(remote, Homebrew::EnvConfig.core_git_remote)
  end

  # CoreTap never allows shallow clones (on request from GitHub).
  sig {
    override.params(quiet: T::Boolean, clone_target: T.nilable(T.any(Pathname, String)),
                    custom_remote: T::Boolean, verify: T::Boolean, force: T::Boolean).void
  }
  def install(quiet: false, clone_target: nil,
              custom_remote: false, verify: false, force: false)
    remote = Homebrew::EnvConfig.core_git_remote # set by HOMEBREW_CORE_GIT_REMOTE
    requested_remote = clone_target || remote

    # The remote will changed again on `brew update` since remotes for homebrew/core are mismatched
    raise TapCoreRemoteMismatchError.new(name, remote, requested_remote) if requested_remote != remote

    if remote != default_remote
      $stderr.puts "HOMEBREW_CORE_GIT_REMOTE set: using #{remote} as the Homebrew/homebrew-core Git remote."
    end

    super(quiet:, clone_target: remote, custom_remote:, force:)
  end

  sig { override.params(manual: T::Boolean).void }
  def uninstall(manual: false)
    raise "Tap#uninstall is not available for CoreTap" if Homebrew::EnvConfig.no_install_from_api?

    super
  end

  sig { override.returns(T::Boolean) }
  def core_tap?
    true
  end

  sig { returns(T::Boolean) }
  def linuxbrew_core?
    remote_repository.to_s.end_with?("/linuxbrew-core") || remote_repository == "Linuxbrew/homebrew-core"
  end

  sig { override.returns(Pathname) }
  def formula_dir
    @formula_dir ||= T.let(begin
      ensure_installed!
      super
    end, T.nilable(Pathname))
  end

  sig { params(name: String).returns(String) }
  def new_formula_subdirectory(name)
    if name.start_with?("lib")
      "lib"
    else
      name[0].to_s
    end
  end

  sig { override.params(name: String).returns(Pathname) }
  def new_formula_path(name)
    formula_subdir = new_formula_subdirectory(name)

    return super unless (formula_dir/formula_subdir).directory?

    formula_dir/formula_subdir/"#{name.downcase}.rb"
  end

  sig { override.returns(Pathname) }
  def alias_dir
    @alias_dir ||= T.let(begin
      ensure_installed!
      super
    end, T.nilable(Pathname))
  end

  sig { override.returns(T::Hash[String, String]) }
  def formula_renames
    @formula_renames ||= T.let(
      if Homebrew::EnvConfig.no_install_from_api?
        ensure_installed!
        super
      else
        Homebrew::API.formula_renames
      end,
      T.nilable(T::Hash[String, String]),
    )
  end

  sig { override.returns(T::Hash[String, T.untyped]) }
  def tap_migrations
    @tap_migrations ||= T.let(
      if Homebrew::EnvConfig.no_install_from_api?
        ensure_installed!
        super
      else
        Homebrew::API.formula_tap_migrations
      end,
      T.nilable(T::Hash[String, T.untyped]),
    )
  end

  sig { override.returns(T::Array[String]) }
  def autobump
    @autobump ||= T.let(begin
      ensure_installed!
      super
    end, T.nilable(T::Array[String]))
  end

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def audit_exceptions
    @audit_exceptions ||= T.let(begin
      ensure_installed!
      super
    end, T.nilable(T::Hash[Symbol, T.untyped]))
  end

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def style_exceptions
    @style_exceptions ||= T.let(begin
      ensure_installed!
      super
    end, T.nilable(T::Hash[Symbol, T.untyped]))
  end

  sig { override.returns(T::Array[T::Array[String]]) }
  def synced_versions_formulae
    @synced_versions_formulae ||= T.let(begin
      ensure_installed!
      super
    end, T.nilable(T::Array[T::Array[String]]))
  end

  sig { override.params(file: Pathname).returns(String) }
  def alias_file_to_name(file)
    file.basename.to_s
  end

  sig { override.returns(T::Hash[String, String]) }
  def alias_table
    @alias_table ||= T.let(
      if Homebrew::EnvConfig.no_install_from_api?
        super
      else
        Homebrew::API.formula_aliases
      end,
      T.nilable(T::Hash[String, String]),
    )
  end

  sig { override.returns(T::Array[Pathname]) }
  def formula_files
    return super if Homebrew::EnvConfig.no_install_from_api?

    formula_files_by_name.values
  end

  sig { override.returns(T::Array[String]) }
  def formula_names
    return super if Homebrew::EnvConfig.no_install_from_api?

    Homebrew::API.formula_names
  end

  sig { override.returns(T::Hash[String, Pathname]) }
  def formula_files_by_name
    return super if Homebrew::EnvConfig.no_install_from_api?

    @formula_files_by_name ||= T.let(
      begin
        formula_directory_path = formula_dir.to_s
        Homebrew::API.formula_names.each_with_object({}) do |name, hash|
          # If there's more than one item with the same path: use the longer one to prioritise more specific results.
          existing_path = hash[name]
          # Pathname equivalent is slow in a tight loop
          new_path = File.join(formula_directory_path, new_formula_subdirectory(name), "#{name.downcase}.rb")
          hash[name] = Pathname(new_path) if existing_path.nil? || existing_path.to_s.length < new_path.length
        end
      end,
      T.nilable(T::Hash[String, Pathname]),
    )
  end
end
