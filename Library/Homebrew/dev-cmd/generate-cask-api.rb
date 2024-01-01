# typed: true
# frozen_string_literal: true

require "cli/parser"
require "cask/cask"
require "formula"

module Homebrew
  module_function

  sig { returns(CLI::Parser) }
  def generate_cask_api_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Generate `homebrew/cask` API data files for <#{HOMEBREW_API_WWW}>.
        The generated files are written to the current directory.
      EOS

      switch "-n", "--dry-run", description: "Generate API data without writing it to files."

      named_args :none
    end
  end

  CASK_JSON_TEMPLATE = <<~EOS
    ---
    layout: cask_json
    ---
    {{ content }}
  EOS

  def html_template(title)
    <<~EOS
      ---
      title: #{title}
      layout: cask
      ---
      {{ content }}
    EOS
  end

  def generate_cask_api
    args = generate_cask_api_args.parse

    tap = CoreCaskTap.instance
    raise TapUnavailableError, tap.name unless tap.installed?

    unless args.dry_run?
      directories = ["_data/cask", "api/cask", "api/cask-source", "cask"].freeze
      FileUtils.rm_rf directories
      FileUtils.mkdir_p directories
    end

    Homebrew.with_no_api_env do
      tap_migrations_json = JSON.dump(tap.tap_migrations)
      File.write("api/cask_tap_migrations.json", tap_migrations_json) unless args.dry_run?

      Cask::Cask.generating_hash!

      tap.cask_files.each do |path|
        cask = Cask::CaskLoader.load(path)
        name = cask.token
        json = JSON.pretty_generate(cask.to_hash_with_variations)
        cask_source = path.read
        html_template_name = html_template(name)

        unless args.dry_run?
          File.write("_data/cask/#{name}.json", "#{json}\n")
          File.write("api/cask/#{name}.json", CASK_JSON_TEMPLATE)
          File.write("api/cask-source/#{name}.rb", cask_source)
          File.write("cask/#{name}.html", html_template_name)
        end
      rescue
        onoe "Error while generating data for cask '#{path.stem}'."
        raise
      end
    end
  end
end
