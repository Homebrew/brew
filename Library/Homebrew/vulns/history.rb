# typed: strict
# frozen_string_literal: true

require "formula_versions"
require "simulate_system"
require "vulns/platform_independence"

module Homebrew
  module Vulns
    # Walks a formula's tap history newest first via {FormulaVersions}. Each
    # instance shares Git facts across platforms for a fixed tap history,
    # while loaded formulae remain specific to the simulated platform unless
    # their source proves that matching metadata is platform-independent.
    #
    # History that cannot be trusted fails closed: a shallow clone, a formula
    # file with no git history and a revision that cannot be loaded all end the
    # walk with `:history_unavailable` so callers skip the candidate rather
    # than inventing a boundary.
    class History
      class LoadFailure < T::Struct
        const :formula, String
        const :revision, String
        const :path, String
        const :platform, String
        const :error_class, String
        const :message, String
      end

      sig { void }
      def initialize
        @formula_versions = T.let({}, T::Hash[String, FormulaVersions])
        @rev_lists = T.let({}, T::Hash[String, T::Array[[String, String]]])
        @complete_history = T.let({}, T::Hash[String, T::Boolean])
        @shallow_taps = T.let({}, T::Hash[String, T::Boolean])
        @sources = T.let({}, T::Hash[[String, String, String], String])
        @platform_independence = T.let({}, T::Hash[[String, String, String], T::Boolean])
        @independent_formulae = T.let({}.compare_by_identity, T::Hash[Formula, T::Boolean])
        @shared_formulae = T.let({}, T::Hash[[String, String, String], Formula])
        @load_failures = T.let({}, T::Hash[[String, String, String, String], LoadFailure])
      end

      # One diagnostic per formula, revision, path and simulated platform.
      sig { returns(T::Array[LoadFailure]) }
      def load_failures = @load_failures.values

      # Identity is essential: distinct platform views of the same formula
      # can compare equal, but only a source-proven historical instance may be shared.
      sig { params(formula: Formula).returns(T::Boolean) }
      def platform_independent?(formula) = @independent_formulae.key?(formula)

      # Yield each loadable historical revision of `formula`, newest first,
      # until the block returns a result. Returns that result,
      # `:history_unavailable` when the history cannot be trusted or `nil` once
      # every revision has been visited. With `complete`, also require the
      # oldest revision to add or rename the formula into this name. History
      # under a different formula name is outside this named lifetime.
      # A proven absent path is not a build; skip it
      # in complete walks so earlier lifetimes are still observed.
      sig {
        params(formula:         Formula,
               complete:        T::Boolean,
               reuse_platforms: T::Boolean,
               _block:          T.proc.params(old: Formula).returns(T.nilable(T.any(String, Symbol))))
          .returns(T.nilable(T.any(String, Symbol)))
      }
      def walk(formula, complete: false, reuse_platforms: false, &_block)
        tap = formula.tap!
        tap_key = tap.path.to_s
        return :history_unavailable if @shallow_taps.fetch(tap_key) { @shallow_taps[tap_key] = tap.shallow? }

        tap_path = formula.tap_path.to_s
        fv = @formula_versions["#{tap_path}:#{SimulateSystem.current_os}:#{SimulateSystem.current_arch}"] ||=
          FormulaVersions.new(formula, simulated_target: true)
        begin
          revs = @rev_lists["#{tap_path}:#{complete}"] ||=
            [].tap { |a| fv.rev_list("HEAD", all_history: complete) { |rev, entry| a << [rev, entry] } }
        rescue ErrorDuringExecution
          return :history_unavailable
        end
        return :history_unavailable if revs.empty?

        if complete
          complete_history = @complete_history.fetch(tap_path) do
            oldest_rev, oldest_path = revs.fetch(-1)
            additions = Utils.popen_read("git", "-C", tap_key, "diff-tree", "--root",
                                         "--no-commit-id", "--name-only", "--find-renames", "--diff-filter=AR",
                                         "-r", oldest_rev, safe: true).lines(chomp: true)
            @complete_history[tap_path] = additions.include?(oldest_path)
          rescue ErrorDuringExecution
            @complete_history[tap_path] = false
          end
          return :history_unavailable unless complete_history
        end

        revs.each do |rev, entry|
          # Wrap the verdict so keeping the walk going (`nil`) stays
          # distinguishable from a revision that failed to load.
          key = [tap_path, rev, entry]
          source = @sources[key] if reuse_platforms
          independent = reuse_platforms && @platform_independence.fetch(key) do
            @platform_independence[key] = begin
              source = Utils.popen_read("git", "-C", tap_key, "cat-file", "blob", "#{rev}:#{entry}", safe: true)
              @sources[key] = source
              PlatformIndependence.source?(source)
            rescue ErrorDuringExecution
              false
            end
          end
          shared = @shared_formulae[key] if independent
          verdict = if shared
            [yield(shared)]
          else
            fv.formula_at_revision(rev, entry, **(source ? { source: } : {})) do |old|
              if independent
                @shared_formulae[key] = old
                @independent_formulae[old] = true
              end
              [yield(old)]
            end
          end
          if verdict.nil?
            begin
              next if complete && fv.path_absent_at_revision?(rev, entry)
            rescue ErrorDuringExecution => e
              record_load_failure(formula, rev, entry, e)
              return :history_unavailable
            end
            record_load_failure(formula, rev, entry, fv.load_error)
            return :history_unavailable
          end

          result = verdict.fetch(0)
          return result unless result.nil?
        end
        nil
      end

      private

      sig { params(formula: Formula, revision: String, path: String, error: T.nilable(Exception)).void }
      def record_load_failure(formula, revision, path, error)
        platform = "#{SimulateSystem.current_os}/#{SimulateSystem.current_arch}"
        key = [formula.full_name, revision, path, platform]
        return if @load_failures[key]

        message = if error
          error.message.lines.first.to_s.strip
        else
          "Formula could not be loaded"
        end
        @load_failures[key] = LoadFailure.new(
          formula: formula.full_name, revision:, path:, platform:,
          error_class: error&.class&.name || "FormulaUnavailableError",
          message:
        )
      end
    end
  end
end
