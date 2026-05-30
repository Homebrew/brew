# typed: strict
# frozen_string_literal: true

require "env_config"
require "json"
require "tap"
require "utils"
require "utils/output"

module Homebrew
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

    TRUST_FILE = T.let((HOMEBREW_PREFIX/"var/homebrew/trust.json").freeze, Pathname)
    private_constant :TRUST_FILE

    sig { returns(T::Boolean) }
    def self.enabled?
      Homebrew::EnvConfig.require_tap_trust? && !Homebrew::EnvConfig.no_require_tap_trust?
    end

    sig { params(type: Symbol, name: String).returns(T::Boolean) }
    def self.trust!(type, name)
      key = setting_key(type)
      entries = trusted_entries(type)
      name = normalise_name(name)
      return false if entries.include?(name)

      store = trust_store
      store[key] = (entries + [name]).sort
      write_trust_store(store)
      true
    end

    sig { params(type: Symbol, name: String).returns(T::Boolean) }
    def self.untrust!(type, name)
      key = setting_key(type)
      entries = trusted_entries(type)
      name = normalise_name(name)
      return false unless entries.delete(name)

      store = trust_store
      if entries.empty?
        store.delete(key)
      else
        store[key] = entries.sort
      end
      write_trust_store(store)
      true
    end

    sig { params(type: Symbol).void }
    def self.clear!(type)
      store = trust_store
      store.delete(setting_key(type))
      write_trust_store(store)
    end

    sig { params(type: Symbol, name: String).returns(T::Boolean) }
    def self.trusted?(type, name)
      trusted_entries(type).include?(normalise_name(name))
    end

    sig { params(tap: T.untyped).returns(T::Boolean) }
    def self.trusted_tap?(tap)
      tap.official? || trusted?(:tap, tap.name)
    end

    sig { params(name: String, path: Pathname).void }
    def self.require_trusted_formula!(name, path)
      return if Homebrew::EnvConfig.no_require_tap_trust?
      return unless (tap = tap_from_path(path))
      return if trusted_tap?(tap)

      full_name = "#{tap.name}/#{::Utils.name_from_full_name(name)}"
      return if trusted?(:formula, full_name)
      return trust_by_default!(tap) unless enabled?

      raise_untrusted!(:formula, full_name, tap)
    end

    sig { params(token: String, path: Pathname).void }
    def self.require_trusted_cask!(token, path)
      return if Homebrew::EnvConfig.no_require_tap_trust?
      return unless (tap = tap_from_path(path))
      return if trusted_tap?(tap)

      full_name = "#{tap.name}/#{::Utils.name_from_full_name(token)}"
      return if trusted?(:cask, full_name)
      return trust_by_default!(tap) unless enabled?

      raise_untrusted!(:cask, full_name, tap)
    end

    sig { params(path: Pathname, command: T.nilable(String)).void }
    def self.require_trusted_command!(path, command = nil)
      return if Homebrew::EnvConfig.no_require_tap_trust?
      return unless (tap = tap_from_path(path))
      return if trusted_tap?(tap)

      full_name = "#{tap.name}/#{command || path.basename(path.extname).to_s.delete_prefix("brew-")}"
      return if trusted?(:command, full_name)
      return trust_by_default!(tap) unless enabled?

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

    sig { params(name: String, type: T.nilable(Symbol), include_existing: T::Boolean).returns([Symbol, String]) }
    def self.target(name, type: nil, include_existing: false)
      return [type, trust_name(type, name)] if type

      infer_target(name, include_existing:)
    end

    sig { params(name: String, include_existing: T::Boolean).returns([Symbol, String]) }
    def self.infer_target(name, include_existing:)
      return [:tap, trust_name(:tap, name)] if name.count("/") == 1

      tap_with_name = Tap.with_formula_name(name)
      unless tap_with_name
        raise UsageError,
              "Trust targets must be fully-qualified tap, formula, cask or command names."
      end

      tap, token = tap_with_name
      full_name = "#{tap.name}/#{token}"
      candidates = T.let([], T::Array[[Symbol, String]])
      candidates << [:formula, full_name] if tap.formula_files_by_name.key?(token)
      candidates << [:cask, full_name] if tap.cask_files_by_name.key?(token)
      candidates << [:command, full_name] if command_file?(tap, token)
      if include_existing
        candidates << [:formula, full_name] if trusted?(:formula, full_name)
        candidates << [:cask, full_name] if trusted?(:cask, full_name)
        candidates << [:command, full_name] if trusted?(:command, full_name)
      end
      candidates.uniq!

      return candidates.fetch(0) if candidates.one?

      raise UsageError, "No formula, cask or command found for #{name}." if candidates.empty?

      raise UsageError, "Ambiguous trust target #{name}. Use `--formula`, `--cask` or `--command`."
    end
    private_class_method :infer_target

    sig { params(type: Symbol, name: String).returns(String) }
    def self.trust_name(type, name)
      case type
      when :tap
        Tap.fetch(name).name
      when :formula
        tap, formula_name = fully_qualified_package_name(name, "Formulae")
        "#{tap.name}/#{formula_name}"
      when :cask
        tap, token = fully_qualified_package_name(name, "Casks")
        "#{tap.name}/#{token}"
      when :command
        tap, command_name = fully_qualified_package_name(name, "Commands")
        "#{tap.name}/#{command_name}"
      else
        raise UsageError, "Unsupported trust target type: #{type}"
      end
    rescue Tap::InvalidNameError => e
      raise UsageError, e.message
    end
    private_class_method :trust_name

    sig { params(name: String, noun: String).returns([Tap, String]) }
    def self.fully_qualified_package_name(name, noun)
      tap_with_name = Tap.with_formula_name(name)
      raise UsageError, "#{noun} must be fully-qualified as <user>/<tap>/<name>." unless tap_with_name

      tap_with_name
    end
    private_class_method :fully_qualified_package_name

    sig { params(tap: Tap, command_name: String).returns(T::Boolean) }
    def self.command_file?(tap, command_name)
      tap.command_files.any? { |path| path.basename(path.extname).to_s.delete_prefix("brew-") == command_name }
    end
    private_class_method :command_file?

    sig { returns(T::Hash[String, T::Array[String]]) }
    def self.trust_store
      return {} unless TRUST_FILE.exist?

      parsed_store = JSON.parse(TRUST_FILE.read)
      return {} unless parsed_store.is_a?(Hash)

      parsed_store.transform_values { |entries| Array(entries).map { |entry| normalise_name(entry.to_s) } }
    rescue Errno::ENOENT, JSON::ParserError
      {}
    end
    private_class_method :trust_store

    sig { params(store: T::Hash[String, T::Array[String]]).void }
    def self.write_trust_store(store)
      if store.empty?
        TRUST_FILE.unlink if TRUST_FILE.exist?
        return
      end

      TRUST_FILE.dirname.mkpath
      TRUST_FILE.atomic_write("#{JSON.pretty_generate(store)}\n")
    end
    private_class_method :write_trust_store

    sig { params(tap: T.untyped).returns(T::Boolean) }
    def self.trust_by_default!(tap)
      trust!(:tap, tap.name)
      unless Homebrew::EnvConfig.no_env_hints?
        opoo <<~EOS
          Tap #{tap.name} was trusted by default.
          Homebrew will require explicit trust for non-official taps in a future release.
          Set `HOMEBREW_REQUIRE_TAP_TRUST=1` to require explicit trust now or `HOMEBREW_NO_REQUIRE_TAP_TRUST=1` to keep trusting by default.
          Hide these hints with `HOMEBREW_NO_ENV_HINTS=1` (see `man brew`).
        EOS
      end

      true
    end
    private_class_method :trust_by_default!

    sig { params(path: Pathname).returns(T.untyped) }
    def self.tap_from_path(path)
      Tap.from_path(path)
    end
    private_class_method :tap_from_path

    sig { params(type: Symbol, path: Pathname).returns(T::Boolean) }
    def self.trusted_file?(type, path)
      return true if Homebrew::EnvConfig.no_require_tap_trust?
      return true unless (tap = tap_from_path(path))
      return true if trusted_tap?(tap)

      return true if trusted?(type, "#{tap.name}/#{path.basename(path.extname)}")

      !enabled?
    end
    private_class_method :trusted_file?

    sig { params(type: Symbol, name: String, tap: T.untyped).void }
    def self.raise_untrusted!(type, name, tap)
      raise UntrustedTapError, "Refusing to load #{type} #{name} from untrusted tap #{tap.name}.\n" \
                               "Run `brew trust --#{type} #{name}` or `brew trust #{tap.name}` to trust it."
    end
    private_class_method :raise_untrusted!
  end
end
