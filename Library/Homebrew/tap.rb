# typed: strict
# frozen_string_literal: true

require "api"
require "commands"
require "settings"
require "utils/output"

# A {Tap} is used to encapsulate Homebrew formulae, casks and custom commands.
# Usually, it's synced with a remote Git repository. And it's likely
# a GitHub repository with the name of `user/homebrew-repository`. In such
# cases, `user/repository` will be used as the {#name} of this {Tap}, where
# {#user} represents the GitHub username and {#repository} represents the
# repository name without the leading `homebrew-`.
class Tap
  extend Cachable
  extend Utils::Output::Mixin
  include Utils::Output::Mixin

  HOMEBREW_TAP_CASK_RENAMES_FILE = "cask_renames.json"
  private_constant :HOMEBREW_TAP_CASK_RENAMES_FILE
  HOMEBREW_TAP_FORMULA_RENAMES_FILE = "formula_renames.json"
  private_constant :HOMEBREW_TAP_FORMULA_RENAMES_FILE
  HOMEBREW_TAP_MIGRATIONS_FILE = "tap_migrations.json"
  private_constant :HOMEBREW_TAP_MIGRATIONS_FILE
  HOMEBREW_TAP_AUTOBUMP_FILE = ".github/autobump.txt"
  private_constant :HOMEBREW_TAP_AUTOBUMP_FILE
  HOMEBREW_TAP_SYNCED_VERSIONS_FORMULAE_FILE = "synced_versions_formulae.json"
  private_constant :HOMEBREW_TAP_SYNCED_VERSIONS_FORMULAE_FILE
  HOMEBREW_TAP_DISABLED_NEW_USR_LOCAL_RELOCATION_FORMULAE_FILE = "disabled_new_usr_local_relocation_formulae.json"
  private_constant :HOMEBREW_TAP_DISABLED_NEW_USR_LOCAL_RELOCATION_FORMULAE_FILE
  HOMEBREW_TAP_AUDIT_EXCEPTIONS_DIR = "audit_exceptions"
  private_constant :HOMEBREW_TAP_AUDIT_EXCEPTIONS_DIR
  HOMEBREW_TAP_STYLE_EXCEPTIONS_DIR = "style_exceptions"
  private_constant :HOMEBREW_TAP_STYLE_EXCEPTIONS_DIR

  HOMEBREW_TAP_JSON_FILES = T.let(%W[
    #{HOMEBREW_TAP_FORMULA_RENAMES_FILE}
    #{HOMEBREW_TAP_CASK_RENAMES_FILE}
    #{HOMEBREW_TAP_MIGRATIONS_FILE}
    #{HOMEBREW_TAP_SYNCED_VERSIONS_FORMULAE_FILE}
    #{HOMEBREW_TAP_DISABLED_NEW_USR_LOCAL_RELOCATION_FORMULAE_FILE}
    #{HOMEBREW_TAP_AUDIT_EXCEPTIONS_DIR}/*.json
    #{HOMEBREW_TAP_STYLE_EXCEPTIONS_DIR}/*.json
  ].freeze, T::Array[String])

  class InvalidNameError < ArgumentError; end

  # Fetch a {Tap} by name.
  #
  # @api public
  sig { params(user: String, repository: String).returns(Tap) }
  def self.fetch(user, repository = T.unsafe(nil))
    user, repository = user.split("/", 2) if repository.nil?

    if [user, repository].any? { |part| part.nil? || part.include?("/") }
      raise InvalidNameError, "Invalid tap name: '#{[*user, *repository].join("/")}'"
    end

    user = T.must(user)

    # We special case homebrew and linuxbrew so that users don't have to shift in a terminal.
    user = user.capitalize if ["homebrew", "linuxbrew"].include?(user)
    repository = repository.sub(HOMEBREW_OFFICIAL_REPO_PREFIXES_REGEX, "")

    return CoreTap.instance if ["Homebrew", "Linuxbrew"].include?(user) && ["core", "homebrew"].include?(repository)
    return CoreCaskTap.instance if user == "Homebrew" && repository == "cask"

    cache_key = "#{user}/#{repository}".downcase
    cache.fetch(cache_key) { |key| cache[key] = new(user, repository) }
  end

  # Get a {Tap} from its path or a path inside of it.
  #
  # @api public
  sig { params(path: T.any(Pathname, String)).returns(T.nilable(Tap)) }
  def self.from_path(path)
    match = File.expand_path(path).match(HOMEBREW_TAP_PATH_REGEX)

    return unless match
    return unless (user = match[:user])
    return unless (repository = match[:repository])

    fetch(user, repository)
  end

  sig { params(name: String).returns(T.nilable([Tap, String])) }
  def self.with_formula_name(name)
    return unless (match = name.match(HOMEBREW_TAP_FORMULA_REGEX))

    user = T.must(match[:user])
    repository = T.must(match[:repository])
    name = T.must(match[:name])

    # Relative paths are not taps.
    return if [user, repository].intersect?([".", ".."])

    tap = fetch(user, repository)
    [tap, name.downcase]
  end

  sig { params(token: String).returns(T.nilable([Tap, String])) }
  def self.with_cask_token(token)
    return unless (match = token.match(HOMEBREW_TAP_CASK_REGEX))

    user = T.must(match[:user])
    repository = T.must(match[:repository])
    token = T.must(match[:token])

    # Relative paths are not taps.
    return if [user, repository].intersect?([".", ".."])

    tap = fetch(user, repository)
    [tap, token.downcase]
  end

  sig { returns(T::Set[Tap]) }
  def self.allowed_taps
    cache_key = :"allowed_taps_#{Homebrew::EnvConfig.allowed_taps.to_s.tr(" ", "_")}"
    cache[cache_key] ||= begin
      allowed_tap_list = Homebrew::EnvConfig.allowed_taps.to_s.split

      Set.new(allowed_tap_list.filter_map do |tap|
        Tap.fetch(tap)
      rescue Tap::InvalidNameError
        opoo "Invalid tap name in `$HOMEBREW_ALLOWED_TAPS`: #{tap}"
        nil
      end).freeze
    end
  end

  sig { returns(T::Set[Tap]) }
  def self.forbidden_taps
    cache_key = :"forbidden_taps_#{Homebrew::EnvConfig.forbidden_taps.to_s.tr(" ", "_")}"
    cache[cache_key] ||= begin
      forbidden_tap_list = Homebrew::EnvConfig.forbidden_taps.to_s.split

      Set.new(forbidden_tap_list.filter_map do |tap|
        Tap.fetch(tap)
      rescue Tap::InvalidNameError
        opoo "Invalid tap name in `$HOMEBREW_FORBIDDEN_TAPS`: #{tap}"
        nil
      end).freeze
    end
  end

  class << self
    extend T::Generic

    Elem = type_member(:out) { { fixed: Tap } }

    # @api public
    include Enumerable
  end

  # The user name of this {Tap}. Usually, it's the GitHub username of
  # this {Tap}'s remote repository.
  #
  # @api public
  sig { returns(String) }
  attr_reader :user

  # The repository name of this {Tap} without the leading `homebrew-`.
  #
  # @api public
  sig { returns(String) }
  attr_reader :repository

  # The repository name of this {Tap} including the leading `homebrew-`.
  #
  # @api public
  sig { returns(String) }
  attr_reader :full_repository

  # The name of this {Tap}. It combines {#user} and {#repository} with a slash.
  # {#name} is always in lowercase.
  # e.g. `user/repository`
  #
  # @api public
  sig { returns(String) }
  attr_reader :name

  # @api public
  sig { returns(String) }
  def to_s = name

  # The full name of this {Tap}, including the `homebrew-` prefix.
  # It combines {#user} and 'homebrew-'-prefixed {#repository} with a slash.
  # e.g. `user/homebrew-repository`
  #
  # @api public
  sig { returns(String) }
  attr_reader :full_name

  # The local path to this {Tap}.
  # e.g. `/usr/local/Library/Taps/user/homebrew-repository`
  #
  # @api public
  sig { returns(Pathname) }
  attr_reader :path

  # The git repository of this {Tap}.
  sig { returns(GitRepository) }
  attr_reader :git_repository

  # Always use `Tap.fetch` instead of `Tap.new`.
  private_class_method :new

  sig { params(user: String, repository: String).void }
  def initialize(user, repository)
    require "git_repository"

    @user = user
    @repository = repository
    @name = T.let("#{@user}/#{@repository}".downcase, String)
    @full_repository = T.let("homebrew-#{@repository}", String)
    @full_name = T.let("#{@user}/#{@full_repository}", String)
    @path = T.let(HOMEBREW_TAP_DIRECTORY/@full_name.downcase, Pathname)
    @git_repository = T.let(GitRepository.new(@path), GitRepository)
  end

  # Clear internal cache.
  sig { void }
  def clear_cache
    @remote = nil
    @repository_var_suffix = nil
    remove_instance_variable(:@private) if instance_variable_defined?(:@private)

    @formula_dir = nil
    @formula_files = nil
    @formula_files_by_name = nil
    @formula_names = nil
    @prefix_to_versioned_formulae_names = nil
    @formula_renames = nil
    @formula_reverse_renames = nil

    @cask_dir = nil
    @cask_files = nil
    @cask_files_by_name = nil
    @cask_tokens = nil
    @cask_renames = nil
    @cask_reverse_renames = nil

    @alias_dir = nil
    @alias_files = nil
    @aliases = nil
    @alias_table = nil
    @alias_reverse_table = nil

    @command_dir = nil
    @command_files = nil

    @tap_migrations = nil
    @reverse_tap_migrations_renames = nil

    @audit_exceptions = nil
    @style_exceptions = nil
    @synced_versions_formulae = nil

    @config = nil
  end

  sig { overridable.void }
  def ensure_installed!
    return if installed?

    install
  end

  # The remote path to this {Tap}.
  # e.g. `https://github.com/user/homebrew-repository`
  #
  # @api public
  sig { overridable.returns(T.nilable(String)) }
  def remote
    return default_remote unless installed?

    @remote ||= T.let(git_repository.origin_url, T.nilable(String))
  end

  # The remote repository name of this {Tap}.
  # e.g. `user/homebrew-repository`
  #
  # @api public
  sig { returns(T.nilable(String)) }
  def remote_repository
    return unless (remote = self.remote)
    return unless (match = remote.match(HOMEBREW_TAP_REPOSITORY_REGEX))

    @remote_repository ||= T.let(T.must(match[:remote_repository]), T.nilable(String))
  end

  # The default remote path to this {Tap}.
  sig { returns(String) }
  def default_remote
    "https://github.com/#{full_name}"
  end

  sig { returns(String) }
  def repository_var_suffix
    @repository_var_suffix ||= T.let(path.to_s
                                         .delete_prefix(HOMEBREW_TAP_DIRECTORY.to_s)
                                         .tr("^A-Za-z0-9", "_")
                                         .upcase, T.nilable(String))
  end

  # Check whether this {Tap} is a Git repository.
  #
  # @api public
  sig { returns(T::Boolean) }
  def git?
    git_repository.git_repository?
  end

  # Git branch for this {Tap}.
  #
  # @api public
  sig { returns(T.nilable(String)) }
  def git_branch
    raise TapUnavailableError, name unless installed?

    git_repository.branch_name
  end

  # Git HEAD for this {Tap}.
  #
  # @api public
  sig { returns(T.nilable(String)) }
  def git_head
    raise TapUnavailableError, name unless installed?

    @git_head ||= T.let(git_repository.head_ref, T.nilable(String))
  end

  # Time since last git commit for this {Tap}.
  #
  # @api public
  sig { returns(T.nilable(String)) }
  def git_last_commit
    raise TapUnavailableError, name unless installed?

    git_repository.last_committed
  end

  # The issues URL of this {Tap}.
  # e.g. `https://github.com/user/homebrew-repository/issues`
  #
  # @api public
  sig { returns(T.nilable(String)) }
  def issues_url
    return if !official? && custom_remote?

    "#{default_remote}/issues"
  end

  # Check whether this {Tap} is an official Homebrew tap.
  #
  # @api public
  sig { returns(T::Boolean) }
  def official?
    user == "Homebrew"
  end

  # Check whether the remote of this {Tap} is a private repository.
  #
  # @api public
  sig { returns(T::Boolean) }
  def private?
    return @private unless @private.nil?

    @private = T.let(
      begin
        if core_tap? || core_cask_tap?
          false
        elsif custom_remote? || (value = GitHub.private_repo?(full_name)).nil?
          true
        else
          value
        end
      rescue GitHub::API::Error
        true
      end,
      T.nilable(T::Boolean),
    )
    T.must(@private)
  end

  # {TapConfig} of this {Tap}.
  sig { returns(TapConfig) }
  def config
    @config ||= T.let(begin
      raise TapUnavailableError, name unless installed?

      TapConfig.new(self)
    end, T.nilable(TapConfig))
  end

  # Check whether this {Tap} is installed.
  #
  # @api public
  sig { returns(T::Boolean) }
  def installed?
    path.directory?
  end

  # Check whether this {Tap} is a shallow clone.
  sig { returns(T::Boolean) }
  def shallow?
    (path/".git/shallow").exist?
  end

  sig { overridable.returns(T::Boolean) }
  def core_tap?
    false
  end

  sig { returns(T::Boolean) }
  def core_cask_tap?
    false
  end

  # Install this {Tap}.
  #
  # @param clone_target If passed, it will be used as the clone remote.
  # @param quiet If set, suppress all output.
  # @param custom_remote If set, change the tap's remote if already installed.
  # @param verify If set, verify all the formula, casks and aliases in the tap are valid.
  # @param force If set, force core and cask taps to install even under API mode.
  #
  # @api public
  sig {
    overridable.params(
      quiet:         T::Boolean,
      clone_target:  T.nilable(T.any(Pathname, String)),
      custom_remote: T::Boolean,
      verify:        T::Boolean,
      force:         T::Boolean,
    ).void
  }
  def install(quiet: false, clone_target: nil,
              custom_remote: false, verify: false, force: false)
    require "descriptions"
    require "readall"

    if official? && DEPRECATED_OFFICIAL_TAPS.include?(repository)
      odie "#{name} was deprecated. This tap is now empty and all its contents were either deleted or migrated."
    elsif user == "caskroom" || name == "phinze/cask"
      new_repository = (repository == "cask") ? "cask" : "cask-#{repository}"
      odie "#{name} was moved. Tap homebrew/#{new_repository} instead."
    end

    raise TapNoCustomRemoteError, name if custom_remote && clone_target.nil?

    requested_remote = clone_target || default_remote

    if installed? && !custom_remote
      raise TapRemoteMismatchError.new(name, @remote, requested_remote) if clone_target && requested_remote != remote
      raise TapAlreadyTappedError, name unless shallow?
    end

    if !allowed_by_env? || forbidden_by_env?
      owner = Homebrew::EnvConfig.forbidden_owner
      owner_contact = if (contact = Homebrew::EnvConfig.forbidden_owner_contact.presence)
        "\n#{contact}"
      end

      error_message = "The installation of the #{full_name} was requested but #{owner}\n"
      error_message << "has not allowed this tap in `$HOMEBREW_ALLOWED_TAPS`" unless allowed_by_env?
      error_message << " and\n" if !allowed_by_env? && forbidden_by_env?
      error_message << "has forbidden this tap in `$HOMEBREW_FORBIDDEN_TAPS`" if forbidden_by_env?
      error_message << ".#{owner_contact}"

      odie error_message
    end

    # ensure git is installed
    Utils::Git.ensure_installed!

    if installed?
      if requested_remote != remote # we are sure that clone_target is not nil and custom_remote is true here
        fix_remote_configuration(requested_remote:, quiet:)
      end

      config.delete(:forceautoupdate)

      $stderr.ohai "Unshallowing #{name}" if shallow? && !quiet
      args = %w[fetch]
      # Git throws an error when attempting to unshallow a full clone
      args << "--unshallow" if shallow?
      args << "-q" if quiet
      path.cd { safe_system "git", *args }
      return
    elsif (core_tap? || core_cask_tap?) && !Homebrew::EnvConfig.no_install_from_api? && !force
      odie "Tapping #{name} is no longer typically necessary.\n" \
           "Add #{Formatter.option("--force")} if you are sure you need it for contributing to Homebrew."
    end

    clear_cache
    Tap.clear_cache

    $stderr.ohai "Tapping #{name}" unless quiet
    args =  %W[clone #{requested_remote} #{path}]

    # Override possible user configs like:
    #   git config --global clone.defaultRemoteName notorigin
    args << "--origin=origin"
    args << "-q" if quiet

    # Override user-set default template.
    args << "--template="
    # Prevent `fsmonitor` from watching this repository.
    args << "--config" << "core.fsmonitor=false"

    begin
      safe_system "git", *args

      if verify && !Homebrew::EnvConfig.developer? && !Readall.valid_tap?(self, aliases: true)
        raise "Cannot tap #{name}: invalid syntax in tap!"
      end
    rescue Interrupt, RuntimeError
      ignore_interrupts do
        # wait for git to possibly cleanup the top directory when interrupt happens.
        sleep 0.1
        FileUtils.rm_rf path
        path.parent.rmdir_if_possible
      end
      raise
    end

    Commands.rebuild_commands_completion_list
    link_completions_and_manpages

    formatted_contents = contents.presence&.to_sentence&.prepend(" ")
    $stderr.puts "Tapped#{formatted_contents} (#{path.abv})." unless quiet

    require "description_cache_store"
    CacheStoreDatabase.use(:descriptions) do |db|
      DescriptionCacheStore.new(db)
                           .update_from_formula_names!(formula_names)
    end
    CacheStoreDatabase.use(:cask_descriptions) do |db|
      CaskDescriptionCacheStore.new(db)
                               .update_from_cask_tokens!(cask_tokens)
    end

    if official?
      untapped = self.class.untapped_official_taps
      untapped -= [name]

      if untapped.empty?
        Homebrew::Settings.delete :untapped
      else
        Homebrew::Settings.write :untapped, untapped.join(";")
      end
    end

    return if clone_target
    return unless private?
    return if quiet

    path.cd do
      return if Utils.popen_read("git", "config", "--get", "credential.helper").present?
    end

    $stderr.puts <<~EOS
      It looks like you tapped a private repository. To avoid entering your
      credentials each time you update, you can use git HTTP credential
      caching or issue the following command:
        cd #{path}
        git remote set-url origin git@github.com:#{full_name}.git
    EOS
  end

  sig { void }
  def link_completions_and_manpages
    require "utils/link"

    command = "brew tap --repair"
    Utils::Link.link_manpages(path, command)

    require "completions"
    Homebrew::Completions.show_completions_message_if_needed
    if official? || Homebrew::Completions.link_completions?
      Utils::Link.link_completions(path, command)
    else
      Utils::Link.unlink_completions(path)
    end
  end

  sig { params(requested_remote: T.nilable(T.any(Pathname, String)), quiet: T::Boolean).void }
  def fix_remote_configuration(requested_remote: nil, quiet: false)
    if requested_remote.present?
      path.cd do
        safe_system "git", "remote", "set-url", "origin", requested_remote
        safe_system "git", "config", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*"
      end
      $stderr.ohai "#{name}: changed remote from #{remote} to #{requested_remote}" unless quiet
    end
    return unless remote

    current_upstream_head = git_repository.origin_branch_name
    return if current_upstream_head.present? && requested_remote.blank? &&
              git_repository.origin_has_branch?(current_upstream_head)

    args = %w[fetch]
    args << "--quiet" if quiet
    args << "origin"
    args << "+refs/heads/*:refs/remotes/origin/*"
    safe_system "git", "-C", path, *args
    git_repository.set_head_origin_auto

    current_upstream_head ||= T.must(git_repository.origin_branch_name)

    new_upstream_head = T.must(git_repository.origin_branch_name)
    return if new_upstream_head == current_upstream_head

    safe_system "git", "-C", path, "config", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*"
    git_repository.rename_branch old: current_upstream_head, new: new_upstream_head
    git_repository.set_upstream_branch local: new_upstream_head, origin: new_upstream_head

    return if quiet

    $stderr.ohai "#{name}: changed default branch name from #{current_upstream_head} to #{new_upstream_head}!"
  end

  # Uninstall this {Tap}.
  #
  # @api public
  sig { overridable.params(manual: T::Boolean).void }
  def uninstall(manual: false)
    require "descriptions"
    raise TapUnavailableError, name unless installed?

    $stderr.puts "Untapping #{name}..."

    abv = path.abv
    formatted_contents = contents.presence&.to_sentence&.prepend(" ")

    require "description_cache_store"
    CacheStoreDatabase.use(:descriptions) do |db|
      DescriptionCacheStore.new(db)
                           .delete_from_formula_names!(formula_names)
    end
    CacheStoreDatabase.use(:cask_descriptions) do |db|
      CaskDescriptionCacheStore.new(db)
                               .delete_from_cask_tokens!(cask_tokens)
    end

    require "utils/link"
    Utils::Link.unlink_manpages(path)
    Utils::Link.unlink_completions(path)
    FileUtils.rm_r(path)
    path.parent.rmdir_if_possible
    $stderr.puts "Untapped#{formatted_contents} (#{abv})."

    Commands.rebuild_commands_completion_list
    clear_cache
    Tap.clear_cache

    return if !manual || !official?

    untapped = self.class.untapped_official_taps
    return if untapped.include? name

    untapped << name
    Homebrew::Settings.write :untapped, untapped.join(";")
  end

  # Check whether the {#remote} of {Tap} is customized.
  #
  # @api public
  sig { returns(T::Boolean) }
  def custom_remote?
    return true unless (remote = self.remote)

    !T.must(remote.casecmp(default_remote)).zero?
  end

  # Path to the directory of all {Formula} files for this {Tap}.
  #
  # @api public
  sig { overridable.returns(Pathname) }
  def formula_dir
    # Official formulae taps always use this directory, saves time to hardcode.
    @formula_dir ||= T.let(
      if official?
        path/"Formula"
      else
        potential_formula_dirs.find(&:directory?) || (path/"Formula")
      end,
      T.nilable(Pathname),
    )
  end

  sig { returns(T::Array[Pathname]) }
  def potential_formula_dirs
    @potential_formula_dirs ||= T.let([path/"Formula", path/"HomebrewFormula", path].freeze, T.nilable(T::Array[Pathname]))
  end

  sig { overridable.params(name: String).returns(Pathname) }
  def new_formula_path(name)
    formula_dir/"#{name.downcase}.rb"
  end

  # Path to the directory of all {Cask} files for this {Tap}.
  #
  # @api public
  sig { returns(Pathname) }
  def cask_dir
    @cask_dir ||= T.let(path/"Casks", T.nilable(Pathname))
  end

  sig { params(token: String).returns(Pathname) }
  def new_cask_path(token)
    cask_dir/"#{token.downcase}.rb"
  end

  sig { params(token: String).returns(String) }
  def relative_cask_path(token)
    new_cask_path(token).to_s
                        .delete_prefix("#{path}/")
  end

  sig { returns(T::Array[String]) }
  def contents
    contents = []

    if (command_count = command_files.count).positive?
      contents << Utils.pluralize("command", command_count, include_count: true)
    end

    if (cask_count = cask_files.count).positive?
      contents << Utils.pluralize("cask", cask_count, include_count: true)
    end

    if (formula_count = formula_files.count).positive?
      contents << Utils.pluralize("formula", formula_count, include_count: true)
    end

    contents
  end

  # An array of all {Formula} files of this {Tap}.
  sig { overridable.returns(T::Array[Pathname]) }
  def formula_files
    @formula_files ||= T.let(
      if formula_dir.directory?
        if formula_dir == path
          # We only want the top level here so we don't treat commands & casks as formulae.
          # Sharding is only supported in Formula/ and HomebrewFormula/.
          Pathname.glob(formula_dir/"*.rb")
        else
          Pathname.glob(formula_dir/"**/*.rb")
        end
      else
        []
      end,
      T.nilable(T::Array[Pathname]),
    )
  end

  # A mapping of {Formula} names to {Formula} file paths.
  sig { overridable.returns(T::Hash[String, Pathname]) }
  def formula_files_by_name
    @formula_files_by_name ||= T.let(formula_files.each_with_object({}) do |file, hash|
      # If there's more than one file with the same basename: use the longer one to prioritise more specific results.
      basename = file.basename(".rb").to_s
      existing_file = hash[basename]
      hash[basename] = file if existing_file.nil? || existing_file.to_s.length < file.to_s.length
    end, T.nilable(T::Hash[String, Pathname]))
  end

  # An array of all {Cask} files of this {Tap}.
  sig { returns(T::Array[Pathname]) }
  def cask_files
    @cask_files ||= T.let(
      if cask_dir.directory?
        Pathname.glob(cask_dir/"**/*.rb")
      else
        []
      end,
      T.nilable(T::Array[Pathname]),
    )
  end

  # A mapping of {Cask} tokens to {Cask} file paths.
  sig { returns(T::Hash[String, Pathname]) }
  def cask_files_by_name
    @cask_files_by_name ||= T.let(cask_files.each_with_object({}) do |file, hash|
      # If there's more than one file with the same basename: use the longer one to prioritise more specific results.
      basename = file.basename(".rb").to_s
      existing_file = hash[basename]
      hash[basename] = file if existing_file.nil? || existing_file.to_s.length < file.to_s.length
    end, T.nilable(T::Hash[String, Pathname]))
  end

  RUBY_FILE_NAME_REGEX = %r{[^/]+\.rb}
  private_constant :RUBY_FILE_NAME_REGEX

  ZERO_OR_MORE_SUBDIRECTORIES_REGEX = %r{(?:[^/]+/)*}
  private_constant :ZERO_OR_MORE_SUBDIRECTORIES_REGEX

  sig { returns(Regexp) }
  def formula_file_regex
    @formula_file_regex ||= T.let(
      case formula_dir
      when path/"Formula"
        %r{^Formula/#{ZERO_OR_MORE_SUBDIRECTORIES_REGEX.source}#{RUBY_FILE_NAME_REGEX.source}$}o
      when path/"HomebrewFormula"
        %r{^HomebrewFormula/#{ZERO_OR_MORE_SUBDIRECTORIES_REGEX.source}#{RUBY_FILE_NAME_REGEX.source}$}o
      when path
        /^#{RUBY_FILE_NAME_REGEX.source}$/o
      else
        raise ArgumentError, "Unexpected formula_dir: #{formula_dir}"
      end,
      T.nilable(Regexp),
    )
  end
  private :formula_file_regex

  # accepts the relative path of a file from {Tap}'s path
  sig { params(file: String).returns(T::Boolean) }
  def formula_file?(file)
    file.match?(formula_file_regex)
  end

  CASK_FILE_REGEX = %r{^Casks/#{ZERO_OR_MORE_SUBDIRECTORIES_REGEX.source}#{RUBY_FILE_NAME_REGEX.source}$}
  private_constant :CASK_FILE_REGEX

  # accepts the relative path of a file from {Tap}'s path
  sig { params(file: String).returns(T::Boolean) }
  def cask_file?(file)
    file.match?(CASK_FILE_REGEX)
  end

  # An array of all {Formula} names of this {Tap}.
  sig { overridable.returns(T::Array[String]) }
  def formula_names
    @formula_names ||= T.let(formula_files.map { formula_file_to_name(it) }, T.nilable(T::Array[String]))
  end

  # A hash of all {Formula} name prefixes to versioned {Formula} in this {Tap}.
  sig { returns(T::Hash[String, T::Array[String]]) }
  def prefix_to_versioned_formulae_names
    @prefix_to_versioned_formulae_names ||= T.let(formula_names
                                                  .select { |name| name.include?("@") }
                                                  .group_by { |name| name.gsub(/(@[\d.]+)?$/, "") }
                                                  .transform_values(&:sort)
                                                  .freeze, T.nilable(T::Hash[String, T::Array[String]]))
  end

  # An array of all {Cask} tokens of this {Tap}.
  sig { returns(T::Array[String]) }
  def cask_tokens
    @cask_tokens ||= T.let(cask_files.map { formula_file_to_name(it) }, T.nilable(T::Array[String]))
  end

  # Path to the directory of all alias files for this {Tap}.
  sig { overridable.returns(Pathname) }
  def alias_dir
    @alias_dir ||= T.let(path/"Aliases", T.nilable(Pathname))
  end

  # An array of all alias files of this {Tap}.
  sig { returns(T::Array[Pathname]) }
  def alias_files
    @alias_files ||= T.let(Pathname.glob("#{alias_dir}/*").select(&:file?), T.nilable(T::Array[Pathname]))
  end

  # An array of all aliases of this {Tap}.
  sig { returns(T::Array[String]) }
  def aliases
    @aliases ||= T.let(alias_table.keys, T.nilable(T::Array[String]))
  end

  # Mapping from aliases to formula names.
  sig { overridable.returns(T::Hash[String, String]) }
  def alias_table
    @alias_table ||= T.let(alias_files.each_with_object({}) do |alias_file, alias_table|
      alias_table[alias_file_to_name(alias_file)] = formula_file_to_name(alias_file.resolved_path)
    end, T.nilable(T::Hash[String, String]))
  end

  # Mapping from formula names to aliases.
  sig { returns(T::Hash[String, T::Array[String]]) }
  def alias_reverse_table
    @alias_reverse_table ||= T.let(
      alias_table.each_with_object({}) do |(alias_name, formula_name), alias_reverse_table|
        alias_reverse_table[formula_name] ||= []
        alias_reverse_table[formula_name] << alias_name
      end,
      T.nilable(T::Hash[String, T::Array[String]]),
    )
  end

  sig { returns(Pathname) }
  def command_dir
    @command_dir ||= T.let(path/"cmd", T.nilable(Pathname))
  end

  # An array of all commands files of this {Tap}.
  sig { returns(T::Array[Pathname]) }
  def command_files
    @command_files ||= T.let(
      if command_dir.directory?
        Commands.find_commands(command_dir)
      else
        []
      end,
      T.nilable(T::Array[Pathname]),
    )
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def to_hash
    hash = {
      "name"          => name,
      "user"          => user,
      "repo"          => repository,
      "repository"    => repository,
      "path"          => path.to_s,
      "installed"     => installed?,
      "official"      => official?,
      "formula_names" => formula_names,
      "cask_tokens"   => cask_tokens,
    }

    if installed?
      hash["formula_files"] = formula_files.map(&:to_s)
      hash["cask_files"] = cask_files.map(&:to_s)
      hash["command_files"] = command_files.map(&:to_s)
      hash["remote"] = remote
      hash["custom_remote"] = custom_remote?
      hash["private"] = private?
      hash["HEAD"] = git_head || "(none)"
      hash["last_commit"] = git_last_commit || "never"
      hash["branch"] = git_branch || "(none)"
    end

    hash
  end

  # Hash with tap cask renames.
  sig { returns(T::Hash[String, String]) }
  def cask_renames
    @cask_renames ||= T.let(
      if (rename_file = path/HOMEBREW_TAP_CASK_RENAMES_FILE).file?
        JSON.parse(rename_file.read)
      else
        {}
      end,
      T.nilable(T::Hash[String, String]),
    )
  end

  # Mapping from new to old cask tokens. Reverse of {#cask_renames}.
  sig { returns(T::Hash[String, T::Array[String]]) }
  def cask_reverse_renames
    @cask_reverse_renames ||= T.let(cask_renames.each_with_object({}) do |(old_name, new_name), hash|
      hash[new_name] ||= []
      hash[new_name] << old_name
    end, T.nilable(T::Hash[String, T::Array[String]]))
  end

  # Hash with tap formula renames.
  sig { overridable.returns(T::Hash[String, String]) }
  def formula_renames
    @formula_renames ||= T.let(
      if (rename_file = path/HOMEBREW_TAP_FORMULA_RENAMES_FILE).file?
        JSON.parse(rename_file.read)
      else
        {}
      end,
      T.nilable(T::Hash[String, String]),
    )
  end

  # Mapping from new to old formula names. Reverse of {#formula_renames}.
  sig { returns(T::Hash[String, T::Array[String]]) }
  def formula_reverse_renames
    @formula_reverse_renames ||= T.let(formula_renames.each_with_object({}) do |(old_name, new_name), hash|
      hash[new_name] ||= []
      hash[new_name] << old_name
    end, T.nilable(T::Hash[String, T::Array[String]]))
  end

  # Hash with tap migrations.
  sig { overridable.returns(T::Hash[String, String]) }
  def tap_migrations
    @tap_migrations ||= T.let(
      if (migration_file = path/HOMEBREW_TAP_MIGRATIONS_FILE).file?
        JSON.parse(migration_file.read)
      else
        {}
      end, T.nilable(T::Hash[String, String])
    )
  end

  sig { returns(T::Hash[String, T::Array[String]]) }
  def reverse_tap_migrations_renames
    @reverse_tap_migrations_renames ||= T.let(
      tap_migrations.each_with_object({}) do |(old_name, new_name), hash|
        # Only include renames:
        # + `homebrew/cask/water-buffalo`
        # - `homebrew/cask`
        next if new_name.count("/") != 2

        hash[new_name] ||= []
        hash[new_name] << old_name
      end,
      T.nilable(T::Hash[String, T::Array[String]]),
    )
  end

  # The old names a formula or cask had before getting migrated to the current tap.
  sig { params(current_tap: Tap, name_or_token: String).returns(T::Array[String]) }
  def self.tap_migration_oldnames(current_tap, name_or_token)
    key = "#{current_tap}/#{name_or_token}"

    Tap.each_with_object([]) do |tap, array|
      next unless (renames = tap.reverse_tap_migrations_renames[key])

      array.concat(renames)
    end
  end

  # Array with autobump names
  sig { overridable.returns(T::Array[String]) }
  def autobump
    autobump_packages = if core_cask_tap?
      Homebrew::API::Cask.all_casks
    elsif core_tap?
      Homebrew::API::Formula.all_formulae
    else
      {}
    end

    @autobump ||= T.let(autobump_packages.select do |_, p|
      next if p["disabled"]
      next if p["deprecated"] && p["deprecation_reason"] != "fails_gatekeeper_check"
      next if p["skip_livecheck"]

      p["autobump"] == true
    end.keys, T.nilable(T::Array[String]))

    if @autobump.blank?
      @autobump = T.let(
        if (autobump_file = path/HOMEBREW_TAP_AUTOBUMP_FILE).file?
          autobump_file.readlines(chomp: true)
        else
          []
        end,
        T.nilable(T::Array[String]),
      )
    end

    T.must(@autobump)
  end

  # Whether this {Tap} allows running bump commands on the given {Formula} or {Cask}.
  sig { params(formula_or_cask_name: String).returns(T::Boolean) }
  def allow_bump?(formula_or_cask_name)
    ENV["HOMEBREW_TEST_BOT_AUTOBUMP"].present? || !official? || autobump.exclude?(formula_or_cask_name)
  end

  # Hash with audit exceptions
  sig { overridable.returns(T::Hash[Symbol, T.untyped]) }
  def audit_exceptions
    @audit_exceptions ||= T.let(read_formula_list_directory("#{HOMEBREW_TAP_AUDIT_EXCEPTIONS_DIR}/*"),
                                T.nilable(T::Hash[Symbol, T.untyped]))
  end

  # Hash with style exceptions
  sig { overridable.returns(T::Hash[Symbol, T.untyped]) }
  def style_exceptions
    @style_exceptions ||= T.let(read_formula_list_directory("#{HOMEBREW_TAP_STYLE_EXCEPTIONS_DIR}/*"),
                                T.nilable(T::Hash[Symbol, T.untyped]))
  end

  # Array with synced versions formulae
  sig { overridable.returns(T::Array[T::Array[String]]) }
  def synced_versions_formulae
    @synced_versions_formulae ||= T.let(
      if (synced_file = path/HOMEBREW_TAP_SYNCED_VERSIONS_FORMULAE_FILE).file?
        JSON.parse(synced_file.read)
      else
        []
      end,
      T.nilable(T::Array[T::Array[String]]),
    )
  end

  # Array with formulae that should not be relocated to new /usr/local
  sig { overridable.returns(T::Array[String]) }
  def disabled_new_usr_local_relocation_formulae
    @disabled_new_usr_local_relocation_formulae ||= T.let(
      if (synced_file = path/HOMEBREW_TAP_DISABLED_NEW_USR_LOCAL_RELOCATION_FORMULAE_FILE).file?
        JSON.parse(synced_file.read)
      else
        []
      end,
      T.nilable(T::Array[String]),
    )
  end

  sig { returns(T::Boolean) }
  def should_report_analytics?
    installed? && !private?
  end

  sig { params(other: T.nilable(T.any(String, Tap))).returns(T::Boolean) }
  def ==(other)
    other = Tap.fetch(other) if other.is_a?(String)
    other.is_a?(self.class) && name == other.name
  end
  alias eql? ==

  sig { returns(Integer) }
  def hash
    [self.class, name].hash
  end

  # All locally installed taps.
  #
  # @api public
  sig { returns(T::Array[Tap]) }
  def self.installed
    cache[:installed] ||= if HOMEBREW_TAP_DIRECTORY.directory?
      HOMEBREW_TAP_DIRECTORY.subdirs.flat_map(&:subdirs).map { from_path(it) }
    else
      []
    end
  end

  # All locally installed and core taps. Core taps might not be installed locally when using the API.
  sig { returns(T::Array[Tap]) }
  def self.all
    cache[:all] ||= installed | core_taps
  end

  sig { returns(T::Array[Tap]) }
  def self.core_taps
    [CoreTap.instance].freeze
  end

  # Enumerate all available {Tap}s.
  #
  # @api public
  sig { override.params(block: T.nilable(T.proc.params(tap: Tap).void)).returns(T.any(T::Array[Tap], T::Enumerator[Tap])) }
  def self.each(&block)
    return to_enum unless block_given?

    if Homebrew::EnvConfig.no_install_from_api?
      installed.each(&block)
    else
      all.each(&block)
    end
  end

  # An array of official taps that have been manually untapped
  sig { returns(T::Array[String]) }
  def self.untapped_official_taps
    Homebrew::Settings.read(:untapped)&.split(";") || []
  end

  sig { overridable.params(file: Pathname).returns(String) }
  def formula_file_to_name(file)
    "#{name}/#{file.basename(".rb")}"
  end

  sig { overridable.params(file: Pathname).returns(String) }
  def alias_file_to_name(file)
    "#{name}/#{file.basename}"
  end

  sig {
    overridable.params(list: Symbol, formula_or_cask: String, value: T.nilable(T.any(String, Version)))
               .returns(T.any(T::Boolean, String))
  }
  def audit_exception(list, formula_or_cask, value = nil)
    return false if audit_exceptions.blank?
    return false unless audit_exceptions.key? list

    list = audit_exceptions[list]

    case list
    when Array
      list.include? formula_or_cask
    when Hash
      return false unless list.include? formula_or_cask
      return list[formula_or_cask] if value.blank?

      return list[formula_or_cask].include?(value) if list[formula_or_cask].is_a?(Array)

      list[formula_or_cask] == value
    end
  end

  sig { returns(T::Boolean) }
  def allowed_by_env?
    @allowed_by_env ||= T.let(begin
      allowed_taps = self.class.allowed_taps

      official? || allowed_taps.blank? || allowed_taps.include?(self)
    end, T.nilable(T::Boolean))
  end

  sig { returns(T::Boolean) }
  def forbidden_by_env?
    @forbidden_by_env ||= T.let(self.class.forbidden_taps.include?(self), T.nilable(T::Boolean))
  end

  private

  sig { params(file: Pathname).returns(T.any(T::Array[String], T::Hash[String, T.untyped])) }
  def read_formula_list(file)
    JSON.parse file.read
  rescue JSON::ParserError
    opoo "#{file} contains invalid JSON"
    {}
  rescue Errno::ENOENT
    {}
  end

  sig { params(directory: String).returns(T::Hash[Symbol, T.untyped]) }
  def read_formula_list_directory(directory)
    list = {}

    Pathname.glob(path/directory).each do |exception_file|
      list_name = exception_file.basename.to_s.chomp(".json").to_sym
      list_contents = read_formula_list exception_file

      next if list_contents.blank?

      list[list_name] = list_contents
    end

    list
  end
end

class AbstractCoreTap < Tap
  extend T::Helpers

  abstract!

  class << self
    Elem = type_member(:out) { { fixed: Tap } }
  end

  private_class_method :fetch

  # Get the singleton instance for this {Tap}.
  #
  # @api internal
  sig { returns(T.attached_class) }
  def self.instance
    @instance ||= T.let(T.unsafe(self).new, T.nilable(T.attached_class))
  end

  sig { override.void }
  def ensure_installed!
    return unless Homebrew::EnvConfig.no_install_from_api?
    return if Homebrew::EnvConfig.automatically_set_no_install_from_api?

    super
  end

  sig { override.params(file: Pathname).returns(String) }
  def formula_file_to_name(file)
    file.basename(".rb").to_s
  end

  sig { override.returns(T::Boolean) }
  def should_report_analytics?
    return super if Homebrew::EnvConfig.no_install_from_api?

    true
  end
end

# A specialized {Tap} class for the core formulae.
class CoreTap < AbstractCoreTap
  class << self
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

# A specialized {Tap} class for homebrew-cask.
class CoreCaskTap < AbstractCoreTap
  class << self
    Elem = type_member(:out) { { fixed: Tap } }
  end

  sig { void }
  def initialize
    super "Homebrew", "cask"
  end

  sig { override.returns(T::Boolean) }
  def core_cask_tap?
    true
  end

  sig { params(token: String).returns(String) }
  def new_cask_subdirectory(token)
    if token.start_with?("font-")
      "font/font-#{token.delete_prefix("font-")[0]}"
    else
      token[0].to_s
    end
  end

  sig { override.params(token: String).returns(Pathname) }
  def new_cask_path(token)
    cask_dir/new_cask_subdirectory(token)/"#{token.downcase}.rb"
  end

  sig { override.returns(T::Array[Pathname]) }
  def cask_files
    return super if Homebrew::EnvConfig.no_install_from_api?

    cask_files_by_name.values
  end

  sig { override.returns(T::Array[String]) }
  def cask_tokens
    return super if Homebrew::EnvConfig.no_install_from_api?

    Homebrew::API.cask_tokens
  end

  sig { override.returns(T::Hash[String, Pathname]) }
  def cask_files_by_name
    return super if Homebrew::EnvConfig.no_install_from_api?

    @cask_files_by_name ||= T.let(
      begin
        cask_directory_path = cask_dir.to_s
        Homebrew::API.cask_tokens.each_with_object({}) do |name, hash|
          # If there's more than one item with the same path: use the longer one to prioritise more specific results.
          existing_path = hash[name]
          # Pathname equivalent is slow in a tight loop
          new_path = File.join(cask_directory_path, new_cask_subdirectory(name), "#{name.downcase}.rb")
          hash[name] = Pathname(new_path) if existing_path.nil? || existing_path.to_s.length < new_path.length
        end
      end,
      T.nilable(T::Hash[String, Pathname]),
    )
  end

  sig { override.returns(T::Hash[String, String]) }
  def cask_renames
    @cask_renames ||= T.let(
      if Homebrew::EnvConfig.no_install_from_api?
        super
      else
        Homebrew::API.cask_renames
      end,
      T.nilable(T::Hash[String, String]),
    )
  end

  sig { override.returns(T::Hash[String, T.untyped]) }
  def tap_migrations
    @tap_migrations ||= T.let(
      if Homebrew::EnvConfig.no_install_from_api?
        super
      else
        Homebrew::API.cask_tap_migrations
      end,
      T.nilable(T::Hash[String, T.untyped]),
    )
  end
end

# Permanent configuration per {Tap} using `git-config(1)`.
class TapConfig
  sig { returns(Tap) }
  attr_reader :tap

  sig { params(tap: Tap).void }
  def initialize(tap)
    @tap = tap
  end

  sig { params(key: Symbol).returns(T.nilable(T::Boolean)) }
  def [](key)
    return unless tap.git?
    return unless Utils::Git.available?

    case Homebrew::Settings.read(key, repo: tap.path)
    when "true" then true
    when "false" then false
    end
  end

  sig { params(key: Symbol, value: T::Boolean).void }
  def []=(key, value)
    return unless tap.git?
    return unless Utils::Git.available?

    Homebrew::Settings.write key, value.to_s, repo: tap.path
  end

  sig { params(key: Symbol).void }
  def delete(key)
    return unless tap.git?
    return unless Utils::Git.available?

    Homebrew::Settings.delete key, repo: tap.path
  end
end

require "extend/os/tap"
