# frozen_string_literal: true

require_relative "../command"
require_relative "../version_option"
require_relative "../rdoc"
require "fileutils"

class Gem::Commands::RdocCommand < Gem::Command
  include Gem::VersionOption

  def initialize
    super "rdoc", "Generates RDoc for pre-installed gems",
          version: Gem::Requirement.default,
          include_rdoc: false, include_ri: true, overwrite: false

    add_option("--all",
               "Generate RDoc/RI documentation for all",
               "installed gems") do |value, options|
      options[:all] = value
    end

    add_option("--[no-]rdoc",
               "Generate RDoc HTML") do |value, options|
      options[:include_rdoc] = value
    end

    add_option("--[no-]ri",
               "Generate RI data") do |value, options|
      options[:include_ri] = value
    end

    add_option("--[no-]overwrite",
               "Overwrite installed documents") do |value, options|
      options[:overwrite] = value
    end

    add_version_option
  end

  def arguments # :nodoc:
    "GEMNAME       gem to generate documentation for (unless --all)"
  end

  def defaults_str # :nodoc:
    "--version '#{Gem::Requirement.default}' --ri --no-overwrite"
  end

  def description # :nodoc:
    <<-DESC
The rdoc command builds documentation for installed gems.  By default
only documentation is built using rdoc, but additional types of
documentation may be built through rubygems plugins and the
Gem.post_installs hook.

Use --overwrite to force rebuilding of documentation.
    DESC
  end

  def usage # :nodoc:
    "#{program_name} [args]"
  end

  def execute
    specs = if options[:all]
      Gem::Specification.to_a
    else
      get_all_gem_names.map do |name|
        Gem::Specification.find_by_name name, options[:version]
      end.flatten.uniq
    end

    if specs.empty?
      alert_error "No matching gems found"
      terminate_interaction 1
    end

    specs.each do |spec|
      doc = Gem::RDoc.new spec, options[:include_rdoc], options[:include_ri]

      doc.force = options[:overwrite]

      if options[:overwrite]
        FileUtils.rm_rf File.join(spec.doc_dir, "ri")
        FileUtils.rm_rf File.join(spec.doc_dir, "rdoc")
      end

      doc.generate
    end
  end
end
