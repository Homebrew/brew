# frozen_string_literal: true

module Bundler
  module GemHelpers
    GENERIC_CACHE = { Gem::Platform::RUBY => Gem::Platform::RUBY } # rubocop:disable Style/MutableConstant
    GENERICS = [
      [Gem::Platform.new("java"), Gem::Platform.new("java")],
      [Gem::Platform.new("mswin32"), Gem::Platform.new("mswin32")],
      [Gem::Platform.new("mswin64"), Gem::Platform.new("mswin64")],
      [Gem::Platform.new("universal-mingw32"), Gem::Platform.new("universal-mingw32")],
      [Gem::Platform.new("x64-mingw32"), Gem::Platform.new("x64-mingw32")],
      [Gem::Platform.new("x86_64-mingw32"), Gem::Platform.new("x64-mingw32")],
      [Gem::Platform.new("x64-mingw-ucrt"), Gem::Platform.new("x64-mingw-ucrt")],
      [Gem::Platform.new("mingw32"), Gem::Platform.new("x86-mingw32")],
    ].freeze

    def generic(p)
      GENERIC_CACHE[p] ||= begin
        _, found = GENERICS.find do |match, _generic|
          p.os == match.os && (!match.cpu || p.cpu == match.cpu)
        end
        found || Gem::Platform::RUBY
      end
    end
    module_function :generic

    def generic_local_platform
      generic(local_platform)
    end
    module_function :generic_local_platform

    def local_platform
      Bundler.local_platform
    end
    module_function :local_platform

    def platform_specificity_match(spec_platform, user_platform)
      spec_platform = Gem::Platform.new(spec_platform)

      PlatformMatch.specificity_score(spec_platform, user_platform)
    end
    module_function :platform_specificity_match

    def select_best_platform_match(specs, platform)
      matching = specs.select {|spec| spec.match_platform(platform) }

      sort_best_platform_match(matching, platform)
    end
    module_function :select_best_platform_match

    def sort_best_platform_match(matching, platform)
      exact = matching.select {|spec| spec.platform == platform }
      return exact if exact.any?

      sorted_matching = matching.sort_by {|spec| platform_specificity_match(spec.platform, platform) }
      exemplary_spec = sorted_matching.first

      sorted_matching.take_while {|spec| same_specificity(platform, spec, exemplary_spec) && same_deps(spec, exemplary_spec) }
    end
    module_function :sort_best_platform_match

    class PlatformMatch
      def self.specificity_score(spec_platform, user_platform)
        return -1 if spec_platform == user_platform
        return 1_000_000 if spec_platform.nil? || spec_platform == Gem::Platform::RUBY || user_platform == Gem::Platform::RUBY

        os_match(spec_platform, user_platform) +
          cpu_match(spec_platform, user_platform) * 10 +
          platform_version_match(spec_platform, user_platform) * 100
      end

      def self.os_match(spec_platform, user_platform)
        if spec_platform.os == user_platform.os
          0
        else
          1
        end
      end

      def self.cpu_match(spec_platform, user_platform)
        if spec_platform.cpu == user_platform.cpu
          0
        elsif spec_platform.cpu == "arm" && user_platform.cpu.to_s.start_with?("arm")
          0
        elsif spec_platform.cpu.nil? || spec_platform.cpu == "universal"
          1
        else
          2
        end
      end

      def self.platform_version_match(spec_platform, user_platform)
        if spec_platform.version == user_platform.version
          0
        elsif spec_platform.version.nil?
          1
        else
          2
        end
      end
    end

    def same_specificity(platform, spec, exemplary_spec)
      platform_specificity_match(spec.platform, platform) == platform_specificity_match(exemplary_spec.platform, platform)
    end
    module_function :same_specificity

    def same_deps(spec, exemplary_spec)
      same_runtime_deps = spec.dependencies.sort == exemplary_spec.dependencies.sort
      return same_runtime_deps unless spec.is_a?(Gem::Specification) && exemplary_spec.is_a?(Gem::Specification)

      same_metadata_deps = spec.required_ruby_version == exemplary_spec.required_ruby_version && spec.required_rubygems_version == exemplary_spec.required_rubygems_version
      same_runtime_deps && same_metadata_deps
    end
    module_function :same_deps
  end
end
