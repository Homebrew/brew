# frozen_string_literal: true

require_relative "../command"
require_relative "../gemspec_helpers"
require_relative "../package"
require_relative "../version_option"

class Gem::Commands::BuildCommand < Gem::Command
  include Gem::VersionOption
  include Gem::GemspecHelpers

  def initialize
    super "build", "Build a gem from a gemspec"

    add_platform_option

    add_option "--force", "skip validation of the spec" do |_value, options|
      options[:force] = true
    end

    add_option "--strict", "consider warnings as errors when validating the spec" do |_value, options|
      options[:strict] = true
    end

    add_option "-o", "--output FILE", "output gem with the given filename" do |value, options|
      options[:output] = value
    end

    add_option "-C PATH", "Run as if gem build was started in <PATH> instead of the current working directory." do |value, options|
      options[:build_path] = value
    end
    deprecate_option "-C",
                     version: "4.0",
                     extra_msg: "-C is a global flag now. Use `gem -C PATH build GEMSPEC_FILE [options]` instead"
  end

  def arguments # :nodoc:
    "GEMSPEC_FILE  gemspec file name to build a gem for"
  end

  def description # :nodoc:
    <<-EOF
The build command allows you to create a gem from a ruby gemspec.

The best way to build a gem is to use a Rakefile and the Gem::PackageTask
which ships with RubyGems.

The gemspec can either be created by hand or extracted from an existing gem
with gem spec:

  $ gem unpack my_gem-1.0.gem
  Unpacked gem: '.../my_gem-1.0'
  $ gem spec my_gem-1.0.gem --ruby > my_gem-1.0/my_gem-1.0.gemspec
  $ cd my_gem-1.0
  [edit gem contents]
  $ gem build my_gem-1.0.gemspec

Gems can be saved to a specified filename with the output option:

  $ gem build my_gem-1.0.gemspec --output=release.gem

    EOF
  end

  def usage # :nodoc:
    "#{program_name} GEMSPEC_FILE"
  end

  def execute
    if build_path = options[:build_path]
      Dir.chdir(build_path) { build_gem }
      return
    end

    build_gem
  end

  private

  def build_gem
    gemspec = resolve_gem_name

    if gemspec
      build_package(gemspec)
    else
      alert_error error_message
      terminate_interaction(1)
    end
  end

  def build_package(gemspec)
    spec = Gem::Specification.load(gemspec)
    if spec
      Gem::Package.build(
        spec,
        options[:force],
        options[:strict],
        options[:output]
      )
    else
      alert_error "Error loading gemspec. Aborting."
      terminate_interaction 1
    end
  end

  def resolve_gem_name
    return find_gemspec unless gem_name

    if File.exist?(gem_name)
      gem_name
    else
      find_gemspec("#{gem_name}.gemspec") || find_gemspec(gem_name)
    end
  end

  def error_message
    if gem_name
      "Couldn't find a gemspec file matching '#{gem_name}' in #{Dir.pwd}"
    else
      "Couldn't find a gemspec file in #{Dir.pwd}"
    end
  end

  def gem_name
    get_one_optional_argument
  end
end
