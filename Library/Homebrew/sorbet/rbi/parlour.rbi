# typed: strict
class PATH
  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def each(*args, **options, &block); end
end

class Caveats
  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T::Boolean) }
  def empty?(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(String) }
  def to_s(*args, **options, &block); end
end

class Checksum
  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T::Boolean) }
  def empty?(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(String) }
  def to_s(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def length(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def [](*args, **options, &block); end
end

module Debrew
  sig { returns(T::Boolean) }
  def self.active?; end
end

class Formula
  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T::Boolean) }
  def bottle_defined?(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T::Boolean) }
  def bottle_tag?(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T::Boolean) }
  def bottled?(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def bottle_specification(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def downloader(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def desc(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def license(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def homepage(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def livecheck(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T::Boolean) }
  def livecheckable?(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T::Boolean) }
  def service?(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def version(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def allow_network_access!(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def deny_network_access!(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T::Boolean) }
  def network_access_allowed?(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T::Boolean) }
  def loaded_from_api?(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def deps(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def declared_deps(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def requirements(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def cached_download(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def clear_cache(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def options(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def deprecated_options(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def deprecated_flags(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T::Boolean) }
  def option_defined?(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def compiler_failures(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def pour_bottle_check_unsatisfied_reason(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def keg_only_reason(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T::Boolean) }
  def deprecated?(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def deprecation_date(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def deprecation_reason(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T::Boolean) }
  def disabled?(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def disable_date(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def disable_reason(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T::Boolean) }
  def pinnable?(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T::Boolean) }
  def pinned?(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def pinned_version(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def pin(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def unpin(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def env(*args, **options, &block); end

  sig { returns(T::Boolean) }
  def self.loaded_from_api?; end

  sig { returns(T::Boolean) }
  def self.on_system_blocks_exist?; end

  sig { params(arg: T.untyped).returns(T.untyped) }
  def self.desc(arg = T.unsafe(nil)); end

  sig { params(arg: T.untyped).returns(T.untyped) }
  def self.homepage(arg = T.unsafe(nil)); end

  sig { params(arg: T.untyped).returns(T.untyped) }
  def self.revision(arg = T.unsafe(nil)); end

  sig { params(arg: T.untyped).returns(T.untyped) }
  def self.version_scheme(arg = T.unsafe(nil)); end
end

class FormulaInstaller
  sig { returns(T::Boolean) }
  def installed_as_dependency?; end

  sig { returns(T::Boolean) }
  def installed_on_request?; end

  sig { returns(T::Boolean) }
  def show_summary_heading?; end

  sig { returns(T::Boolean) }
  def show_header?; end

  sig { returns(T::Boolean) }
  def force_bottle?; end

  sig { returns(T::Boolean) }
  def ignore_deps?; end

  sig { returns(T::Boolean) }
  def only_deps?; end

  sig { returns(T::Boolean) }
  def interactive?; end

  sig { returns(T::Boolean) }
  def git?; end

  sig { returns(T::Boolean) }
  def force?; end

  sig { returns(T::Boolean) }
  def overwrite?; end

  sig { returns(T::Boolean) }
  def keep_tmp?; end

  sig { returns(T::Boolean) }
  def debug_symbols?; end

  sig { returns(T::Boolean) }
  def verbose?; end

  sig { returns(T::Boolean) }
  def debug?; end

  sig { returns(T::Boolean) }
  def quiet?; end

  sig { returns(T::Boolean) }
  def hold_locks?; end
end

class Livecheck
  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def version(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def arch(*args, **options, &block); end
end

module MachOShim
  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def dylib_id(*args, **options, &block); end
end

class PkgVersion
  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def major(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def minor(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def patch(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def major_minor(*args, **options, &block); end

  sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
  def major_minor_patch(*args, **options, &block); end
end

class Requirement
  sig { params(arg: T.untyped).returns(T.untyped) }
  def self.fatal(arg = T.unsafe(nil)); end

  sig { params(arg: T.untyped).returns(T.untyped) }
  def self.cask(arg = T.unsafe(nil)); end

  sig { params(arg: T.untyped).returns(T.untyped) }
  def self.download(arg = T.unsafe(nil)); end
end

class BottleSpecification
  sig { params(arg: T.untyped).returns(T.untyped) }
  def rebuild(arg = T.unsafe(nil)); end
end

class SystemCommand
  sig { returns(T::Boolean) }
  def sudo?; end

  sig { returns(T::Boolean) }
  def sudo_as_root?; end

  sig { returns(T::Boolean) }
  def must_succeed?; end
end

module Utils
  module AST
    class FormulaAST
      sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
      def process(*args, **options, &block); end
    end
  end
end

module Cask
  class Audit
    sig { returns(T::Boolean) }
    def new_cask?; end

    sig { returns(T::Boolean) }
    def strict?; end

    sig { returns(T::Boolean) }
    def signing?; end

    sig { returns(T::Boolean) }
    def online?; end

    sig { returns(T::Boolean) }
    def token_conflicts?; end
  end

  class Cask
    sig { returns(T::Boolean) }
    def loaded_from_api?; end
  end

  class Installer
    sig { returns(T::Boolean) }
    def binaries?; end

    sig { returns(T::Boolean) }
    def force?; end

    sig { returns(T::Boolean) }
    def adopt?; end

    sig { returns(T::Boolean) }
    def skip_cask_deps?; end

    sig { returns(T::Boolean) }
    def require_sha?; end

    sig { returns(T::Boolean) }
    def reinstall?; end

    sig { returns(T::Boolean) }
    def upgrade?; end

    sig { returns(T::Boolean) }
    def verbose?; end

    sig { returns(T::Boolean) }
    def zap?; end

    sig { returns(T::Boolean) }
    def installed_as_dependency?; end

    sig { returns(T::Boolean) }
    def installed_on_request?; end

    sig { returns(T::Boolean) }
    def quarantine?; end

    sig { returns(T::Boolean) }
    def quiet?; end
  end

  class DSL
    class Caveats < Base
      sig { returns(T::Boolean) }
      def discontinued?; end
    end

    sig { returns(T::Boolean) }
    def deprecated?; end

    sig { returns(T::Boolean) }
    def disabled?; end

    sig { returns(T::Boolean) }
    def livecheckable?; end

    sig { returns(T::Boolean) }
    def on_system_blocks_exist?; end

    sig { returns(T::Boolean) }
    def depends_on_set_in_block?; end
  end
end

module Homebrew
  class Cleanup
    sig { returns(T::Boolean) }
    def dry_run?; end

    sig { returns(T::Boolean) }
    def scrub?; end

    sig { returns(T::Boolean) }
    def prune?; end
  end

  class Service
    sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
    def bin(*args, **options, &block); end

    sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
    def etc(*args, **options, &block); end

    sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
    def libexec(*args, **options, &block); end

    sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
    def opt_bin(*args, **options, &block); end

    sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
    def opt_libexec(*args, **options, &block); end

    sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
    def opt_pkgshare(*args, **options, &block); end

    sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
    def opt_prefix(*args, **options, &block); end

    sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
    def opt_sbin(*args, **options, &block); end

    sig { params(args: T.untyped, options: T.untyped, block: T.untyped).returns(T.untyped) }
    def var(*args, **options, &block); end
  end
end
