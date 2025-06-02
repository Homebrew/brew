# frozen_string_literal: true

module Bundler
  # Returns current version of Ruby
  #
  # @return [CurrentRuby] Current version of Ruby
  def self.current_ruby
    @current_ruby ||= CurrentRuby.new
  end

  class CurrentRuby
    KNOWN_MINOR_VERSIONS = %w[
      1.8
      1.9
      2.0
      2.1
      2.2
      2.3
      2.4
      2.5
      2.6
      2.7
      3.0
      3.1
    ].freeze

    KNOWN_MAJOR_VERSIONS = KNOWN_MINOR_VERSIONS.map {|v| v.split(".", 2).first }.uniq.freeze

    KNOWN_PLATFORMS = %w[
      jruby
      maglev
      mingw
      mri
      mswin
      mswin64
      rbx
      ruby
      truffleruby
      windows
      x64_mingw
    ].freeze

    def ruby?
      return true if Bundler::GemHelpers.generic_local_platform == Gem::Platform::RUBY

      !windows? && (RUBY_ENGINE == "ruby" || RUBY_ENGINE == "rbx" || RUBY_ENGINE == "maglev" || RUBY_ENGINE == "truffleruby")
    end

    def mri?
      !windows? && RUBY_ENGINE == "ruby"
    end

    def rbx?
      ruby? && RUBY_ENGINE == "rbx"
    end

    def jruby?
      RUBY_ENGINE == "jruby"
    end

    def maglev?
      RUBY_ENGINE == "maglev"
    end

    def truffleruby?
      RUBY_ENGINE == "truffleruby"
    end

    def windows?
      Gem.win_platform?
    end

    def mswin?
      # For backwards compatibility
      windows?

      # TODO: This should correctly be:
      # windows? && Bundler.local_platform != Gem::Platform::RUBY && Bundler.local_platform.os == "mswin32" && Bundler.local_platform.cpu == "x86"
    end

    def mswin64?
      windows? && Bundler.local_platform != Gem::Platform::RUBY && Bundler.local_platform.os == "mswin64" && Bundler.local_platform.cpu == "x64"
    end

    def mingw?
      windows? && Bundler.local_platform != Gem::Platform::RUBY && Bundler.local_platform.os == "mingw32" && Bundler.local_platform.cpu != "x64"
    end

    def x64_mingw?
      Gem.win_platform? && Bundler.local_platform != Gem::Platform::RUBY && Bundler.local_platform.os.start_with?("mingw") && Bundler.local_platform.cpu == "x64"
    end

    (KNOWN_MINOR_VERSIONS + KNOWN_MAJOR_VERSIONS).each do |version|
      trimmed_version = version.tr(".", "")
      define_method(:"on_#{trimmed_version}?") do
        RUBY_VERSION.start_with?("#{version}.")
      end

      KNOWN_PLATFORMS.each do |platform|
        define_method(:"#{platform}_#{trimmed_version}?") do
          send(:"#{platform}?") && send(:"on_#{trimmed_version}?")
        end
      end
    end
  end
end
