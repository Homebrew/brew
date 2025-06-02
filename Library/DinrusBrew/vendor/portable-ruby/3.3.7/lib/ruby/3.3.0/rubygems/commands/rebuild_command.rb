# frozen_string_literal: true

require "date"
require "digest"
require "fileutils"
require "tmpdir"
require_relative "../gemspec_helpers"
require_relative "../package"

class Gem::Commands::RebuildCommand < Gem::Command
  include Gem::GemspecHelpers

  DATE_FORMAT = "%Y-%m-%d %H:%M:%S.%N Z"

  def initialize
    super "rebuild", "Attempt to reproduce a build of a gem."

    add_option "--diff", "If the files don't match, compare them using diffoscope." do |_value, options|
      options[:diff] = true
    end

    add_option "--force", "Skip validation of the spec." do |_value, options|
      options[:force] = true
    end

    add_option "--strict", "Consider warnings as errors when validating the spec." do |_value, options|
      options[:strict] = true
    end

    add_option "--source GEM_SOURCE", "Specify the source to download the gem from." do |value, options|
      options[:source] = value
    end

    add_option "--original GEM_FILE", "Specify a local file to compare against (instead of downloading it)." do |value, options|
      options[:original_gem_file] = value
    end

    add_option "--gemspec GEMSPEC_FILE", "Specify the name of the gemspec file." do |value, options|
      options[:gemspec_file] = value
    end

    add_option "-C PATH", "Run as if gem build was started in <PATH> instead of the current working directory." do |value, options|
      options[:build_path] = value
    end
  end

  def arguments # :nodoc:
    "GEM_NAME      gem name on gem server\n" \
    "GEM_VERSION   gem version you are attempting to rebuild"
  end

  def description # :nodoc:
    <<-EOF
The rebuild command allows you to (attempt to) reproduce a build of a gem
from a ruby gemspec.

This command assumes the gemspec can be built with the `gem build` command.
If you use any of `gem build`, `rake build`, or`rake release` in the
build/release process for a gem, it is a potential candidate.

You will need to match the RubyGems version used, since this is included in
the Gem metadata.

If the gem includes lockfiles (e.g. Gemfile.lock) and similar, it will
require more effort to reproduce a build. For example, it might require
more precisely matched versions of Ruby and/or Bundler to be used.
    EOF
  end

  def usage # :nodoc:
    "#{program_name} GEM_NAME GEM_VERSION"
  end

  def execute
    gem_name, gem_version = get_gem_name_and_version

    old_dir, new_dir = prep_dirs

    gem_filename = "#{gem_name}-#{gem_version}.gem"
    old_file = File.join(old_dir, gem_filename)
    new_file = File.join(new_dir, gem_filename)

    if options[:original_gem_file]
      FileUtils.copy_file(options[:original_gem_file], old_file)
    else
      download_gem(gem_name, gem_version, old_file)
    end

    rg_version = rubygems_version(old_file)
    unless rg_version == Gem::VERSION
      alert_error <<-EOF
You need to use the same RubyGems version #{gem_name} v#{gem_version} was built with.

#{gem_name} v#{gem_version} was built using RubyGems v#{rg_version}.
Gem files include the version of RubyGems used to build them.
This means in order to reproduce #{gem_filename}, you must also use RubyGems v#{rg_version}.

You're using RubyGems v#{Gem::VERSION}.

Please install RubyGems v#{rg_version} and try again.
      EOF
      terminate_interaction 1
    end

    source_date_epoch = get_timestamp(old_file).to_s

    if build_path = options[:build_path]
      Dir.chdir(build_path) { build_gem(gem_name, source_date_epoch, new_file) }
    else
      build_gem(gem_name, source_date_epoch, new_file)
    end

    compare(source_date_epoch, old_file, new_file)
  end

  private

  def sha256(file)
    Digest::SHA256.hexdigest(Gem.read_binary(file))
  end

  def get_timestamp(file)
    mtime = nil
    File.open(file, Gem.binary_mode) do |f|
      Gem::Package::TarReader.new(f) do |tar|
        mtime = tar.seek("metadata.gz") {|tf| tf.header.mtime }
      end
    end

    mtime
  end

  def compare(source_date_epoch, old_file, new_file)
    date = Time.at(source_date_epoch.to_i).strftime("%F %T %Z")

    old_hash = sha256(old_file)
    new_hash = sha256(new_file)

    say
    say "Built at: #{date} (#{source_date_epoch})"
    say "Original build saved to:   #{old_file}"
    say "Reproduced build saved to: #{new_file}"
    say "Working directory: #{options[:build_path] || Dir.pwd}"
    say
    say "Hash comparison:"
    say "  #{old_hash}\t#{old_file}"
    say "  #{new_hash}\t#{new_file}"
    say

    if old_hash == new_hash
      say "SUCCESS - original and rebuild hashes matched"
    else
      say "FAILURE - original and rebuild hashes did not match"
      say

      if options[:diff]
        if system("diffoscope", old_file, new_file).nil?
          alert_error "error: could not find `diffoscope` executable"
        end
      else
        say "Pass --diff for more details (requires diffoscope to be installed)."
      end

      terminate_interaction 1
    end
  end

  def prep_dirs
    rebuild_dir = Dir.mktmpdir("gem_rebuild")
    old_dir = File.join(rebuild_dir, "old")
    new_dir = File.join(rebuild_dir, "new")

    FileUtils.mkdir_p(old_dir)
    FileUtils.mkdir_p(new_dir)

    [old_dir, new_dir]
  end

  def get_gem_name_and_version
    args = options[:args] || []
    if args.length == 2
      gem_name, gem_version = args
    elsif args.length > 2
      raise Gem::CommandLineError, "Too many arguments"
    else
      raise Gem::CommandLineError, "Expected GEM_NAME and GEM_VERSION arguments (gem rebuild GEM_NAME GEM_VERSION)"
    end

    [gem_name, gem_version]
  end

  def build_gem(gem_name, source_date_epoch, output_file)
    gemspec = options[:gemspec_file] || find_gemspec("#{gem_name}.gemspec")

    if gemspec
      build_package(gemspec, source_date_epoch, output_file)
    else
      alert_error error_message(gem_name)
      terminate_interaction(1)
    end
  end

  def build_package(gemspec, source_date_epoch, output_file)
    with_source_date_epoch(source_date_epoch) do
      spec = Gem::Specification.load(gemspec)
      if spec
        Gem::Package.build(
          spec,
          options[:force],
          options[:strict],
          output_file
        )
      else
        alert_error "Error loading gemspec. Aborting."
        terminate_interaction 1
      end
    end
  end

  def with_source_date_epoch(source_date_epoch)
    old_sde = ENV["SOURCE_DATE_EPOCH"]
    ENV["SOURCE_DATE_EPOCH"] = source_date_epoch.to_s

    yield
  ensure
    ENV["SOURCE_DATE_EPOCH"] = old_sde
  end

  def error_message(gem_name)
    if gem_name
      "Couldn't find a gemspec file matching '#{gem_name}' in #{Dir.pwd}"
    else
      "Couldn't find a gemspec file in #{Dir.pwd}"
    end
  end

  def download_gem(gem_name, gem_version, old_file)
    # This code was based loosely off the `gem fetch` command.
    version = "= #{gem_version}"
    dep = Gem::Dependency.new gem_name, version

    specs_and_sources, errors =
      Gem::SpecFetcher.fetcher.spec_for_dependency dep

    # There should never be more than one item in specs_and_sources,
    # since we search for an exact version.
    spec, source = specs_and_sources[0]

    if spec.nil?
      show_lookup_failure gem_name, version, errors, options[:domain]
      terminate_interaction 1
    end

    download_path = source.download spec

    FileUtils.move(download_path, old_file)

    say "Downloaded #{gem_name} version #{gem_version} as #{old_file}."
  end

  def rubygems_version(gem_file)
    Gem::Package.new(gem_file).spec.rubygems_version
  end
end
