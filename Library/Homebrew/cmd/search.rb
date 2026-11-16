# typed: strict
# frozen_string_literal: true

require "utils/browser"

require "abstract_command"
require "formula"
require "missing_formula"
require "search"

module Homebrew
  module Cmd
    class SearchCmd < AbstractCommand
      PACKAGE_MANAGERS = T.let({
        alpine:    ->(query) { "https://pkgs.alpinelinux.org/packages?name=#{query}" },
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
      }.freeze, T::Hash[Symbol, T.proc.params(query: String).returns(String)])

      cmd_args do
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
               description: "Evaluate all available formulae and casks, whether installed or not, to search their " \
                            "descriptions.",
               env:         :eval_all,
               replacement: "the default trusted-tap behaviour",
               odisabled:   true
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

      sig { override.void }
      def run
        return if search_package_manager!

        query = args.named.join(" ")
        string_or_regex = Search.query_regexp(query)

        if args.desc?
          Search.search_descriptions(string_or_regex, args, show_missing: true)
        elsif args.pull_request?
          only = if args.open? && !args.closed?
            "open"
          elsif args.closed? && !args.open?
            "closed"
          end

          GitHub.print_pull_requests_matching(query, only)
        else
          formulae, casks = Search.search_names(string_or_regex, args)
          count = formulae.size + casks.size

          if formulae.any?
            if $stdout.tty? && !args.quiet?
              ohai "Formulae", Formatter.columns(formulae)
            else
              puts formulae
            end
          end
          puts if formulae.any? && casks.any?
          if casks.any?
            if $stdout.tty? && !args.quiet?
              ohai "Casks", Formatter.columns(casks)
            else
              puts casks
            end
          end

          print_missing_formula_help(query, count.positive?) if casks.exclude?(query)

          odie "No formulae or casks found for #{query.inspect}." if count.zero?
        end

        puts "Use `brew desc` to list packages with a short description." if args.verbose?

        print_regex_help
      end

      sig { params(query: String, found_matches: T::Boolean).void }
      def print_missing_formula_help(query, found_matches)
        return unless $stdout.tty?
        return if query.match?(Search::QUERY_REGEX)

        reason = MissingFormula.reason(query, silent: true)
        return if reason.nil?

        if found_matches
          puts
          puts "If you meant #{query.inspect} specifically:"
        end
        puts reason
      end

      private

      sig { void }
      def print_regex_help
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

      sig { returns(T::Boolean) }
      def search_package_manager!
        package_manager = PACKAGE_MANAGERS.find { |name,| args.public_send(:"#{name}?") }
        return false if package_manager.nil?

        _, url = package_manager
        Utils::Browser.open url.call(URI.encode_www_form_component(args.named.join(" ")))
        true
      end
    end
  end
end
