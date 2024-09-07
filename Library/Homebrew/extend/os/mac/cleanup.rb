# typed: strict
# frozen_string_literal: true

module Homebrew
  class Cleanup
    undef use_system_ruby?

    sig { returns(T::Boolean) }
    def use_system_ruby?
      return false if Homebrew::EnvConfig.force_vendor_ruby?

      Homebrew::EnvConfig.developer? && ENV["HOMEBREW_USE_RUBY_FROM_PATH"].present?
    end
  end
end
