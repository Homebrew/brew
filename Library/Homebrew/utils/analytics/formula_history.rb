# typed: strict
# frozen_string_literal: true

require "api"
require "digest"
require "formula_versions"
require "vulns/platform_independence"

module Utils
  module Analytics
    # Incremental stable-version history on core's first-parent branch.
    class FormulaHistory
      class Build < T::Struct
        const :version, T.nilable(String)
        const :revision, Integer, default: 0
        const :rebuild, Integer, default: 0
        const :error, T.nilable(String)
      end

      class Package < T::Struct
        prop :blob, String
        prop :builds, T::Hash[String, Build]
        prop :versions, T::Array[String], default: []
        prop :updated_at, Integer, default: 0
        prop :unknown_at, Integer, default: 0
      end

      class Checkpoint < T::Struct
        const :signature, String
        const :start_year, Integer
        const :baseline, String
        prop :seeded, T::Boolean, default: false
        prop :head, String, default: ""
        prop :packages, T::Hash[String, Package], default: {}
        prop :years, T::Hash[String, T::Hash[String, Integer]], default: {}
      end

      class Change < T::Struct
        const :path, String
        const :old_path, String
        const :blob, String
        const :regular, T::Boolean
      end

      class Commit < T::Struct
        const :revision, String
        const :timestamp, Integer
        const :changes, T::Array[Change], default: []
      end

      METRICS = %w[added removed versions major minor patch other revision_bumps bottle_rebuilds unreadable].freeze
      VERSION_PARTS = %w[major minor patch].freeze
      BATCH_SIZE = 100
      MAX_RUN_SECONDS = 600

      sig { params(path: Pathname, cache: Pathname).void }
      def initialize(path, cache: HOMEBREW_CACHE/"analytics/git/formula-history.json")
        @path = path
        @cache = cache
      end

      # A cold backfill may span runs; only complete reports describe today's catalogue.
      sig { params(start_year: T.nilable(Integer), max_seconds: Integer).returns(T::Hash[String, T.anything]) }
      def report(start_year: nil, max_seconds: MAX_RUN_SECONDS)
        if git("rev-parse", "--is-shallow-repository") == "true"
          raise "Formula history requires a complete Git history"
        end

        target = git("rev-parse", "HEAD")
        saved = JSON.parse(@cache.read) if @cache.exist?
        start_year ||= saved&.fetch("start_year", nil) || (Time.now.utc.year - 5)
        signature = Digest::SHA256.hexdigest([
          __FILE__, HOMEBREW_LIBRARY_PATH/"formula_versions.rb", HOMEBREW_LIBRARY_PATH/"version.rb",
          HOMEBREW_LIBRARY_PATH/"resource.rb", HOMEBREW_LIBRARY_PATH/"software_spec.rb",
          HOMEBREW_LIBRARY_PATH/"vulns/platform_independence.rb"
        ].map { |file| Digest::SHA256.file(file).hexdigest }.join + targets.to_s + start_year.to_s)
        if saved && saved["signature"] == signature
          # Sorbet's nested deserialiser resolves Utils against T::Props::Utils.
          saved.fetch("packages").transform_values! do |package|
            package.fetch("builds").transform_values! { |build| Build.from_hash(build) }
            Package.new(**package.transform_keys(&:to_sym))
          end
          state = Checkpoint.new(**saved.transform_keys(&:to_sym))
          begin
            git("merge-base", "--is-ancestor", state.head.presence || state.baseline.presence || target, target)
          rescue ErrorDuringExecution
            state = nil
          end
        end
        state ||= Checkpoint.new(signature:, start_year:, baseline: git(
          "rev-list", "--first-parent", "-1", "--before=#{start_year}-01-01T00:00:00Z", target
        ))
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + max_seconds
        Homebrew::API.with_no_api_env do
          unless state.seeded
            entries = if state.baseline.empty?
              []
            else
              git("ls-tree", "-rz", state.baseline).split("\0")
            end
            pending = entries.filter_map do |entry|
              metadata, path = entry.split("\t", 2)
              next if path.nil? || !formula_path?(path) || state.packages.key?(path)
              next unless metadata&.start_with?("100644 blob ", "100755 blob ")

              Change.new(path:, old_path: path, blob: metadata.split.fetch(2), regular: true)
            end
            pending.each_slice(BATCH_SIZE) do |changes|
              break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

              sources = sources(changes.map(&:blob))
              changes.each { |change| apply(state, change, sources.fetch(change.blob), timestamp: 0) }
              save(state)
            end
            state.seeded = pending.all? { |change| state.packages.key?(change.path) }
            state.head = state.baseline if state.seeded
          end
          if state.seeded && state.head != target
            range = state.head.empty? ? target : "#{state.head}..#{target}"
            git("rev-list", "--first-parent", "--reverse",
                range).lines(chomp: true).each_slice(BATCH_SIZE) do |revisions|
              break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

              batch = commits(state.head.empty? ? revisions.fetch(-1) : "#{state.head}..#{revisions.fetch(-1)}")
              sources = sources(batch.flat_map(&:changes).select(&:regular).map(&:blob).uniq)
              batch.each do |commit|
                commit.changes.each do |change|
                  apply(state, change, sources[change.blob], timestamp: commit.timestamp)
                end
                state.head = commit.revision
              end
              save(state)
            end
          end
        end
        save(state)
        complete = state.seeded && state.head == target
        cutoff_date = Time.now.utc.to_date << 12
        cutoff = Time.utc(cutoff_date.year, cutoff_date.month, cutoff_date.day).to_i
        processed_date = git("show", "-s", "--format=%cI", state.head) unless state.head.empty?
        {
          "generated_at"           => Time.now.utc.iso8601,
          "source"                 => "https://github.com/Homebrew/homebrew-core",
          "start_year"             => state.start_year,
          "revision"               => state.head.presence,
          "target_revision"        => target,
          "complete"               => complete,
          "processed_through"      => processed_date,
          "platforms"              => targets.map { |os, arch| "#{os}/#{arch}" },
          "maintenance"            => if complete
                                        state.packages.values.map do |package|
                                          if package.updated_at >= cutoff
                                            "updated"
                                          elsif package.unknown_at >= cutoff || package.builds.values.any?(&:error)
                                            "unknown"
                                          elsif package.builds.values.all? { |build| build.version.nil? }
                                            "no_stable_version"
                                          else
                                            "unchanged"
                                          end
                                        end.tally
          end,
          "maintenance_start_date" => Time.at(cutoff).utc.to_date.iso8601,
          "rows"                   => ["current", *Time.now.utc.year.downto(state.start_year)].map do |period|
            period = period.to_s
            METRICS.to_h do |metric|
              count = if period == "current"
                state.years.values.sum { |counts| counts.fetch(metric, 0) }
              else
                state.years.fetch(period, {}).fetch(metric, 0)
              end
              if !complete && (processed_date.nil? || (period != "current" && period.to_i > processed_date.to_i))
                count = nil
              end
              [metric, count]
            end.merge("period" => period)
          end,
        }
      end

      sig { returns(T::Array[[Symbol, Symbol]]) }
      def targets
        macos = MacOSVersion.new((HOMEBREW_MACOS_NEWEST_UNSUPPORTED.to_i - 1).to_s).to_sym
        [[macos, :arm], [macos, :intel], [:linux, :arm], [:linux, :intel]]
      end

      sig { params(path: String, source: String).returns(T::Hash[String, Build]) }
      def builds(path, source)
        independent = Homebrew::Vulns::PlatformIndependence.source?(source)
        result = T.let({}, T::Hash[String, Build])
        targets.each do |os, arch|
          result["#{os}/#{arch}"] = if independent && (shared = result.values.first)
            shared
          else
            Homebrew::SimulateSystem.with(os:, arch:) do
              versions = FormulaVersions.new(@path/path, repository: @path, simulated_target: true)
              versions.formula_at_revision(Digest::SHA256.hexdigest(source), path, source:) do |formula|
                Build.new(version: formula.stable&.version&.to_s, revision: formula.revision,
                          rebuild: formula.stable&.bottle_specification&.rebuild || 0)
              end || Build.new(version: nil, error: versions.load_error&.class&.name || "Unavailable formula")
            ensure
              Formulary.clear_cache
            end
          end
        end
        result
      end

      sig { params(state: Checkpoint, change: Change, source: T.nilable(String), timestamp: Integer).void }
      def apply(state, change, source, timestamp:)
        previous = state.packages.delete(change.old_path)
        counts = state.years[Time.at(timestamp).utc.year.to_s] ||= {} if timestamp.positive?
        unless change.regular
          counts["removed"] = counts.fetch("removed", 0) + 1 if counts && previous
          return
        end
        current = if previous && previous.blob == change.blob
          previous.builds
        else
          builds(change.path, source || raise("Missing Git blob #{change.blob}"))
        end
        package = previous || Package.new(blob: change.blob, builds: {})
        observed = current.values.filter_map(&:version).uniq
        events = T.let([], T::Array[String])
        events << "added" unless previous
        changed = current.filter_map do |platform, build|
          old = package.builds[platform]
          next if old.nil?

          old_version = old.version
          version = build.version
          next if old_version.nil? || version.nil?

          if old_version != version
            before = Version.new(old_version)
            after = Version.new(version)
            if after > before
              VERSION_PARTS.find { |part| before.public_send(part) != after.public_send(part) } || "other"
            else
              "other"
            end
          elsif build.revision > old.revision
            "revision_bumps"
          elsif build.revision == old.revision && build.rebuild > old.rebuild
            "bottle_rebuilds"
          end
        end
        if (version_change = (%w[major minor patch other] & changed).first)
          events << version_change
        end
        events.concat(changed & %w[revision_bumps bottle_rebuilds])
        if current.values.any?(&:error)
          events << "unreadable"
          package.unknown_at = [package.unknown_at, timestamp].max
        end
        if events.intersect?(%w[added major minor patch other revision_bumps])
          package.updated_at = [package.updated_at, timestamp].max
        end
        if counts
          events.compact.each { |event| counts[event] = counts.fetch(event, 0) + 1 }
          counts["versions"] = counts.fetch("versions", 0) + (observed - package.versions).length
        end
        package.versions |= observed
        package.blob = change.blob
        package.builds = current
        state.packages[change.path] = package
      end

      sig { params(range: String).returns(T::Array[Commit]) }
      def commits(range)
        tokens = git("log", "--first-parent", "--reverse", "--raw", "--root", "--no-abbrev",
                     "--diff-merges=first-parent", "--find-renames=50%", "--format=%x00commit%x00%H%x00%ct",
                     "-z", range).split("\0")
        commits = T.let([], T::Array[Commit])
        while (token = tokens.shift)
          if token == "commit"
            commits << Commit.new(revision: tokens.shift.to_s, timestamp: tokens.shift.to_i)
          elsif token.lstrip.start_with?(":")
            _, mode, _, blob, status = token.split
            path = tokens.shift.to_s
            new_path = status&.start_with?("R") ? tokens.shift.to_s : path
            next if !formula_path?(path) && !formula_path?(new_path)

            commits.fetch(-1).changes << Change.new(
              path: new_path, old_path: path, blob: blob.to_s,
              regular: %w[100644 100755].include?(mode) && formula_path?(new_path)
            )
          end
        end
        commits
      end

      # Fetch missing promisor objects together, avoiding one network fetch per old formula.
      sig { params(objects: T::Array[String]).returns(T::Hash[String, String]) }
      def sources(objects)
        missing = SystemCommand.run!(
          "git", args: ["-C", @path.to_s, "cat-file", "--batch-check"],
          input: objects.map { |object| "#{object}\n" }, env: { "GIT_NO_LAZY_FETCH" => "1" }
        ).stdout.lines.filter_map { |line| line.split.first if line.end_with?(" missing\n") }
        missing.each_slice(500) do |batch|
          Utils.safe_popen_write("git", "-C", @path.to_s, "-c", "fetch.negotiationAlgorithm=noop",
                                 "fetch", "--quiet", "--no-tags", "--no-write-fetch-head", "--filter=blob:none",
                                 "--stdin", "origin") { |pipe| pipe.puts(batch) }
        end
        result = T.let({}, T::Hash[String, String])
        Utils.safe_popen_write("git", "-C", @path.to_s, "cat-file", "--batch") do |pipe|
          objects.each do |object|
            pipe.puts(object)
            pipe.flush
            _, type, length = pipe.gets.to_s.split
            raise "Missing Git blob #{object}" if type != "blob"

            result[object] = pipe.read(Integer(length.to_s, 10)).to_s.force_encoding(Encoding::UTF_8)
            pipe.read(1)
          end
        end
        result
      end

      sig { params(path: String).returns(T::Boolean) }
      def formula_path?(path)
        path.match?(%r{\A(?:Library/)?Formula/(?:[^/]+/)?[^/]+\.rb\z})
      end

      sig { params(state: Checkpoint).void }
      def save(state)
        @cache.dirname.mkpath
        @cache.atomic_write(JSON.generate(state.serialize))
      end

      sig { params(args: String).returns(String) }
      def git(*args)
        Utils.safe_popen_read("git", "-C", @path.to_s, *args).strip
      end
    end
  end
end
