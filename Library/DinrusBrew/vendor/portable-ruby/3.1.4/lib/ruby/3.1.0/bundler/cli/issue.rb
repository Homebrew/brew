# frozen_string_literal: true

require "rbconfig"

module Bundler
  class CLI::Issue
    def run
      Bundler.ui.info <<-EOS.gsub(/^ {8}/, "")
        Did you find an issue with Bundler? Before filing a new issue,
        be sure to check out these resources:

        1. Check out our troubleshooting guide for quick fixes to common issues:
        https://github.com/rubygems/rubygems/blob/master/bundler/doc/TROUBLESHOOTING.md

        2. Instructions for common Bundler uses can be found on the documentation
        site: https://bundler.io/

        3. Information about each Bundler command can be found in the Bundler
        man pages: https://bundler.io/man/bundle.1.html

        Hopefully the troubleshooting steps above resolved your problem!  If things
        still aren't working the way you expect them to, please let us know so
        that we can diagnose and help fix the problem you're having, by filling
        in the new issue form located at
        https://github.com/rubygems/rubygems/issues/new?labels=Bundler&template=bundler-related-issue.md,
        and copy and pasting the information below.

      EOS

      Bundler.ui.info Bundler::Env.report

      Bundler.ui.info "\n## Bundle Doctor"
      doctor
    end

    def doctor
      require_relative "doctor"
      Bundler::CLI::Doctor.new({}).run
    end
  end
end
