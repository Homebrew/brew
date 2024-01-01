# typed: true
# frozen_string_literal: true

module Homebrew
  class Cleanup
    undef use_system_ruby?

    def use_system_ruby?
      return false if Homebrew::EnvConfig.force_vendor_ruby?

      rubies = [which("ruby"), which("ruby", ORIGINAL_PATHS)].compact
      system_ruby = Pathname.new("/usr/bin/ruby")
      rubies << system_ruby if system_ruby.exist?

      check_ruby_version = HOMEBREW_LIBRARY_PATH/"utils/ruby_check_version_script.rb"
      rubies.uniq.any? do |ruby|
        quiet_system ruby, "--enable-frozen-string-literal", "--disable=gems,did_you_mean,rubyopt",
                     check_ruby_version, RUBY_VERSION
      end
    end
  end
end
