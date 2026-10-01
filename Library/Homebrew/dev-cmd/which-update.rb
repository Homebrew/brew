# typed: strict
# frozen_string_literal: true

# License: MIT
# The license text can be found in Library/Homebrew/command-not-found/LICENSE

require "abstract_command"
require "executables_db"
require "utils/github"

module Homebrew
  module DevCmd
    class WhichUpdate < AbstractCommand
      cmd_args do
        description <<~EOS
          Database update for `brew which-formula`.
        EOS
        flag "--bottle-json-dir=",
             description: "Use generated bottle JSON files in the given directory to update formula entries."
        flag "--removed-formulae-file=",
             description: "Remove database entries for formulae listed in the given file."
        flag "--pull-request=",
             description: "Update entries for formula changes in the given pull request number."
        flag "--repository=",
             depends_on:  "--pull-request",
             description: "GitHub repository for `--pull-request` (default: `$GITHUB_REPOSITORY`)."
        flag "--summary-file=",
             description: "Output a summary of the changes to a file."
        named_args :database, number: 1
      end

      sig { override.void }
      def run
        updated = update_and_save! source:                args.named.fetch(0),
                                   bottle_json_dir:       args.bottle_json_dir,
                                   removed_formulae_file: args.removed_formulae_file,
                                   pull_request:          args.pull_request,
                                   repository:            args.repository,
                                   summary_file:          args.summary_file

        if (github_output = ENV["GITHUB_OUTPUT"].presence)
          File.open(github_output, "a") { |file| file.puts "updated=#{updated}" }
        end
      end

      sig {
        params(
          source:                String,
          bottle_json_dir:       T.nilable(String),
          removed_formulae_file: T.nilable(String),
          pull_request:          T.nilable(String),
          repository:            T.nilable(String),
          summary_file:          T.nilable(String),
        ).returns(T::Boolean)
      }
      def update_and_save!(source:, bottle_json_dir: nil, removed_formulae_file: nil, pull_request: nil,
                           repository: nil, summary_file: nil)
        source_path = Pathname(source)
        original_database = source_path.exist? ? source_path.read : nil
        db = ExecutablesDB.new source

        removed_formulae = if removed_formulae_file.blank? || !File.file?(removed_formulae_file)
          []
        else
          File.readlines(removed_formulae_file, chomp: true).filter_map { |line| line.strip.presence }
        end

        if pull_request
          repository = repository.presence || ENV["GITHUB_REPOSITORY"].presence
          if repository.blank?
            raise UsageError,
                  "`--repository` or `$GITHUB_REPOSITORY` is required with `--pull-request`."
          end

          owner, repo = repository.split("/", 2)
          if owner.blank? || repo.blank? || repo.include?("/")
            raise UsageError, "`--repository` must be in the form `owner/repo`."
          end

          GitHub::API.paginate_rest(GitHub.url_to("repos", owner, repo, "pulls", pull_request, "files")) do |files|
            T.cast(files, T::Array[T::Hash[String, T.untyped]]).each do |file|
              filename = file["filename"].to_s
              next if !filename.start_with?("Formula/") || !filename.end_with?(".rb")

              case file["status"].to_s
              when "removed"
                removed_formulae << File.basename(filename, ".rb")
              when "renamed"
                removed_formulae << File.basename(file["previous_filename"].to_s, ".rb")
              end
            end
          end
        end

        db.update!(bottle_json_dir:, removed_formulae:)
        db.save!
        updated = original_database != source_path.read

        if summary_file
          File.open(summary_file, "a") do |file|
            file.puts <<~EOS
              ## Database Update Summary

              #{updated ? "Updated command-not-found database." : "No changes"}
            EOS
          end
        end

        updated
      end
    end
  end
end
