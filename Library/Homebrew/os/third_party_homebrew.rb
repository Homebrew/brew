# typed: strict
# frozen_string_literal: true

module OS
  # Local evidence of a third-party Homebrew configuration and its support policy.
  class ThirdPartyHomebrew < T::Struct
    const :tier, T.any(Integer, Symbol), default: 3
    const :diagnostic, String, default: "A third-party tool manages this Homebrew installation or its package list."
    const :issues_url, T.nilable(String)
    const :check, T.nilable(Method)

    sig { returns(T::Boolean) }
    private_class_method def self.nix_homebrew?
      HOMEBREW_REPOSITORY.basename.to_s == ".homebrew-is-managed-by-nix" ||
        (HOMEBREW_PREFIX/".managed_by_nix_darwin").exist? ||
        (ENV["HOMEBREW_UPDATE_BEFORE"] == "nix" && ENV["HOMEBREW_UPDATE_AFTER"] == "nix")
    end

    sig { returns(T::Boolean) }
    private_class_method def self.nix_darwin?
      ENV.fetch("HOMEBREW_BUNDLE_FILE", "").start_with?("/nix/store/") ||
        ARGV.each_cons(2).any? { |arg, value| arg == "--file" && value.start_with?("/nix/store/") } ||
        ARGV.any? { |arg| arg.start_with?("--file=/nix/store/") }
    end

    configurations = {
      # https://github.com/zhaofengli/nix-homebrew/blob/aeb2069920742d0d6570089e8b3b8620050bacf2/modules/default.nix#L115-L125
      nix_homebrew: new(
        check:      method(:nix_homebrew?),
        issues_url: "https://github.com/zhaofengli/nix-homebrew/issues",
      ),
      # https://github.com/nix-darwin/nix-darwin/blob/8c62fba0854ba15c8917aed18894dbccb48a3777/modules/homebrew.nix#L76-L129
      nix_darwin:   new(
        check:      method(:nix_darwin?),
        issues_url: "https://github.com/nix-darwin/nix-darwin/issues",
      ),
    }
    CONFIGURATIONS = T.let(configurations.freeze, T::Hash[Symbol, ThirdPartyHomebrew])

    # Provisioners invoking regular brew inherit the installation's tier.
    # https://github.com/ansible-collections/community.general/blob/main/plugins/modules/homebrew.py
    # https://github.com/chef/chef/blob/main/lib/chef/provider/package/homebrew.rb
    # https://github.com/saltstack/salt/blob/master/salt/modules/mac_brew_pkg.py
    sig { returns(T.nilable(ThirdPartyHomebrew)) }
    def self.detect
      CONFIGURATIONS.each_value.find { |configuration| configuration.check&.call }
    end
  end
end
