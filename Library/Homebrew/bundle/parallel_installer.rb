# typed: strict
# frozen_string_literal: true

require "concurrent/executors"
require "concurrent/promises"
require "monitor"
require "utils"
require "bundle/package_types"

module Homebrew
  module Bundle
    class ParallelInstaller
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
        dependency_map = build_dependency_map

        success = 0
        failure = 0
        pending_entries = T.let(@entries.dup, T::Array[Installer::InstallableEntry])
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
          futures = batch.to_h do |entry|
            [entry, Concurrent::Promises.future_on(@pool, entry) do |install_entry|
              install_entry!(install_entry)
            end]
          end

          batch.each do |entry|
            installed = begin
              !futures.fetch(entry).value!.nil?
            rescue => e
              write_output(Formatter.error("Installing #{entry.name} has failed!"), stream: $stderr)
              write_output("[#{entry.name}] #{e.message}", stream: $stderr) if @verbose
              false
            end

            pending_entries.delete(entry)
            completed << entry.name
            if installed
              success += 1
            else
              failure += 1
            end
          end
        end

        [success, failure]
      ensure
        @pool.shutdown
        @pool.wait_for_termination
      end

      private

      sig { returns(T::Hash[String, T::Set[String]]) }
      def build_dependency_map
        installed_taps = Homebrew::Bundle::Tap.installed_taps

        # Phase 1: Map both full and short names so dep lookups work either way.
        entry_name_map = @entries.each_with_object({}) do |entry, map|
          map[entry.name] = entry.name
          map[normalize_formula_name(entry.name)] = entry.name
        end

        # Phase 2: Direct dependencies declared in the Brewfile. Determines
        # install ordering (entry A must finish before entry B starts).
        brewfile_deps = T.let({}, T::Hash[String, T::Array[String]])
        @entries.each do |entry|
          deps = case entry.cls.name
          when "Homebrew::Bundle::Brew"
            Homebrew::Bundle::Brew.formula_dep_names(entry.name)
          when "Homebrew::Bundle::Cask"
            Homebrew::Bundle::Cask.formula_dependencies([entry.name])
          else
            []
          end

          # Entries from non-default taps depend on the tap being installed first.
          deps += Homebrew::Bundle::Installer.tap_dependencies(entry, entries: @entries, installed_taps:)

          brewfile_deps[entry.name] = deps
        end

        # Phase 3: Recursive dependency sets for lock conflict detection.
        # Only include build deps when building from source.  Pouring bottles
        # only locks runtime deps, so a shared build dep like cmake won't
        # serialize unrelated bottle pours.
        cask_names = T.let(@entries.select { |e| e.cls == Homebrew::Bundle::Cask }.to_set(&:name), T::Set[String])
        recursive_deps = T.let({}, T::Hash[String, T::Set[String]])
        @entries.each do |entry|
          recursive_deps[entry.name] = case entry.cls.name
          when "Homebrew::Bundle::Brew"
            building_from_source = Array(entry.options[:args]).any? { |a| a.to_s == "build-from-source" } ||
                                   !Homebrew::Bundle::Brew.formula_bottled?(entry.name)
            Homebrew::Bundle::Brew.recursive_dep_names(entry.name, include_build: building_from_source)
          when "Homebrew::Bundle::Cask"
            cask_dep_names(entry.name, cask_names)
          else
            Set.new
          end
        end

        # Phase 4: Merge explicit ordering and implicit lock conflicts.
        @entries.each_with_object({}) do |entry, map|
          depends_on = brewfile_deps.fetch(entry.name).each_with_object(Set.new) do |dep, set|
            name = entry_name_map[dep] || entry_name_map[normalize_formula_name(dep)]
            set << name if name.present? && name != entry.name
          end

          # Later entries wait for earlier ones when they share any recursive dep.
          entry_rdeps = recursive_deps.fetch(entry.name)
          @entries.each do |earlier|
            break if earlier.name == entry.name
            next if depends_on.include?(earlier.name)

            earlier_rdeps = recursive_deps.fetch(earlier.name)
            depends_on << earlier.name if entry_rdeps.intersect?(earlier_rdeps)
          end

          map[entry.name] = depends_on
        end
      end

      sig { params(name: String).returns(String) }
      def normalize_formula_name(name)
        Utils.name_from_full_name(name)
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

      sig { params(message: String, stream: IO).void }
      def write_output(message, stream: $stdout)
        @output_mutex.synchronize { stream.puts(message) }
      end

      sig { void }
      def clear_tty_line
        File.open("/dev/tty", "w") { |f| f.print("\r\e[K") }
      rescue Errno::ENXIO, Errno::ENOENT
        # No TTY available (CI, piped output) - nothing to clean up.
        nil
      end
    end
  end
end
