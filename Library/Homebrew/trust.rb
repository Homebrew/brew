# typed: strict
# frozen_string_literal: true

require "env_config"
require "etc"
require "json"
require "tap"
require "utils"
require "utils/output"

module Homebrew
  class InsecureTrustStoreError < RuntimeError; end
  class UntrustedTapError < RuntimeError; end

  module Trust
    extend Utils::Output::Mixin

    SETTING_KEYS = T.let({
      tap:     :trustedtaps,
      formula: :trustedformulae,
      cask:    :trustedcasks,
      command: :trustedcommands,
    }.freeze, T::Hash[Symbol, Symbol])
    private_constant :SETTING_KEYS

    sig { params(home: T.any(String, Pathname)).returns(Pathname) }
    def self.trust_file(home: Dir.home(ENV.fetch("USER")))
      user_config_home = Pathname.new(ENV.fetch("HOMEBREW_USER_CONFIG_HOME"))
      if user_config_home == Pathname.new(Dir.home(ENV.fetch("USER")))/".homebrew"
        Pathname.new(home.to_s)/".homebrew/trust.json"
      else
        user_config_home/"trust.json"
      end
    end

    sig { params(type: Symbol, name: T.any(String, Tap)).returns(T::Boolean) }
    def self.trust!(type, name)
      if name.is_a?(Tap)
        raise ArgumentError, "a #{type} trust name must be a String, not a Tap" if type != :tap

        name = name.reference
      end
      key = setting_key(type)
      name = normalise_name(name)
      with_trust_store_lock do
        store = trust_store
        entries = store.fetch(key, [])
        next false if entries.include?(name)

        store[key] = (entries + [name]).sort
        write_trust_store(store)
        true
      end
    end

    sig { params(type: Symbol, name: String).returns(T::Boolean) }
    def self.untrust!(type, name)
      key = setting_key(type)
      name = normalise_name(name)
      entries_to_delete = T.let([name], T::Array[String])
      if type != :tap && ::Utils.full_name?(name) && (tap_name = ::Utils.tap_from_full_name(name))
        tap = Tap.fetch(tap_name)
        entries_to_delete << item_trust_name(type, tap, ::Utils.name_from_full_name(name)) if tap.uses_custom_remote?
      end

      with_trust_store_lock do
        store = trust_store
        entries = store.fetch(key, [])
        removed = T.let(false, T::Boolean)
        entries_to_delete.uniq.each { |entry| removed = true if entries.delete(entry) }
        next false unless removed

        if entries.empty?
          store.delete(key)
        else
          store[key] = entries.sort
        end
        write_trust_store(store)
        true
      end
    end

    sig { params(name: String, remote: T.nilable(String)).returns(T::Boolean) }
    def self.invalidate_tap_references!(name, remote: nil)
      name = normalise_name(name)
      references = [name]
      references << normalise_name(remote) if remote.present?
      if remote.present? && (remote_reference = Tap.remote_to_reference(remote))
        references << normalise_name(remote_reference)
      end
      references.uniq!

      with_trust_store_lock do
        store = trust_store
        changed = T.let(false, T::Boolean)
        store.keys.each do |key|
          entries = store.fetch(key)
          filtered_entries = entries.reject do |entry|
            references.include?(entry) || entry.start_with?("#{name}/")
          end
          next if filtered_entries == entries

          changed = true
          if filtered_entries.empty?
            store.delete(key)
          else
            store[key] = filtered_entries.sort
          end
        end
        write_trust_store(store) if changed
        changed
      end
    end

    sig { params(names: T::Array[String], type: T.nilable(Symbol)).void }
    def self.trust_fully_qualified_items!(names, type: nil)
      names.each do |name|
        next unless ::Utils.full_name?(name)

        tap_name = name.split("/").first(2).join("/")
        item_name = ::Utils.name_from_full_name(name)
        tap = Tap.fetch(tap_name)
        next if tap.official?

        types = if type == :formula
          tap.formula_files_by_name.key?(item_name) ? [:formula] : []
        elsif type == :cask
          tap.cask_files_by_name.key?(item_name) ? [:cask] : []
        elsif tap.formula_files_by_name.key?(item_name)
          [:formula]
        elsif tap.cask_files_by_name.key?(item_name)
          [:cask]
        else
          []
        end
        types.each do |item_type|
          full_name = "#{tap.name}/#{item_name}"
          if trust!(item_type, item_trust_name(item_type, tap, item_name))
            $stderr.ohai "Trusted #{item_type} #{full_name}"
          end
        end
      rescue Tap::InvalidNameError
        nil
      end
    end

    sig { params(type: Symbol).void }
    def self.clear!(type)
      with_trust_store_lock do
        store = trust_store
        store.delete(setting_key(type))
        write_trust_store(store)
      end
    end

    sig { params(entries: T::Array[[Symbol, String]]).void }
    def self.replace!(entries)
      store = T.let({}, T::Hash[String, T::Array[String]])
      entries.each do |type, name|
        key = setting_key(type)
        store[key] ||= []
        store.fetch(key) << normalise_name(name)
      end
      store.keys.each do |key|
        store[key] = store.fetch(key).uniq.sort
      end

      with_trust_store_lock do
        write_trust_store(store)
      end
    end

    sig { params(type: Symbol, name: String).returns(T::Boolean) }
    def self.trusted?(type, name)
      name = normalise_name(name)
      entries = trusted_entries(type)
      return true if entries.include?(name)

      if type == :tap
        return false if Tap.remote_reference?(name)

        return explicitly_trusted_tap?(Tap.fetch(name))
      end
      return false unless (tap_name = ::Utils.tap_from_full_name(name))

      tap = Tap.fetch(tap_name)
      return true if trusted_tap?(tap)

      item_name = normalise_name(::Utils.name_from_full_name(name))
      return true if entries.include?(item_trust_name(type, tap, item_name))
      return false unless tap.uses_custom_remote?

      entries.any? do |entry|
        next false unless entry.end_with?("/#{item_name}")

        Tap.same_remote?(entry.delete_suffix("/#{item_name}"), tap.remote)
      end
    rescue Tap::InvalidNameError
      false
    end

    sig { params(tap: Tap).returns(T::Boolean) }
    def self.trusted_tap?(tap)
      tap.implicitly_trusted? || explicitly_trusted_tap?(tap)
    end

    # Whether the tap appears in the trust list, ignoring any implicit official-tap trust. The
    # entries may be `user/repository` names or remote URLs, so match via {Tap#matches_reference?}.
    sig { params(tap: Tap).returns(T::Boolean) }
    def self.explicitly_trusted_tap?(tap)
      trusted_entries(:tap).any? { |reference| tap.matches_reference?(reference) }
    end

    sig { params(name: String, path: Pathname).void }
    def self.require_trusted_formula!(name, path)
      return if Homebrew::EnvConfig.no_require_tap_trust?
      return unless (tap = tap_from_path(path))
      return if trusted_tap?(tap)

      full_name = "#{tap.name}/#{::Utils.name_from_full_name(name)}"
      return if trusted?(:formula, full_name)
      return if explicitly_allowed?(:formula, full_name, tap)
      return unless Homebrew::EnvConfig.require_tap_trust?

      raise_untrusted!(:formula, full_name, tap)
    end

    sig { params(token: String, path: Pathname).void }
    def self.require_trusted_cask!(token, path)
      return if Homebrew::EnvConfig.no_require_tap_trust?
      return unless (tap = tap_from_path(path))
      return if trusted_tap?(tap)

      full_name = "#{tap.name}/#{::Utils.name_from_full_name(token)}"
      return if trusted?(:cask, full_name)
      return if explicitly_allowed?(:cask, full_name, tap)
      return unless Homebrew::EnvConfig.require_tap_trust?

      raise_untrusted!(:cask, full_name, tap)
    end

    sig { params(path: Pathname, command: T.nilable(String)).void }
    def self.require_trusted_command!(path, command = nil)
      return if Homebrew::EnvConfig.no_require_tap_trust?
      return unless (tap = tap_from_path(path))
      return if trusted_tap?(tap)

      full_name = "#{tap.name}/#{command || path.basename(path.extname).to_s.delete_prefix("brew-")}"
      return if trusted?(:command, full_name)
      return unless Homebrew::EnvConfig.require_tap_trust?

      raise_untrusted!(:command, full_name, tap)
    end

    sig { params(path: Pathname).returns(T::Boolean) }
    def self.trusted_formula_file?(path)
      trusted_file?(:formula, path)
    end

    sig { params(path: Pathname).returns(T::Boolean) }
    def self.trusted_cask_file?(path)
      trusted_file?(:cask, path)
    end

    sig { params(files: T::Array[Pathname]).returns(T::Array[Pathname]) }
    def self.trusted_formula_files(files)
      trusted_files(:formula, files)
    end

    sig { params(files: T::Array[Pathname]).returns(T::Array[Pathname]) }
    def self.trusted_cask_files(files)
      trusted_files(:cask, files)
    end

    sig { params(files: T::Array[Pathname]).returns(T::Array[Pathname]) }
    def self.trusted_command_files(files)
      trusted_files(:command, files)
    end

    sig { returns(T::Array[Tap]) }
    def self.untrusted_taps
      Tap.installed.reject(&:official?).reject { |tap| trusted_tap?(tap) }.sort_by(&:name)
    end

    sig { returns(T::Array[Tap]) }
    def self.wholly_untrusted_taps
      untrusted_taps.reject { |tap| partially_trusted_tap?(tap) }
    end

    sig { params(tap: Tap).returns(T::Boolean) }
    def self.partially_trusted_tap?(tap)
      trusted_entry_prefix?(:formula, tap) ||
        trusted_entry_prefix?(:cask, tap) ||
        trusted_entry_prefix?(:command, tap)
    end
    private_class_method :partially_trusted_tap?

    sig { params(type: Symbol).returns(String) }
    def self.setting_key(type)
      SETTING_KEYS.fetch(type).to_s
    end

    sig { params(type: Symbol).returns(T::Array[String]) }
    def self.trusted_entries(type)
      trust_store.fetch(setting_key(type), [])
    end

    sig { params(name: String).returns(String) }
    def self.normalise_name(name)
      name.downcase
    end

    sig {
      params(
        name: String, type: T.nilable(Symbol), include_existing: T::Boolean, tap_remote: T.nilable(String),
      ).returns([Symbol, String])
    }
    def self.target(name, type: nil, include_existing: false, tap_remote: nil)
      return [type, trust_name(type, name, include_existing:, tap_remote:)] if type

      infer_target(name, include_existing:)
    end

    sig { params(name: String, include_existing: T::Boolean).returns([Symbol, String]) }
    def self.infer_target(name, include_existing:)
      return [:tap, trust_name(:tap, name)] if name.count("/") == 1 || Tap.remote_reference?(name)

      tap_with_name = Tap.with_formula_name(name)
      unless tap_with_name
        raise UsageError,
              "Trust targets must be fully-qualified tap, formula, cask or command names."
      end

      tap, token = tap_with_name
      candidate_types = T.let([], T::Array[Symbol])
      candidate_types << :formula if tap.formula_files_by_name.key?(token)
      candidate_types << :cask if tap.cask_files_by_name.key?(token)
      if tap.command_files.any? { |path| path.basename(path.extname).to_s.delete_prefix("brew-") == token }
        candidate_types << :command
      end
      if include_existing
        full_name = "#{tap.name}/#{token}"
        candidate_types << :formula if trusted?(:formula, full_name)
        candidate_types << :cask if trusted?(:cask, full_name)
        candidate_types << :command if trusted?(:command, full_name)
      end
      candidates = T.let([], T::Array[[Symbol, String]])
      candidate_types.uniq.each do |candidate_type|
        candidates << [candidate_type, item_trust_name(candidate_type, tap, token, include_existing:)]
      end
      return candidates.fetch(0) if candidates.one?

      raise UsageError, "No formula, cask or command found for #{name}." if candidates.empty?

      raise UsageError, "Ambiguous trust target #{name}. Use `--formula`, `--cask` or `--command`."
    end
    private_class_method :infer_target

    sig {
      params(
        type: Symbol, name: String, include_existing: T::Boolean, tap_remote: T.nilable(String),
      ).returns(String)
    }
    def self.trust_name(type, name, include_existing: false, tap_remote: nil)
      case type
      when :tap
        if Tap.remote_reference?(name)
          reference = Tap.remote_to_reference(name)
          raise UsageError, "Invalid tap remote URL: #{name}" if reference.nil?

          reference
        else
          Tap.fetch(name).reference(remote: tap_remote)
        end
      when :formula
        tap, formula_name = fully_qualified_package_name(name, "Formulae")
        item_trust_name(type, tap, formula_name, include_existing:, tap_remote:)
      when :cask
        tap, token = fully_qualified_package_name(name, "Casks")
        item_trust_name(type, tap, token, include_existing:, tap_remote:)
      when :command
        tap, command_name = fully_qualified_package_name(name, "Commands")
        item_trust_name(type, tap, command_name, include_existing:, tap_remote:)
      else
        raise UsageError, "Unsupported trust target type: #{type}"
      end
    rescue Tap::InvalidNameError => e
      raise UsageError, e.message
    end
    private_class_method :trust_name

    sig {
      params(
        type: Symbol, tap: Tap, item_name: String, include_existing: T::Boolean, tap_remote: T.nilable(String),
      ).returns(String)
    }
    def self.item_trust_name(type, tap, item_name, include_existing: false, tap_remote: nil)
      item_name = normalise_name(item_name)
      full_name = "#{tap.name}/#{item_name}"
      return full_name if include_existing && trusted_entries(type).include?(normalise_name(full_name))

      reference = tap.reference(remote: tap_remote)
      return full_name if reference == tap.name

      "#{normalise_name(reference)}/#{item_name}"
    end
    private_class_method :item_trust_name

    sig { params(name: String, noun: String).returns([Tap, String]) }
    def self.fully_qualified_package_name(name, noun)
      tap_with_name = Tap.with_formula_name(name)
      raise UsageError, "#{noun} must be fully-qualified as <user>/<tap>/<name>." unless tap_with_name

      tap_with_name
    end
    private_class_method :fully_qualified_package_name

    sig { returns(T::Hash[String, T::Array[String]]) }
    def self.trust_store
      trust_path = if Homebrew.running_as_root? &&
                      (sudo_user = ENV.fetch("HOMEBREW_SUDO_USER", nil).presence) &&
                      sudo_user != "root"
        passwd = begin
          Etc.getpwnam(sudo_user)
        rescue ArgumentError
          nil
        end

        if passwd
          trust_file(home: passwd.dir)
        else
          opoo "Could not determine home directory for `$HOMEBREW_SUDO_USER` (#{sudo_user}); " \
               "falling back to #{trust_file}."
          trust_file
        end
      else
        trust_file
      end
      return {} unless trust_path.exist?

      parsed_store = JSON.parse(trust_path.read)
      return {} unless parsed_store.is_a?(Hash)

      parsed_store.transform_values { |entries| Array(entries).map { |entry| normalise_name(entry.to_s) } }
    rescue Errno::ENOENT, JSON::ParserError
      {}
    end
    private_class_method :trust_store

    sig { params(store: T::Hash[String, T::Array[String]]).void }
    def self.write_trust_store(store)
      write_path = trust_file
      if write_path.symlink?
        link_parent = write_path.dirname.realpath
        assert_secure_trust_store_path!(link_parent, link_parent.stat, "symlink directory")
        if write_path.lstat.uid != Process.euid
          raise InsecureTrustStoreError,
                "Refusing to write insecure trust store: symlink #{write_path} is not owned by the current user."
        end
        target_path = write_path.readlink
        target_path = write_path.dirname/target_path unless target_path.absolute?
        target_parent = target_path.dirname.realpath
        assert_secure_trust_store_path!(target_parent, target_parent.stat, "target directory")
        write_path = target_parent/target_path.basename
        if write_path.symlink?
          raise InsecureTrustStoreError,
                "Refusing to write insecure trust store: target is a symlink."
        end
        if write_path.exist?
          assert_secure_trust_store_path!(write_path, write_path.stat, "target")
          unless write_path.file?
            raise InsecureTrustStoreError,
                  "Refusing to write insecure trust store: target is not a regular file."
          end
        end
      else
        ensure_secure_trust_store_directory!(write_path.dirname, "trust store directory")
        if write_path.exist?
          assert_secure_trust_store_path!(write_path, write_path.stat, "trust store")
          unless write_path.file?
            raise InsecureTrustStoreError,
                  "Refusing to write insecure trust store: trust store is not a regular file."
          end
        end
      end
      if store.empty?
        write_path.unlink if write_path.exist?
        return
      end

      write_path.atomic_write("#{JSON.pretty_generate(store)}\n")
      write_path.chmod(0600)
    rescue Errno::ENOENT
      raise InsecureTrustStoreError, "Refusing to write insecure trust store: target directory does not exist."
    end
    private_class_method :write_trust_store

    sig { params(path: Pathname, description: String).void }
    def self.ensure_secure_trust_store_directory!(path, description)
      existed = path.exist?
      path.mkpath
      path.chmod(0700) unless existed
      assert_secure_trust_store_path!(path, path.stat, description)
    end
    private_class_method :ensure_secure_trust_store_directory!

    sig { params(path: Pathname, stat: File::Stat, description: String).void }
    def self.assert_secure_trust_store_path!(path, stat, description)
      if stat.uid != Process.euid
        raise InsecureTrustStoreError,
              "Refusing to write insecure trust store: #{description} #{path} is not owned by the current user."
      end

      return if stat.mode.nobits?(022)

      raise InsecureTrustStoreError,
            "Refusing to write insecure trust store: #{description} #{path} is group or world writable."
    end
    private_class_method :assert_secure_trust_store_path!

    # Serialises trust store mutations so concurrent processes or threads
    # (e.g. parallel `brew bundle` installs) cannot lose entries in the
    # read-modify-write cycle.
    sig {
      type_parameters(:U).params(_block: T.proc.returns(T.type_parameter(:U))).returns(T.type_parameter(:U))
    }
    def self.with_trust_store_lock(&_block)
      lock_path = Pathname.new("#{trust_file}.lock")
      ensure_secure_trust_store_directory!(lock_path.dirname, "trust store directory")
      File.open(lock_path, File::RDWR | File::CREAT, 0600) do |lock_file|
        lock_file.flock(File::LOCK_EX)
        yield
      end
    end
    private_class_method :with_trust_store_lock

    sig { params(path: Pathname).returns(T.nilable(Tap)) }
    def self.tap_from_path(path)
      Tap.from_path(path)
    end
    private_class_method :tap_from_path

    sig { params(type: Symbol, path: Pathname).returns(T::Boolean) }
    def self.trusted_file?(type, path)
      return true if Homebrew::EnvConfig.no_require_tap_trust?
      return true unless (tap = tap_from_path(path))
      return true if trusted_tap?(tap)

      name = path.basename(path.extname).to_s
      name = name.delete_prefix("brew-") if type == :command
      full_name = "#{tap.name}/#{name}"
      return true if trusted?(type, full_name)
      return true if explicitly_allowed?(type, full_name, tap)

      !Homebrew::EnvConfig.require_tap_trust?
    end
    private_class_method :trusted_file?

    sig { params(type: Symbol, full_name: String, tap: Tap).returns(T::Boolean) }
    def self.explicitly_allowed?(type, full_name, tap)
      return false if type == :command

      downcased_args = ARGV.map(&:downcase)
      downcased_full_name = full_name.downcase
      tap_name = tap.name.downcase
      downcased_args.include?(downcased_full_name) ||
        downcased_args.include?(tap_name) ||
        downcased_args.include?("--tap=#{tap_name}") ||
        downcased_args.each_cons(2).any? { |option, value| option == "--tap" && value == tap_name }
    end
    private_class_method :explicitly_allowed?

    sig { params(type: Symbol, files: T::Array[Pathname]).returns(T::Array[Pathname]) }
    def self.trusted_files(type, files)
      trusted_files = files.select { |file| trusted_file?(type, file) }
      return trusted_files unless Homebrew::EnvConfig.require_tap_trust?

      skipped_taps = (files - trusted_files).filter_map { |file| tap_from_path(file) }.uniq.sort_by(&:name)
      skipped_taps.each do |tap|
        next if partially_trusted_tap?(tap)

        opoo "Skipping #{tap.name} because it is not trusted. Run `brew trust #{tap.name}` to trust it."
      end

      trusted_files
    end
    private_class_method :trusted_files

    sig { params(type: Symbol, tap: Tap).returns(T::Boolean) }
    def self.trusted_entry_prefix?(type, tap)
      prefixes = T.let([normalise_name(tap.reference)], T::Array[String])
      prefixes << tap.name if tap.uses_custom_remote?
      trusted_entries(type).any? do |entry|
        prefixes.any? { |prefix| entry.start_with?("#{prefix}/") }
      end
    end
    private_class_method :trusted_entry_prefix?

    sig { params(type: Symbol, name: String, tap: Tap).void }
    def self.raise_untrusted!(type, name, tap)
      raise UntrustedTapError, "Refusing to load #{type} #{name} from untrusted tap #{tap.name}.\n" \
                               "Run `brew trust --#{type} #{name}` or `brew trust #{tap.name}` to trust it."
    end
    private_class_method :raise_untrusted!
  end
end
