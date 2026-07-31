# typed: strict
# frozen_string_literal: true

require "concurrent/executors"
require "concurrent/promises"
require "monitor"
require "utils"
require "utils/tty"
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
        installed_taps = Homebrew::Bundle::Tap.installed_taps
        attestation_formula = if Homebrew::EnvConfig.verify_attestations?
          entries.find { |entry| entry.cls == Homebrew::Bundle::Brew && entry.name == "gh" }
        end

        # Phase 1: Map both full and short names so dep lookups work either way.
        entry_name_map = entries.each_with_object(T.let({}, T::Hash[String, String])) do |entry, map|
          map[entry.name] = entry.name
          map[normalize_formula_name(entry.name)] = entry.name
        end

        # Phase 2: Direct dependencies declared in the Brewfile. Determines
        # install ordering (entry A must finish before entry B starts).
        brewfile_deps = T.let({}, T::Hash[String, T::Array[String]])
        entries.each do |entry|
          deps = case entry.cls.name
          when "Homebrew::Bundle::Brew"
            Homebrew::Bundle::Brew.formula_dep_names(entry.name)
          when "Homebrew::Bundle::Cask"
            Homebrew::Bundle::Cask.formula_dependencies([entry.full_name])
          else
            []
          end

          # Entries from non-default taps depend on the tap being installed first.
          deps += Homebrew::Bundle::Installer.tap_dependencies(entry, entries:, installed_taps:)
          if attestation_formula && [Homebrew::Bundle::Brew, Homebrew::Bundle::Cask].include?(entry.cls) &&
             entry.name != attestation_formula.name
            deps << attestation_formula.name
          end

          brewfile_deps[entry.name] = deps
        end

        # Phase 3: The names each entry's install locks, for lock conflict detection.
        # `FormulaInstaller#lock` locks the formula itself and all of its recursive
        # dependencies before installing, even when pouring bottles, so a formula with
        # no dependencies of its own (e.g. `xz`) still conflicts with every entry that
        # depends on it.
        cask_names = T.let(entries.select { |e| e.cls == Homebrew::Bundle::Cask }.to_set(&:name), T::Set[String])
        lock_names = T.let({}, T::Hash[String, T::Set[String]])
        entries.each do |entry|
          lock_names[entry.name] = case entry.cls.name
          when "Homebrew::Bundle::Brew"
            Homebrew::Bundle::Brew.lock_names(entry.name)
          when "Homebrew::Bundle::Cask"
            cask_dep_names(entry.name, cask_names)
          else
            Set.new
          end
        end

        # Phase 4: Resolve the declared dependencies to the entries providing them.
        entry_deps = entries.to_h do |entry|
          deps = brewfile_deps.fetch(entry.name)
                              .each_with_object(T.let(Set.new, T::Set[String])) do |dep, set|
            name = entry_name_map[dep] || entry_name_map[normalize_formula_name(dep)]
            next if name.nil? || name == entry.name

            set << name
          end

          [entry.name, deps]
        end

        # Phase 5: Order the entries dependency-first. Lock conflicts have to be
        # serialized the same way round as the declared dependencies above, so a
        # Brewfile that lists a dependent before its dependency (e.g. `python`
        # before `xz`) does not end up with the two orderings disagreeing and
        # stranding every entry in the sequential fallback in `run!`.
        topo = Homebrew::Bundle::Brew::Topo.new
        entries.each { |entry| topo[entry.name] = entry_deps.fetch(entry.name).to_a }
        # A cycle here means the declared dependencies themselves disagree, which
        # `run!` handles by installing serially; keep the rest of the order usable.
        order = topo.tsort_with_cycles do |cycles|
          odebug "Bundle entries have a circular dependency: #{cycles.flatten.uniq.join(", ")}"
        end
        position = T.let(order.each_with_index.to_h, T::Hash[String, Integer])

        # Phase 6: formulae racing for an undeclared implicit dependency (e.g. a
        # Linux sandbox executable) wait on just the first one, not on each other.
        # It has to be the first in dependency order rather than in Brewfile order
        # so that its edges point the same way round as everything else.
        implicit_pioneer = T.let(nil, T.nilable(String))
        unless DependencyCollector.new.implicit_dependency_names.empty?
          implicit_pioneer = entries.select { |entry| entry.cls == Homebrew::Bundle::Brew }
                                    .min_by { |entry| position.fetch(entry.name) }&.name
        end

        # Phase 7: Merge declared ordering and lock conflicts.
        entries.each_with_object({}) do |entry, map|
          depends_on = entry_deps.fetch(entry.name).dup
          entry_locks = lock_names.fetch(entry.name)
          entry_position = position.fetch(entry.name)

          entries.each do |other|
            next if position.fetch(other.name) >= entry_position
            next if depends_on.include?(other.name)

            depends_on << other.name if entry_locks.intersect?(lock_names.fetch(other.name))
          end

          if implicit_pioneer && entry.name != implicit_pioneer && entry.cls == Homebrew::Bundle::Brew
            depends_on << implicit_pioneer
          end

          map[entry.name] = depends_on
        end
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

      # Walk cask-on-cask dependencies transitively, returning the set of
      # cask names (from the Brewfile) that this cask depends on.
      sig { params(name: String, cask_names: T::Set[String]).returns(T::Set[String]) }
      def cask_dep_names(name, cask_names)
        return Set.new unless Bundle.cask_installed?

        require "cask/cask_loader"
        cask = ::Cask::CaskLoader.load(name)
        direct = Array(cask.depends_on[:cask]).to_set
        # Only include deps that are also in the Brewfile.
        direct & cask_names
      rescue ::Cask::CaskUnavailableError
        Set.new
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
