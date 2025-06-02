# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module Cleanup
      extend T::Helpers

      requires_ancestor { DinrusBrew::Cleanup }

      sig { returns(T::Boolean) }
      def use_system_ruby?
        return false if DinrusBrew::EnvConfig.force_vendor_ruby?

        rubies = [which("ruby"), which("ruby", ORIGINAL_PATHS)].compact
        system_ruby = Pathname.new("/usr/bin/ruby")
        rubies << system_ruby if system_ruby.exist?

        check_ruby_version = DINRUSBREW_LIBRARY_PATH/"utils/ruby_check_version_script.rb"
        rubies.uniq.any? do |ruby|
          quiet_system ruby, "--enable-frozen-string-literal", "--disable=gems,did_you_mean,rubyopt",
                       check_ruby_version, RUBY_VERSION
        end
      end
    end
  end
end

DinrusBrew::Cleanup.prepend(OS::Linux::Cleanup)
