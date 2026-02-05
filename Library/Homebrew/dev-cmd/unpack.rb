# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "fileutils"
require "stringio"
require "formula"
require "cask/download"
require "unpack_strategy"

module Homebrew
  module DevCmd
    class Unpack < AbstractCommand
      include FileUtils

      cmd_args do
        description <<~EOS
          Unpack the files for the <formula> or <cask> into subdirectories of the current
          working directory.
        EOS
        flag   "--destdir=",
               description: "Create subdirectories in the directory named by <path> instead."
        switch "--patch",
               description: "Patches for <formula> will be applied to the unpacked source."
        switch "-g", "--git",
               description: "Initialise a Git repository in the unpacked source. This is useful for creating " \
                            "patches for the software."
        switch "-f", "--force",
               description: "Overwrite the destination directory if it already exists."
        switch "--formula", "--formulae",
               description: "Treat all named arguments as formulae."
        switch "--cask", "--casks",
               description: "Treat all named arguments as casks."

        conflicts "--git", "--patch"
        conflicts "--formula", "--cask"
        conflicts "--cask", "--patch"
        conflicts "--cask", "--git"

        named_args [:formula, :cask], min: 1
      end

      sig { override.void }
      def run
        formulae_and_casks = if args.casks?
          args.named.to_formulae_and_casks(only: :cask)
        elsif args.formulae?
          args.named.to_formulae_and_casks(only: :formula)
        else
          args.named.to_formulae_and_casks
        end

        if (dir = args.destdir)
          unpack_dir = Pathname.new(dir).expand_path
          unpack_dir.mkpath
        else
          unpack_dir = Pathname.pwd
        end

        odie "Cannot write to #{unpack_dir}" unless unpack_dir.writable?

        formulae_and_casks.each do |formula_or_cask|
          if formula_or_cask.is_a?(Cask::Cask)
            unpack_cask(formula_or_cask, unpack_dir)
          elsif (formula = T.cast(formula_or_cask, Formula))
            unpack_formula(formula, unpack_dir)
          end
        end
      end

      private

      sig { params(formula: Formula, unpack_dir: Pathname).void }
      def unpack_formula(formula, unpack_dir)
        stage_dir = unpack_dir/"#{formula.name}-#{formula.version}"

        if stage_dir.exist?
          odie "Destination #{stage_dir} already exists!" unless args.force?

          rm_rf stage_dir
        end

        oh1 "Unpacking #{Formatter.identifier(formula.full_name)} to: #{stage_dir}"

        # show messages about tar
        with_env VERBOSE: "1" do
          formula.brew do
            formula.patch if args.patch?
            cp_r getwd, stage_dir, preserve: true
          end
        end

        return unless args.git?

        ohai "Setting up Git repository"
        cd(stage_dir) do
          system "git", "init", "-q"
          system "git", "add", "-A"
          system "git", "commit", "-q", "-m", "brew-unpack"
        end
      end

      sig { params(cask: Cask::Cask, unpack_dir: Pathname).void }
      def unpack_cask(cask, unpack_dir)
        stage_dir = unpack_dir/"#{cask.token}-#{cask.version}"

        if stage_dir.exist?
          odie "Destination #{stage_dir} already exists!" unless args.force?

          rm_rf stage_dir
        end

        oh1 "Unpacking #{Formatter.identifier(cask.full_name)} to: #{stage_dir}"

        download = Cask::Download.new(cask, quarantine: true)

        downloaded_path = if download.downloaded?
          download.cached_download
        else
          download.fetch(quiet: false)
        end

        stage_dir.mkpath
        UnpackStrategy.detect(downloaded_path).extract_nestedly(to: stage_dir, verbose: true)
      end
    end
  end
end
