# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "cask"
require "system_command"

module Homebrew
  module DevCmd
    class GenerateZap < AbstractCommand
      include SystemCommand::Mixin

      cmd_args do
        description <<~EOS
          Generate a `zap` stanza for a cask by scanning the system for associated
          files and directories.

          Accepts a cask token (e.g. `firefox`) or, with `--name`, a raw application
          name string (e.g. `Firefox`). When a cask token is given, the application
          name is resolved from the cask's `app` artifact.

          The target application should have been launched at least once so that
          preference files and caches exist on disk.

          Outputs `trash`, `delete`, and `rmdir` directives suitable for pasting
          into a cask definition.
        EOS

        switch "--name",
               description: "Treat the argument as a raw application name instead of a cask token."

        named_args :cask_or_name, number: 1
      end

      USER_TRASH_PATHS = [
        "Desktop",
        "Documents",
        "Library",
        "Library/Application Scripts",
        "Library/Application Support",
        "Library/Application Support/CrashReporter",
        "Library/Application Support/com.apple.sharedfilelist/" \
        "com.apple.LSSharedFileList.ApplicationRecentDocuments",
        "Library/Caches",
        "Library/Caches/com.apple.helpd/Generated",
        "Library/Caches/com.apple.helpd/SDMHelpData/Other/English/HelpSDMIndexFile",
        "Library/Containers",
        "Library/Cookies",
        "Library/Group Containers",
        "Library/HTTPStorages",
        "Library/Internet Plug-Ins",
        "Library/LaunchAgents",
        "Library/Logs",
        "Library/Logs/DiagnosticReports",
        "Library/PreferencePanes",
        "Library/Preferences",
        "Library/Preferences/ByHost",
        "Library/Saved Application State",
        "Library/WebKit",
        "Music",
      ].freeze

      SYSTEM_DELETE_PATHS = [
        "/Library/Application Support",
        "/Library/Caches",
        "/Library/Frameworks",
        "/Library/LaunchAgents",
        "/Library/LaunchDaemons",
        "/Library/Logs",
        "/Library/PreferencePanes",
        "/Library/Preferences",
        "/Library/PrivilegedHelperTools",
        "/Library/Screen Savers",
        "/Library/ScriptingAdditions",
        "/Library/Services",
        "/Users/Shared",
        "/etc/newsyslog.d",
      ].freeze

      RMDIR_EXCLUSIONS = [
        "Library/Application Support/CrashReporter",
        "Library/Application Support/com.apple.sharedfilelist/" \
        "com.apple.LSSharedFileList.ApplicationRecentDocuments",
        "/Library/Application Support",
        "/Library/Caches",
        "/Library/Preferences",
      ].freeze

      UUID_PATTERN = /[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}/i

      sig { override.void }
      def run
        patterns = if args.name?
          [args.named.fetch(0)]
        else
          resolve_patterns_from_cask(args.named.to_casks.fetch(0))
        end

        ohai "Scanning for files matching #{format_patterns(patterns)}..."

        begin
          trash_paths = scan_directories(USER_TRASH_PATHS, home_relative: true, patterns:) + scan_home_root(patterns)
          delete_paths = scan_directories(SYSTEM_DELETE_PATHS, home_relative: false, patterns:)
        rescue Errno::EACCES, Errno::EPERM => e
          message = "Unable to generate a complete zap stanza: #{e.message}"

          unless Cask::Utils.full_disk_access_enabled?
            message += " Please enable Full Disk Access for your terminal under " \
                       "#{Cask::Utils.privacy_security_preference_pane("Full Disk Access")}."
          end

          odie message
        end

        trash_paths  = replace_uuids(collapse_to_wildcards(trash_paths))
        delete_paths = replace_uuids(collapse_to_wildcards(delete_paths))

        rmdir_paths = derive_rmdir_candidates(trash_paths + delete_paths)

        if trash_paths.empty? && delete_paths.empty?
          opoo "No files found matching #{format_patterns(patterns)}."
          puts "# No zap stanza required"
          return
        end

        puts format_stanza(trash: trash_paths, delete: delete_paths, rmdir: rmdir_paths)
      end

      private

      sig { params(cask: Cask::Cask).returns(T::Array[String]) }
      def resolve_patterns_from_cask(cask)
        app_artifact = cask.artifacts.find { |a| a.is_a?(Cask::Artifact::App) }
        if app_artifact
          patterns = [app_artifact.target.basename(".app").to_s]
          patterns.concat(bundle_identifiers(app_artifact))
          patterns.uniq
        else
          ohai "No app artifact found in cask \"#{cask.token}\"; using token as app name."
          [cask.token.tr("-", " ").split.map(&:capitalize).join(" ")]
        end
      end

      sig { params(patterns: T::Array[String]).returns(String) }
      def format_patterns(patterns)
        patterns.map { |pattern| "\"#{pattern}\"" }.to_sentence
      end

      sig { params(app_artifact: Cask::Artifact::App).returns(T::Array[String]) }
      def bundle_identifiers(app_artifact)
        info_plist = app_artifact.target/"Contents/Info.plist"
        return [] if !info_plist.exist? || !info_plist.readable?

        plist = system_command!("plutil", args: ["-convert", "xml1", "-o", "-", info_plist]).plist
        bundle_identifier = plist["CFBundleIdentifier"]
        return [] unless bundle_identifier.is_a?(String)

        [bundle_identifier]
      end

      sig {
        params(
          directories:   T::Array[String],
          home_relative: T::Boolean,
          patterns:      T::Array[String],
        ).returns(T::Array[String])
      }
      def scan_directories(directories, home_relative:, patterns:)
        home = Dir.home
        downcased_patterns = patterns.map(&:downcase)
        matches = []

        directories.each do |dir|
          full_dir = home_relative ? File.join(home, dir) : dir
          next unless File.directory?(full_dir)

          each_readable_child(full_dir) do |entry|
            downcased_entry = entry.downcase
            next unless downcased_patterns.any? { |pattern| downcased_entry.include?(pattern) }

            full_path = File.join(full_dir, entry)
            matches << normalize_path(full_path)
          end
        end

        matches.uniq.sort
      end

      sig { params(patterns: T::Array[String]).returns(T::Array[String]) }
      def scan_home_root(patterns)
        home = Dir.home
        downcased_patterns = patterns.map(&:downcase)
        matches = []

        each_readable_child(home) do |entry|
          next unless entry.start_with?(".")

          downcased_entry = entry.downcase
          next unless downcased_patterns.any? { |pattern| downcased_entry.include?(pattern) }

          matches << normalize_path(File.join(home, entry))
        end

        matches.sort
      end

      sig { params(dir: String, block: T.proc.params(entry: String).void).void }
      def each_readable_child(dir, &block)
        Dir.each_child(dir, &block)
      rescue Errno::EPERM, Errno::EACCES
        # Skip directories we lack permission to read, e.g. macOS-protected paths.
        nil
      end

      sig { params(paths: T::Array[String]).returns(T::Array[String]) }
      def collapse_to_wildcards(paths)
        grouped = paths.group_by { |p| File.dirname(p) }

        result = []
        grouped.each_value do |entries|
          if entries.size == 1
            result << entries.first
            next
          end

          basenames = entries.map { |e| File.basename(e) }
          wildcarded = find_wildcard_groups(basenames)

          dir = File.dirname(entries.fetch(0))
          wildcarded.each do |name|
            result << File.join(dir, name)
          end
        end

        result.uniq.sort
      end

      sig { params(basenames: T::Array[String]).returns(T::Array[String]) }
      def find_wildcard_groups(basenames)
        return basenames if basenames.size <= 1

        used = Array.new(basenames.size, false)
        result = []

        basenames.each_with_index do |name, i|
          next if used[i]

          group_indices = [i]
          basenames.each_with_index do |other, j|
            next if i == j || used[j]
            next unless other.start_with?(name)

            group_indices << j
          end

          if group_indices.size > 1
            result << "#{name}*"
            group_indices.each { |idx| used[idx] = true }
          else
            result << name
          end
        end

        result
      end

      sig { params(paths: T::Array[String]).returns(T::Array[String]) }
      def replace_uuids(paths)
        paths.map { |p| p.gsub(UUID_PATTERN, "*") }.uniq.sort
      end

      sig { params(paths: T::Array[String]).returns(T::Array[String]) }
      def derive_rmdir_candidates(paths)
        home = Dir.home
        candidates = []

        paths.each do |path|
          expanded = path.start_with?("~") ? File.join(home, path[2..]) : path
          parent = File.dirname(expanded)

          next unless parent.match?(%r{/(Application Support|Containers|Group Containers)/})

          normalized = normalize_path(parent)

          next if RMDIR_EXCLUSIONS.any? { |excl| normalized == "~/#{excl}" || normalized == excl }

          candidates << normalized unless paths.include?(normalized)
        end

        candidates.uniq.sort
      end

      sig { params(path: String).returns(String) }
      def normalize_path(path)
        home = Dir.home
        path.start_with?(home) ? path.sub(home, "~") : path
      end

      sig {
        params(
          trash:  T::Array[String],
          delete: T::Array[String],
          rmdir:  T::Array[String],
        ).returns(String)
      }
      def format_stanza(trash:, delete:, rmdir:)
        directives = []
        directives << format_directive("trash", trash) unless trash.empty?
        directives << format_directive("delete", delete) unless delete.empty?
        directives << format_directive("rmdir", rmdir) unless rmdir.empty?

        directives.join(",\n")
                  .prepend("zap ")
      end

      sig { params(key: String, paths: T::Array[String]).returns(String) }
      def format_directive(key, paths)
        if paths.size == 1
          "#{key}: \"#{paths.first}\""
        else
          items = paths.map { |p| "       \"#{p}\"" }.join(",\n")
          "#{key}: [\n#{items},\n     ]"
        end
      end
    end
  end
end
