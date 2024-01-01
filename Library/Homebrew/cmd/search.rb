# typed: true
# frozen_string_literal: true

require "formula"
require "missing_formula"
require "descriptions"
require "cli/parser"
require "search"

module Homebrew
  module_function

  PACKAGE_MANAGERS = {
    repology:  ->(query) { "https://repology.org/projects/?search=#{query}" },
    macports:  ->(query) { "https://ports.macports.org/search/?q=#{query}" },
    fink:      ->(query) { "https://pdb.finkproject.org/pdb/browse.php?summary=#{query}" },
    opensuse:  ->(query) { "https://software.opensuse.org/search?q=#{query}" },
    fedora:    ->(query) { "https://packages.fedoraproject.org/search?query=#{query}" },
    archlinux: ->(query) { "https://archlinux.org/packages/?q=#{query}" },
    debian:    lambda { |query|
      "https://packages.debian.org/search?keywords=#{query}&searchon=names&suite=all&section=all"
    },
    ubuntu:    lambda { |query|
      "https://packages.ubuntu.com/search?keywords=#{query}&searchon=names&suite=all&section=all"
    },
  }.freeze

  sig { returns(CLI::Parser) }
  def search_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Perform a substring search of cask tokens and formula names for <text>. If <text>
        is flanked by slashes, it is interpreted as a regular expression.
      EOS
      switch "--formula", "--formulae",
             description: "Search for formulae."
      switch "--cask", "--casks",
             description: "Search for casks."
      switch "--desc",
             description: "Search for formulae with a description matching <text> and casks with " \
                          "a name or description matching <text>."
      switch "--eval-all",
             depends_on:  "--desc",
             description: "Evaluate all available formulae and casks, whether installed or not, to search their " \
                          "descriptions. Implied if `HOMEBREW_EVAL_ALL` is set."
      switch "--pull-request",
             description: "Search for GitHub pull requests containing <text>."
      switch "--open",
             depends_on:  "--pull-request",
             description: "Search for only open GitHub pull requests."
      switch "--closed",
             depends_on:  "--pull-request",
             description: "Search for only closed GitHub pull requests."
      package_manager_switches = PACKAGE_MANAGERS.keys.map { |name| "--#{name}" }
      package_manager_switches.each do |s|
        switch s,
               description: "Search for <text> in the given database."
      end

      conflicts "--desc", "--pull-request"
      conflicts "--open", "--closed"
      conflicts(*package_manager_switches)

      named_args :text_or_regex, min: 1
    end
  end

  def search
    args = search_args.parse

    return if search_package_manager(args)

    query = args.named.join(" ")
    string_or_regex = Search.query_regexp(query)

    if args.desc?
      if !args.eval_all? && !Homebrew::EnvConfig.eval_all?
        raise UsageError, "`brew search --desc` needs `--eval-all` passed or `HOMEBREW_EVAL_ALL` set!"
      end

      Search.search_descriptions(string_or_regex, args)
    elsif args.pull_request?
      search_pull_requests(query, args)
    else
      formulae, casks = Search.search_names(string_or_regex, args)
      print_results(formulae, casks, query)
    end

    puts "Use `brew desc` to list packages with a short description." if args.verbose?

    print_regex_help(args)
  end

  def print_regex_help(args)
    return unless $stdout.tty?

    metacharacters = %w[\\ | ( ) [ ] { } ^ $ * + ?].freeze
    return unless metacharacters.any? do |char|
      args.named.any? do |arg|
        arg.include?(char) && !arg.start_with?("/")
      end
    end

    opoo <<~EOS
      Did you mean to perform a regular expression search?
      Surround your query with /slashes/ to search locally by regex.
    EOS
  end

  def search_package_manager(args)
    package_manager = PACKAGE_MANAGERS.find { |name,| args[:"#{name}?"] }
    return false if package_manager.nil?

    _, url = package_manager
    exec_browser url.call(URI.encode_www_form_component(args.named.join(" ")))
    true
  end

  def search_pull_requests(query, args)
    only = if args.open? && !args.closed?
      "open"
    elsif args.closed? && !args.open?
      "closed"
    end

    GitHub.print_pull_requests_matching(query, only)
  end

  def print_results(all_formulae, all_casks, query)
    count = all_formulae.size + all_casks.size

    if all_formulae.any?
      if $stdout.tty?
        ohai "Formulae", Formatter.columns(all_formulae)
      else
        puts all_formulae
      end
    end
    puts if all_formulae.any? && all_casks.any?
    if all_casks.any?
      if $stdout.tty?
        ohai "Casks", Formatter.columns(all_casks)
      else
        puts all_casks
      end
    end

    print_missing_formula_help(query, count.positive?) if all_casks.exclude?(query)

    odie "No formulae or casks found for #{query.inspect}." if count.zero?
  end

  def print_missing_formula_help(query, found_matches)
    return unless $stdout.tty?

    reason = MissingFormula.reason(query, silent: true)
    return if reason.nil?

    if found_matches
      puts
      puts "If you meant #{query.inspect} specifically:"
    end
    puts reason
  end
end
