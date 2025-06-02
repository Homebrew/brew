# frozen_string_literal: true

require_relative "local_remote_options"
require_relative "spec_fetcher"
require_relative "version_option"
require_relative "text"

module Gem::QueryUtils
  include Gem::Text
  include Gem::LocalRemoteOptions
  include Gem::VersionOption

  def add_query_options
    add_option("-i", "--[no-]installed",
               "Check for installed gem") do |value, options|
      options[:installed] = value
    end

    add_option("-I", "Equivalent to --no-installed") do |_value, options|
      options[:installed] = false
    end

    add_version_option command, "for use with --installed"

    add_option("-d", "--[no-]details",
               "Display detailed information of gem(s)") do |value, options|
      options[:details] = value
    end

    add_option("--[no-]versions",
               "Display only gem names") do |value, options|
      options[:versions] = value
      options[:details] = false unless value
    end

    add_option("-a", "--all",
               "Display all gem versions") do |value, options|
      options[:all] = value
    end

    add_option("-e", "--exact",
               "Name of gem(s) to query on matches the",
               "provided STRING") do |value, options|
      options[:exact] = value
    end

    add_option("--[no-]prerelease",
               "Display prerelease versions") do |value, options|
      options[:prerelease] = value
    end

    add_local_remote_options
  end

  def defaults_str # :nodoc:
    "--local --no-details --versions --no-installed"
  end

  def execute
    gem_names = if args.empty?
      [options[:name]]
    else
      options[:exact] ? args.map {|arg| /\A#{Regexp.escape(arg)}\Z/ } : args.map {|arg| /#{arg}/i }
    end

    terminate_interaction(check_installed_gems(gem_names)) if check_installed_gems?

    gem_names.each {|n| show_gems(n) }
  end

  private

  def check_installed_gems(gem_names)
    exit_code = 0

    if args.empty? && !gem_name?
      alert_error "You must specify a gem name"
      exit_code = 4
    elsif gem_names.count > 1
      alert_error "You must specify only ONE gem!"
      exit_code = 4
    else
      installed = installed?(gem_names.first, options[:version])
      installed = !installed unless options[:installed]

      say(installed)
      exit_code = 1 unless installed
    end

    exit_code
  end

  def check_installed_gems?
    !options[:installed].nil?
  end

  def gem_name?
    !options[:name].nil?
  end

  def prerelease
    options[:prerelease]
  end

  def show_prereleases?
    prerelease.nil? || prerelease
  end

  def args
    options[:args].to_a
  end

  def display_header(type)
    if (ui.outs.tty? && Gem.configuration.verbose) || both?
      say
      say "*** #{type} GEMS ***"
      say
    end
  end

  # Guts of original execute
  def show_gems(name)
    show_local_gems(name)  if local?
    show_remote_gems(name) if remote?
  end

  def show_local_gems(name, req = Gem::Requirement.default)
    display_header("LOCAL")

    specs = Gem::Specification.find_all do |s|
      name_matches = name ? s.name =~ name : true
      version_matches = show_prereleases? || !s.version.prerelease?

      name_matches && version_matches
    end.uniq(&:full_name)

    spec_tuples = specs.map do |spec|
      [spec.name_tuple, spec]
    end

    output_query_results(spec_tuples)
  end

  def show_remote_gems(name)
    display_header("REMOTE")

    fetcher = Gem::SpecFetcher.fetcher

    spec_tuples = if name.nil?
      fetcher.detect(specs_type) { true }
    else
      fetcher.detect(specs_type) do |name_tuple|
        name === name_tuple.name && options[:version].satisfied_by?(name_tuple.version)
      end
    end

    output_query_results(spec_tuples)
  end

  def specs_type
    if options[:all] || options[:version].specific?
      if options[:prerelease]
        :complete
      else
        :released
      end
    elsif options[:prerelease]
      :prerelease
    else
      :latest
    end
  end

  ##
  # Check if gem +name+ version +version+ is installed.

  def installed?(name, req = Gem::Requirement.default)
    Gem::Specification.any? {|s| s.name =~ name && req =~ s.version }
  end

  def output_query_results(spec_tuples)
    output = []
    versions = Hash.new {|h,name| h[name] = [] }

    spec_tuples.each do |spec_tuple, source|
      versions[spec_tuple.name] << [spec_tuple, source]
    end

    versions = versions.sort_by do |(n,_),_|
      n.downcase
    end

    output_versions output, versions

    say output.join(options[:details] ? "\n\n" : "\n")
  end

  def output_versions(output, versions)
    versions.each do |_gem_name, matching_tuples|
      matching_tuples = matching_tuples.sort_by {|n,_| n.version }.reverse

      platforms = Hash.new {|h,version| h[version] = [] }

      matching_tuples.each do |n, _|
        platforms[n.version] << n.platform if n.platform
      end

      seen = {}

      matching_tuples.delete_if do |n,_|
        if seen[n.version]
          true
        else
          seen[n.version] = true
          false
        end
      end

      output << clean_text(make_entry(matching_tuples, platforms))
    end
  end

  def entry_details(entry, detail_tuple, specs, platforms)
    return unless options[:details]

    name_tuple, spec = detail_tuple

    spec = spec.fetch_spec(name_tuple)if spec.respond_to?(:fetch_spec)

    entry << "\n"

    spec_platforms   entry, platforms
    spec_authors     entry, spec
    spec_homepage    entry, spec
    spec_license     entry, spec
    spec_loaded_from entry, spec, specs
    spec_summary     entry, spec
  end

  def entry_versions(entry, name_tuples, platforms, specs)
    return unless options[:versions]

    list =
      if platforms.empty? || options[:details]
        name_tuples.map(&:version).uniq
      else
        platforms.sort.reverse.map do |version, pls|
          out = version.to_s

          if options[:domain] == :local
            default = specs.any? do |s|
              !s.is_a?(Gem::Source) && s.version == version && s.default_gem?
            end
            out = "default: #{out}" if default
          end

          if pls != [Gem::Platform::RUBY]
            platform_list = [pls.delete(Gem::Platform::RUBY), *pls.sort].compact
            out = platform_list.unshift(out).join(" ")
          end

          out
        end
      end

    entry << " (#{list.join ", "})"
  end

  def make_entry(entry_tuples, platforms)
    detail_tuple = entry_tuples.first

    name_tuples, specs = entry_tuples.flatten.partition do |item|
      Gem::NameTuple === item
    end

    entry = [name_tuples.first.name]

    entry_versions(entry, name_tuples, platforms, specs)
    entry_details(entry, detail_tuple, specs, platforms)

    entry.join
  end

  def spec_authors(entry, spec)
    authors = "Author#{spec.authors.length > 1 ? "s" : ""}: ".dup
    authors << spec.authors.join(", ")
    entry << format_text(authors, 68, 4)
  end

  def spec_homepage(entry, spec)
    return if spec.homepage.nil? || spec.homepage.empty?

    entry << "\n" << format_text("Homepage: #{spec.homepage}", 68, 4)
  end

  def spec_license(entry, spec)
    return if spec.license.nil? || spec.license.empty?

    licenses = "License#{spec.licenses.length > 1 ? "s" : ""}: ".dup
    licenses << spec.licenses.join(", ")
    entry << "\n" << format_text(licenses, 68, 4)
  end

  def spec_loaded_from(entry, spec, specs)
    return unless spec.loaded_from

    if specs.length == 1
      default = spec.default_gem? ? " (default)" : nil
      entry << "\n" << "    Installed at#{default}: #{spec.base_dir}"
    else
      label = "Installed at"
      specs.each do |s|
        version = s.version.to_s
        default = ", default" if s.default_gem?
        entry << "\n" << "    #{label} (#{version}#{default}): #{s.base_dir}"
        label = " " * label.length
      end
    end
  end

  def spec_platforms(entry, platforms)
    non_ruby = platforms.any? do |_, pls|
      pls.any? {|pl| pl != Gem::Platform::RUBY }
    end

    return unless non_ruby

    if platforms.length == 1
      title = platforms.values.length == 1 ? "Platform" : "Platforms"
      entry << "    #{title}: #{platforms.values.sort.join(", ")}\n"
    else
      entry << "    Platforms:\n"

      sorted_platforms = platforms.sort

      sorted_platforms.each do |version, pls|
        label = "        #{version}: "
        data = format_text pls.sort.join(", "), 68, label.length
        data[0, label.length] = label
        entry << data << "\n"
      end
    end
  end

  def spec_summary(entry, spec)
    summary = truncate_text(spec.summary, "the summary for #{spec.full_name}")
    entry << "\n\n" << format_text(summary, 68, 4)
  end
end
