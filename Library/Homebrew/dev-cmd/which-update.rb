# typed: strict
# frozen_string_literal: true

# License: MIT
# The license text can be found in Library/Homebrew/command-not-found/LICENSE

require "abstract_command"
require "executables_db"

module Homebrew
  module DevCmd
    class WhichUpdate < AbstractCommand
      cmd_args do
        description <<~EOS
          Database update for `brew which-formula`.
        EOS
        switch "--stats",
               description: "Print statistics about the database contents (number of commands and formulae, " \
                            "list of missing formulae)."
        switch "--commit",
               description: "Commit the changes using `git`."
        switch "--update-existing",
               description: "Update database entries with outdated formula versions."
        switch "--install-missing",
               description: "Install and update formulae that are missing from the database and don't have bottles."
        switch "--eval-all",
               description: "Evaluate all installed taps, rather than just the core tap."
        flag   "--max-downloads=",
               description: "Specify a maximum number of formulae to download and update."
        flag   "--summary-file=",
               description: "Output a summary of the changes to a file."
        conflicts "--stats", "--commit"
        conflicts "--stats", "--install-missing"
        conflicts "--stats", "--update-existing"
        conflicts "--stats", "--max-downloads"
        named_args :database, number: 1
      end

      sig { override.void }
      def run
        if args.stats?
          stats source: args.named.fetch(0)
        else
          update_and_save! source:          args.named.fetch(0),
                           commit:          args.commit?,
                           update_existing: args.update_existing?,
                           install_missing: args.install_missing?,
                           max_downloads:   args.max_downloads&.to_i,
                           eval_all:        args.eval_all?,
                           summary_file:    args.summary_file
        end
      end

      sig { params(source: String).void }
      def stats(source:)
        opoo "The DB file doesn't exist." unless File.exist? source
        db = ExecutablesDB.new source

        formulae = db.formula_names
        core = Formula.core_names

        cmds_count = db.exes.values.reduce(0) { |s, exs| s + exs.binaries.size }

        core_percentage = ((formulae & core).size * 1000 / core.size.to_f).round / 10.0

        missing = (core - formulae).reject { |f| Formula[f].disabled? }
        puts <<~EOS
          #{formulae.size} formulae
          #{cmds_count} commands
          #{core_percentage}%  (missing: #{missing * " "})
        EOS

        unknown = formulae - Formula.full_names
        puts "\nUnknown formulae: #{unknown * ", "}." if unknown.any?
        nil
      end

      sig {
        params(
          source:          String,
          commit:          T::Boolean,
          update_existing: T::Boolean,
          install_missing: T::Boolean,
          max_downloads:   T.nilable(Integer),
          eval_all:        T::Boolean,
          summary_file:    T.nilable(String),
        ).void
      }
      def update_and_save!(source:, commit: false, update_existing: false, install_missing: false,
                           max_downloads: nil, eval_all: false, summary_file: nil)
        db = ExecutablesDB.new source
        db.update!(update_existing:, install_missing:,
                   max_downloads:, eval_all:)
        db.save!

        if summary_file
          msg = summary_file_message(db.changes)
          File.open(summary_file, "a") do |file|
            file.puts(msg)
          end
        end

        return if !commit || !db.changed?

        msg = git_commit_message(db.changes)
        safe_system "git", "-C", db.root.to_s, "commit", "-m", msg, source
      end

      sig { params(els: T::Array[String], verb: String).returns(String) }
      def english_list(els, verb)
        msg = +""
        msg << els.slice(0, 3)&.join(", ")
        msg << " and #{els.length - 3} more" if msg.length < 40 && els.length > 3
        "#{verb.capitalize} #{msg}"
      end

      sig { params(changes: ExecutablesDB::Changes).returns(String) }
      def git_commit_message(changes)
        msg = []
        ExecutablesDB::Changes::TYPES.each do |action|
          names = changes.send(action)
          next if names.empty?

          action = "bump version for" if action == :version_bump
          msg << english_list(names.to_a.sort, action.to_s)
          break
        end

        msg.join
      end

      sig { params(changes: ExecutablesDB::Changes).returns(String) }
      def summary_file_message(changes)
        msg = []
        ExecutablesDB::Changes::TYPES.each do |action|
          names = changes.send(action)
          next if names.empty?

          action_heading = action.to_s.split("_").map(&:capitalize).join(" ")
          msg << "### #{action_heading}"
          msg << ""
          names.to_a.sort.each do |name|
            msg << "- [`#{name}`](https://formulae.brew.sh/formula/#{name})"
          end
        end

        msg << "No changes" if msg.empty?

        <<~MESSAGE
          ## Database Update Summary

          #{msg.join("\n")}
        MESSAGE
      end
    end
  end
end
