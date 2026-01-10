# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"

module Homebrew
  module Cmd
    class Source < AbstractCommand
      cmd_args do
        description <<~EOS
          Open a <formula>'s source repository in a browser, or open
          Homebrew's own repository if no argument is provided.

          The repository URL is determined from the formula's head URL,
          stable URL, or homepage. Supports GitHub, GitLab, Bitbucket, Codeberg and
          SourceHut repositories.
        EOS

        named_args :formula
      end

      sig { override.void }
      def run
        if args.no_named?
          exec_browser "https://github.com/Homebrew/brew"
          return
        end

        formulae = args.named.to_formulae
        repo_urls = formulae.filter_map do |formula|
          repo_url = extract_repo_url(formula)
          if repo_url
            puts "Opening repository for #{formula.name}"
            repo_url
          else
            opoo "Could not determine repository URL for #{formula.name}"
            nil
          end
        end

        return if repo_urls.empty?

        exec_browser(*repo_urls)
      end

      private

      sig { params(formula: Formula).returns(T.nilable(String)) }
      def extract_repo_url(formula)
        urls_to_check = [
          formula.head&.url,
          formula.stable&.url,
          formula.homepage,
        ]

        urls_to_check.each do |url|
          next if url.nil?

          repo_url = url_to_repo(url)
          return repo_url if repo_url
        end

        nil
      end

      sig { params(url: String).returns(T.nilable(String)) }
      def url_to_repo(url)
        github_repo_url(url) ||
          gitlab_repo_url(url) ||
          bitbucket_repo_url(url) ||
          codeberg_repo_url(url) ||
          sourcehut_repo_url(url)
      end

      sig { params(url: String).returns(T.nilable(String)) }
      def github_repo_url(url)
        regex = %r{
          https?://github\.com/
          (?<user>[\w.-]+)/
          (?<repo>[\w.-]+)
          (?:/.*)?
        }x
        match = url.match(regex)
        return unless match

        user = match[:user]
        repo = match[:repo]&.delete_suffix(".git")
        "https://github.com/#{user}/#{repo}"
      end

      sig { params(url: String).returns(T.nilable(String)) }
      def gitlab_repo_url(url)
        regex = %r{
          https?://gitlab\.com/
          (?<path>(?:[\w.-]+/)*?[\w.-]+)
          (?:/-/|\.git|/archive/)
        }x
        match = url.match(regex)
        return unless match

        path = match[:path]&.delete_suffix(".git")
        "https://gitlab.com/#{path}"
      end

      sig { params(url: String).returns(T.nilable(String)) }
      def bitbucket_repo_url(url)
        regex = %r{
          https?://bitbucket\.org/
          (?<user>[\w.-]+)/
          (?<repo>[\w.-]+)
          (?:/.*)?
        }x
        match = url.match(regex)
        return unless match

        user = match[:user]
        repo = match[:repo]&.delete_suffix(".git")
        "https://bitbucket.org/#{user}/#{repo}"
      end

      sig { params(url: String).returns(T.nilable(String)) }
      def codeberg_repo_url(url)
        regex = %r{
          https?://codeberg\.org/
          (?<user>[\w.-]+)/
          (?<repo>[\w.-]+)
          (?:/.*)?
        }x
        match = url.match(regex)
        return unless match

        user = match[:user]
        repo = match[:repo]&.delete_suffix(".git")
        "https://codeberg.org/#{user}/#{repo}"
      end

      sig { params(url: String).returns(T.nilable(String)) }
      def sourcehut_repo_url(url)
        regex = %r{
          https?://(?:git\.)?sr\.ht/
          ~(?<user>[\w.-]+)/
          (?<repo>[\w.-]+)
          (?:/.*)?
        }x
        match = url.match(regex)
        return unless match

        user = match[:user]
        repo = match[:repo]&.delete_suffix(".git")
        "https://sr.ht/~#{user}/#{repo}"
      end
    end
  end
end
