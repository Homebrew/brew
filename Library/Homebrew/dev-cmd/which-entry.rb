# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formulary"
require "executables_db"

module Homebrew
  module DevCmd
    # `brew which-entry` command.
    class WhichEntry < AbstractCommand
      cmd_args do
        description <<~EOS
          Generate an executables database entry for one or more formulae using
          their bottle manifest metadata (sh.brew.path_exec_files). Optionally
          append/update entries in an existing executables.txt file.
        EOS

        flag "--append-to=",
             description: "Append or update entries in the given database file (e.g. executables.txt)."
        switch "--no-fallback",
               description: "Do not fall back to scanning the bottle tarball when the manifest is missing " \
                            "annotations."

        named_args :formula, min: 1
      end

      sig { override.void }
      def run
        # Resolve all formula objects first
        formulae = args.named.to_a.map { |name| Formulary.factory(name) }

        lines = []
        formulae.each do |f|
          entry = ExecutablesDB.entry_from_manifest(f, fallback_to_tar: !args.no_fallback?)
          if entry.nil?
            opoo "No executables metadata found for #{f.full_name}."
            next
          end
          lines << entry
        end

        if (path = args.append_to)
          update_db_file(Pathname(path), lines)
        else
          print lines.join
        end
      end

      private

      sig { params(path: Pathname, new_lines: T::Array[String]).void }
      def update_db_file(path, new_lines)
        # Build a map of name => line for new entries
        new_by_name = {}
        new_lines.each do |line|
          if (name = line[/\A([^()]+)\(/, 1])
            new_by_name[name] = line
          end
        end

        existing_lines = if path.exist?
          path.read.split("\n", -1).reject(&:empty?).map { |l| l.end_with?("\n") ? l : "#{l}\n" }
        else
          []
        end

        updated = []
        seen = {}
        existing_lines.each do |line|
          name = line[/\A([^()]+)\(/, 1]
          if name && new_by_name.key?(name)
            updated << new_by_name[name]
            seen[name] = true
          else
            updated << line
          end
        end

        # Append any new names not already present
        (new_by_name.keys - seen.keys).sort.each do |name|
          updated << new_by_name[name]
        end

        # Sort for stable output like ExecutablesDB#save!
        updated_sorted = updated.sort

        path.write(updated_sorted.join)
      end
    end
  end
end
