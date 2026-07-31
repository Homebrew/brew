# typed: strict
# frozen_string_literal: true

require "concurrent/executors"
require "concurrent/promises"
require "monitor"
require "utils"
require "utils/tty"
require "utils/topological_hash"
require "bundle/brew"
require "bundle/cask"
require "bundle/package_types"
require "dependency_collector"

module Homebrew
  module Bundle
    class ParallelInstaller
      include ::Utils::Output::Mixin

      sig {
        params(
          entries:    T::Array[Installer::InstallableEntry],
          jobs:       Integer,
          no_upgrade: T::Boolean,
          verbose:    T::Boolean,
          force:      T::Boolean,
          quiet:      T::Boolean,
        ).void
      }
      def initialize(entries, jobs:, no_upgrade:, verbose:, force:, quiet:)
        @entries = entries
        @jobs = jobs
        @no_upgrade = no_upgrade
        @verbose = verbose
        @force = force
        @quiet = quiet
        @pool = T.let(Concurrent::FixedThreadPool.new(jobs), Concurrent::FixedThreadPool)
        @output_mutex = T.let(Monitor.new, Monitor)
        # Cask installs may trigger interactive sudo prompts that write
        # directly to the terminal.  Serialize them so Password: prompts
        # don't interleave with status output from other workers.
        @cask_install_mutex = T.let(Mutex.new, Mutex)
      end

      sig { returns([Integer, Integer]) }
      def run!
        success = 0
        failure = 0

        tap_entries, pending_entries = @entries.partition { |entry| entry.cls == Homebrew::Bundle::Tap }
        tap_entries.each_slice(@jobs) do |batch|
          tap_success, tap_failure = install_entries_parallel!(batch)
          success += tap_success
          failure += tap_failure
        end
        ::Tap.clear_cache if tap_entries.present?

        require "tap"
        installed_taps = Homebrew::Bundle::Tap.installed_taps
        pending_entries.each do |entry|
          tap_with_name = if entry.cls == Homebrew::Bundle::Brew
            ::Tap.with_formula_name(entry.full_name)
          elsif entry.cls == Homebrew::Bundle::Cask
            ::Tap.with_cask_token(entry.full_name)
          end
          next unless tap_with_name

          tap = tap_with_name.first
          next if installed_taps.include?(tap.name) || tap_entries.any? { |tap_entry| tap_entry.name == tap.name }

          tap.ensure_installed!
          installed_taps << tap.name
        end

        prepare_attestation_verification!(pending_entries)
        dependency_map = build_dependency_map(pending_entries)
        completed = T.let(Set.new, T::Set[String])
        until pending_entries.empty?
          ready_entries = pending_entries.select do |entry|
            dependency_map.fetch(entry.name, Set.new).all? { |dependency| completed.include?(dependency) }
          end

          if ready_entries.empty?
            pending_entries.each do |entry|
              installed = install_entry!(entry)
              completed << entry.name
              if installed
                success += 1
              else
                failure += 1
              end
            end
            break
          end

          batch = ready_entries.take(@jobs)
          batch_success, batch_failure = install_entries_parallel!(batch)
          success += batch_success
          failure += batch_failure

          pending_entries -= batch
          completed.merge(batch.map(&:name))
        end

        [success, failure]
      ensure
        @pool.shutdown
        @pool.wait_for_termination
      end

      sig { params(entries: T::Array[Installer::InstallableEntry]).returns(T::Hash[String, T::Set[String]]) }
      def build_dependency_map(entries)
        lock_names = lock_names_by_entry(entries)
        entry_deps = declared_deps_by_entry(entries, lock_names:)
        order = dependency_order(entries, entry_deps)
        position = order.each_with_index.to_h

        merge_lock_conflicts(entries, entry_deps:, lock_names:, order:, position:,
                             implicit_pioneer: implicit_pioneer(entries, position))
      end

      sig { params(message: String, stream: IO).void }
      def write_output(message, stream: $stdout)
        @output_mutex.synchronize do
          # Interactive installers can leave ONLCR disabled, so use CRLF to
          # ensure terminal status output returns to column 0.
          if stream.tty?
            stream.write(message, "\r\n")
          else
            stream.puts(message)
          end
        end
      end

      private

      sig { params(name: String).returns(String) }
      def normalize_formula_name(name)
        Utils.name_from_full_name(name)
      end

      sig { params(entries: T::Array[Installer::InstallableEntry]).void }
      def prepare_attestation_verification!(entries)
        return unless Homebrew::EnvConfig.verify_attestations?
        return unless entries.any? { |entry| [Homebrew::Bundle::Brew, Homebrew::Bundle::Cask].include?(entry.cls) }
        return if entries.any? { |entry| entry.cls == Homebrew::Bundle::Brew && entry.name == "gh" }

        require "attestation"

        Homebrew::Attestation.gh_executable
      end

      # The Cellar racks each entry's install locks. `FormulaInstaller#lock` locks the
      # formula itself and all of its recursive dependencies before installing, even
      # when pouring bottles, so a formula with no dependencies of its own (e.g. `xz`)
      # still conflicts with every entry that depends on it. Cask installs take the
      # same locks for the formulae they depend on.
      sig { params(entries: T::Array[Installer::InstallableEntry]).returns(T::Hash[String, T::Set[String]]) }
      def lock_names_by_entry(entries)
        entries.to_h do |entry|
          locks = case entry.cls.name
          when "Homebrew::Bundle::Brew"
            Homebrew::Bundle::Brew.lock_names(entry.name)
          when "Homebrew::Bundle::Cask"
            Homebrew::Bundle::Cask.lock_names([entry.full_name])
          else
            Set.new
          end

          [entry.name, locks]
        end
      end

      # Dependencies declared in the Brewfile, resolved to the entries providing them.
      # These determine install ordering: entry A must finish before entry B starts.
      sig {
        params(
          entries:    T::Array[Installer::InstallableEntry],
          lock_names: T::Hash[String, T::Set[String]],
        ).returns(T::Hash[String, T::Set[String]])
      }
      def declared_deps_by_entry(entries, lock_names:)
        installed_taps = Homebrew::Bundle::Tap.installed_taps
        attestation_formula = if Homebrew::EnvConfig.verify_attestations?
          entries.find { |entry| entry.cls == Homebrew::Bundle::Brew && entry.name == "gh" }
        end
        attestation_locks = attestation_formula ? lock_names.fetch(attestation_formula.name) : Set.new

        # Map both full and short names so dep lookups work either way.
        entry_name_map = entries.each_with_object(T.let({}, T::Hash[String, String])) do |entry, map|
          map[entry.name] = entry.name
          map[normalize_formula_name(entry.name)] = entry.name
        end

        entries.to_h do |entry|
          deps = case entry.cls.name
          when "Homebrew::Bundle::Brew"
            Homebrew::Bundle::Brew.formula_dep_names(entry.name)
          when "Homebrew::Bundle::Cask"
            Homebrew::Bundle::Cask.formula_dependencies([entry.full_name]) +
            Homebrew::Bundle::Cask.cask_dependencies([entry.full_name])
          else
            []
          end

          # Entries from non-default taps depend on the tap being installed first.
          deps += Homebrew::Bundle::Installer.tap_dependencies(entry, entries:, installed_taps:)
          if attestation_formula && verifies_attestation?(entry, attestation_formula, attestation_locks, lock_names)
            deps << attestation_formula.name
          end

          resolved = deps.each_with_object(T.let(Set.new, T::Set[String])) do |dep, set|
            name = entry_name_map[dep] || entry_name_map[normalize_formula_name(dep)]
            next if name.nil? || name == entry.name

            set << name
          end

          [entry.name, resolved]
        end
      end

      # Attestation verification shells out to `gh`, so entries that verify one have to
      # wait for it. Entries `gh` itself depends on must not: that edge would point back
      # against their own dependency edge and close a cycle. `lock_names` holds each
      # entry's own rack plus its recursive dependencies' racks, so `gh` already locking
      # everything a formula entry locks means `gh` depends on it.
      sig {
        params(
          entry:               Installer::InstallableEntry,
          attestation_formula: Installer::InstallableEntry,
          attestation_locks:   T::Set[String],
          lock_names:          T::Hash[String, T::Set[String]],
        ).returns(T::Boolean)
      }
      def verifies_attestation?(entry, attestation_formula, attestation_locks, lock_names)
        return false unless [Homebrew::Bundle::Brew, Homebrew::Bundle::Cask].include?(entry.cls)
        return false if entry.name == attestation_formula.name
        # Cask racks are the formulae a cask depends on, which `gh` can share without
        # depending on the cask, so only formula entries can be dependencies of `gh`.
        return true if entry.cls == Homebrew::Bundle::Cask

        !attestation_locks.superset?(lock_names.fetch(entry.name))
      end

      # Orders the entries dependency-first. Lock conflicts have to be serialized the
      # same way round as the declared dependencies, so a Brewfile that lists a
      # dependent before its dependency (e.g. `python` before `xz`) does not end up
      # with the two orderings disagreeing and stranding every entry in the sequential
      # fallback in `run!`.
      sig {
        params(
          entries:    T::Array[Installer::InstallableEntry],
          entry_deps: T::Hash[String, T::Set[String]],
        ).returns(T::Array[String])
      }
      def dependency_order(entries, entry_deps)
        topo = ::Utils::StringTopologicalHash.new
        entries.each { |entry| topo[entry.name] = entry_deps.fetch(entry.name).to_a }
        # A cycle means the declared dependencies themselves disagree. Entries outside
        # it still order correctly; those inside get an arbitrary intra-cycle order, so
        # warn rather than leave an unexplained partly-serial install behind.
        topo.sorted_names do |cycles|
          opoo <<~EOS
            Bundle entries have a circular dependency:
              #{cycles.flatten.uniq.join(", ")}
            These will be installed one at a time. Please report this if the Brewfile
            does not declare a dependency loop itself.
          EOS
        end
      end

      # Formulae racing for an undeclared implicit dependency (e.g. a Linux sandbox
      # executable) wait on just the first one, not on each other. It has to be the
      # first in dependency order rather than in Brewfile order so that its edges point
      # the same way round as everything else.
      sig {
        params(
          entries:  T::Array[Installer::InstallableEntry],
          position: T::Hash[String, Integer],
        ).returns(T.nilable(String))
      }
      def implicit_pioneer(entries, position)
        return if DependencyCollector.new.implicit_dependency_names.empty?

        entries.select { |entry| entry.cls == Homebrew::Bundle::Brew }
               .min_by { |entry| position.fetch(entry.name) }&.name
      end

      sig {
        params(
          entries:          T::Array[Installer::InstallableEntry],
          entry_deps:       T::Hash[String, T::Set[String]],
          lock_names:       T::Hash[String, T::Set[String]],
          order:            T::Array[String],
          position:         T::Hash[String, Integer],
          implicit_pioneer: T.nilable(String),
        ).returns(T::Hash[String, T::Set[String]])
      }
      def merge_lock_conflicts(entries, entry_deps:, lock_names:, order:, position:, implicit_pioneer:)
        entries.to_h do |entry|
          depends_on = entry_deps.fetch(entry.name).dup
          entry_locks = lock_names.fetch(entry.name)

          order.take(position.fetch(entry.name)).each do |earlier_name|
            next if depends_on.include?(earlier_name)

            depends_on << earlier_name if entry_locks.intersect?(lock_names.fetch(earlier_name))
          end

          if implicit_pioneer && entry.name != implicit_pioneer && entry.cls == Homebrew::Bundle::Brew
            depends_on << implicit_pioneer
          end

          [entry.name, depends_on]
        end
      end

      sig { params(entries: T::Array[Installer::InstallableEntry]).returns([Integer, Integer]) }
      def install_entries_parallel!(entries)
        futures = entries.to_h do |entry|
          [entry, Concurrent::Promises.future_on(@pool, entry) do |install_entry|
            install_entry!(install_entry)
          end]
        end

        success = 0
        failure = 0
        entries.each do |entry|
          installed = begin
            futures.fetch(entry).value! == true
          rescue => e
            write_output(Formatter.error("Installing #{entry.name} has failed!"), stream: $stderr)
            write_output("[#{entry.name}] #{e.message}", stream: $stderr) if @verbose
            false
          end

          if installed
            success += 1
          else
            failure += 1
          end
        end

        [success, failure]
      end

      sig { params(entry: Installer::InstallableEntry).returns(T::Boolean) }
      def install_entry!(entry)
        # Cask installs can trigger sudo password prompts that write directly
        # to /dev/tty.  Hold the output lock for the entire install so that
        # status messages from parallel formula workers don't interleave with
        # the Password: prompt.  Monitor is reentrant, so write_output calls
        # inside do_install_entry! can re-acquire the lock on the same thread.
        if entry.cls == Homebrew::Bundle::Cask
          @cask_install_mutex.synchronize do
            result = @output_mutex.synchronize { do_install_entry!(entry) }
            # Interactive prompts (sudo, macOS security frameworks) can leave
            # the terminal cursor mid-line on /dev/tty with no trailing
            # newline.  Clear any trailing prompt text with \r + CSI-K so the
            # next worker's status message overwrites it rather than appending
            # to produce "Password:Using foo".  Writes nothing visible when
            # the line is already clean, so formula and cask output stay
            # visually uniform.
            clear_tty_line
            result
          end
        else
          do_install_entry!(entry)
        end
      end

      sig { params(entry: Installer::InstallableEntry).returns(T::Boolean) }
      def do_install_entry!(entry)
        name = entry.name
        options = entry.options
        verb = entry.verb
        cls = entry.cls

        preinstall = if cls.preinstall!(name, **options, no_upgrade: @no_upgrade, verbose: @verbose)
          write_output(Formatter.success("#{verb} #{name}"))
          true
        else
          write_output("Using #{name}") unless @quiet
          false
        end

        if cls.install!(name, **options,
                        preinstall:, no_upgrade: @no_upgrade, verbose: @verbose, force: @force)
          true
        else
          write_output(Formatter.error("#{verb} #{name} has failed!"), stream: $stderr)
          false
        end
      end

      sig { void }
      def clear_tty_line
        File.open("/dev/tty", "w") do |f|
          f.print("#{Tty.begin_synchronized_update}\r\e[K#{Tty.end_synchronized_update}")
        end
      rescue Errno::ENXIO, Errno::ENOENT, Errno::EACCES, Errno::EPERM
        # No TTY available (CI, piped output) - nothing to clean up.
        nil
      end
    end
  end
end
