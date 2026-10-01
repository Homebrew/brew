# typed: strict
# frozen_string_literal: true

require "utils/data"

require "timeout"

require "services/system"
require "utils/user"
require "cask/artifact/abstract_artifact"
require "cask/pkg"
require "cask/utils"
require "cask/utils/trash"
require "extend/hash/keys"
require "system_command"

module Cask
  module Artifact
    # Abstract superclass for uninstall artifacts.
    class AbstractUninstall < AbstractArtifact
      include SystemCommand::Mixin

      ORDERED_DIRECTIVES = [
        :early_script,
        :launchctl,
        :quit,
        :signal,
        :login_item,
        :kext,
        :script,
        :pkgutil,
        :delete,
        :trash,
        :rmdir,
      ].freeze

      METADATA_KEYS = [
        :on_upgrade,
      ].freeze

      sig { params(cask: Cask, directives: DirectivesType).returns(AbstractUninstall) }
      def self.from_args(cask, **directives)
        new(cask, **directives)
      end

      sig { returns(T::Hash[Symbol, DirectivesType]) }
      attr_reader :directives

      sig { params(cask: Cask, directives: DirectivesType).void }
      def initialize(cask, **directives)
        ::Utils::Data.assert_valid_keys(directives, *ORDERED_DIRECTIVES, *METADATA_KEYS)

        super
        directives[:signal] = Array(directives[:signal]).flatten.each_slice(2).to_a
        @directives = directives

        # This is already included when loading from the API.
        return if cask.loaded_from_api?
        return unless directives.key?(:kext)

        cask.caveats do
          T.bind(self, ::Cask::DSL::Caveats)
          kext
        end
      end

      sig { returns(T::Hash[Symbol, DirectivesType]) }
      def to_h
        directives.to_h
      end

      sig { override.returns(String) }
      def summarize
        to_h.flat_map { |key, val| Array(val).map { |v| "#{key.inspect} => #{v.inspect}" } }.join(", ")
      end

      sig { returns(T::Array[String]) }
      def bundle_ids_to_reopen
        @bundle_ids_to_reopen ||= T.let([], T.nilable(T::Array[String]))
      end

      # :quit/:signal must come before :kext so the kext will not be in use by a running process
      sig {
        params(
          bundle_ids: String,
          command:    T.nilable(T.class_of(SystemCommand)),
          upgrade:    T::Boolean,
          _kwargs:    T.anything,
        ).void
      }
      def uninstall_quit(*bundle_ids, command: nil, upgrade: false, **_kwargs)
        bundle_ids = bundle_ids.flat_map { |bundle_id| expand_bundle_id(bundle_id) }

        bundle_ids.each do |bundle_id|
          next unless running?(bundle_id)

          unless User.current&.gui?
            opoo "Not logged into a GUI; skipping quitting application ID '#{bundle_id}'."
            next
          end

          if hosting_brew?(bundle_id)
            opoo "Skipping quitting application '#{bundle_id}' as `brew` is running inside it."
            next
          end

          ohai "Quitting application '#{bundle_id}'..."

          quit_succeeded = T.let(false, T::Boolean)
          begin
            Timeout.timeout(10) do
              Kernel.loop do
                next unless quit(bundle_id).success?

                next if running?(bundle_id)

                puts "Application '#{bundle_id}' quit successfully."
                quit_succeeded = true
                break
              end
            end
          rescue Timeout::Error
            opoo "Application '#{bundle_id}' did not quit. #{automation_access_instructions}"
          end

          bundle_ids_to_reopen << bundle_id if upgrade && quit_succeeded
        end
      end

      # This returns T::Enumerable[[Pathname, T::Array[Pathname]]] when called without a block,
      # but sorbet doesn't support overloads.
      sig {
        params(
          action: Symbol,
          paths:  T::Array[T.any(Pathname, String)],
          _block: T.nilable(T.proc.params(path: T.any(Pathname, String), resolved_paths: T::Array[Pathname]).void),
        ).returns(T.untyped)
      }
      def each_resolved_path(action, paths, &_block)
        return enum_for(:each_resolved_path, action, paths) unless block_given?

        paths.each do |path|
          resolved_path = Pathname.new(path.to_s.sub(%r{^~(?=(?:/|$))}, Dir.home))

          if resolved_path.relative?
            opoo "Skipping #{Formatter.identifier(action)} for relative path '#{path}'."
            next
          end

          if resolved_path.each_filename.to_a.intersect?([".", ".."])
            opoo "Skipping #{Formatter.identifier(action)} for path with relative segments '#{path}'."
            next
          end

          begin
            resolved_paths = Pathname.glob(resolved_path).reject do |target|
              next false unless undeletable?(target)

              opoo "Skipping #{Formatter.identifier(action)} for undeletable path '#{target}'."
              true
            end
            yield path, resolved_paths
          rescue Errno::EPERM
            raise if ::Cask::Utils.full_disk_access_enabled?

            odie "Unable to remove some files. Please enable Full Disk Access for your terminal under " \
                 "#{::Cask::Utils.privacy_security_preference_pane("Full Disk Access")}."
          end
        end
      end

      sig { params(search: String).returns(T::Array[String]) }
      def find_launchctl_with_wildcard(search)
        regex = wildcard_pattern(search)
        system_command!("/bin/launchctl", args: ["list"])
          .stdout.lines.drop(1) # skip stdout column headers
          .filter_map do |line|
            pid, _state, id = line.chomp.split(/\s+/)
            id if pid.to_i.nonzero? && id&.match?(regex)
          end
      end

      private

      sig {
        params(
          command:   T.class_of(SystemCommand),
          force:     T::Boolean,
          successor: T.nilable(Cask),
          upgrade:   T::Boolean,
        ).void
      }
      def dispatch_uninstall_directives(command:, force: false, successor: nil, upgrade: false)
        ORDERED_DIRECTIVES.each do |directive_sym|
          dispatch_uninstall_directive(directive_sym, command:, force:, successor:, upgrade:)
        end
      end

      # The `uninstall_*` methods are dispatched dynamically, so they take these
      # options uniformly and ignore the ones they do not need.
      sig {
        params(
          directive_sym: Symbol,
          command:       T.class_of(SystemCommand),
          force:         T::Boolean,
          successor:     T.nilable(Cask),
          upgrade:       T::Boolean,
        ).void
      }
      def dispatch_uninstall_directive(directive_sym, command:, force: false, successor: nil, upgrade: false)
        return unless directives.key?(directive_sym)

        args = directives[directive_sym]

        send(:"uninstall_#{directive_sym}", *(args.is_a?(Hash) ? [args] : args),
             command:, force:, successor:, upgrade:)
      end

      sig { returns(Symbol) }
      def stanza
        self.class.dsl_key
      end

      # Preserve prior functionality of script which runs first. Should rarely be needed.
      # :early_script should not delete files, better defer that to :script.
      # If cask writers never need :early_script it may be removed in the future.
      sig {
        params(
          directives: DirectivesType,
          command:    T.class_of(SystemCommand),
          force:      T::Boolean,
          _kwargs:    T.anything,
        ).void
      }
      def uninstall_early_script(directives, command:, force: false, **_kwargs)
        uninstall_script(directives, command:, directive_name: :early_script, force:)
      end

      # :launchctl must come before :quit/:signal for cases where app would instantly re-launch
      sig { params(services: String, command: T.class_of(SystemCommand), _kwargs: T.anything).void }
      def uninstall_launchctl(*services, command:, **_kwargs)
        booleans = [false, true]
        all_services = []

        # if launchctl item contains a wildcard, find matching process(es)
        services.each do |service|
          all_services << service unless service.include?("*")
          next unless service.include?("*")

          found_services = find_launchctl_with_wildcard(service)
          next if found_services.blank?

          found_services.each { |found_service| all_services << found_service }
        end

        all_services.each do |service|
          ohai "Removing launchctl service #{service}"
          booleans.each do |sudo|
            next if sudo && !SystemCommand.sudo_available?

            _, found, = Homebrew::Services::System.launchctl_find_service(service, sudo:)
            if found
              result = command.run(
                "/bin/launchctl",
                args:         ["remove", service],
                must_succeed: false,
                sudo:,
                sudo_as_root: sudo,
              )
              next unless result.success?

              sleep 1
            end
            paths = [
              "/Library/LaunchAgents/#{service}.plist",
              "/Library/LaunchDaemons/#{service}.plist",
            ]
            paths.each { |elt| elt.prepend(Dir.home).freeze } unless sudo
            paths = paths.map { |elt| Pathname(elt) }.select(&:exist?)
            paths.each do |path|
              command.run("/bin/rm", args: ["-f", "--", path], must_succeed: false, sudo:, sudo_as_root: sudo)
            end
            # undocumented and untested: pass a path to uninstall :launchctl
            next unless Pathname(service).exist?

            command.run(
              "/bin/launchctl",
              args:         ["unload", "-w", "--", service],
              must_succeed: false,
              sudo:,
              sudo_as_root: sudo,
            )
            command.run(
              "/bin/rm",
              args:         ["-f", "--", service],
              must_succeed: false,
              sudo:,
              sudo_as_root: sudo,
            )
            sleep 1
          end
        end
      end

      sig { params(bundle_id: String).returns(T::Array[[Integer, Integer, T.nilable(String)]]) }
      def running_processes(bundle_id)
        system_command!("/bin/launchctl", args: ["list"])
          .stdout.lines.drop(1)
          .map { |line| line.chomp.split("\t") }
          .map { |pid, state, id| [pid.to_i, state.to_i, id] }
          .select do |(pid, _, id)|
            pid.nonzero? && /\A(?:application\.)?#{Regexp.escape(bundle_id)}(?:\.\d+){0,2}\Z/.match?(id)
          end
      end

      sig { returns(String) }
      def automation_access_instructions
        <<~EOS
          Enable Automation access for "Terminal → System Events" in:
            #{::Cask::Utils.privacy_security_preference_pane("Automation")}
          if you haven't already.
        EOS
      end

      sig { params(bundle_id: String).returns(T::Boolean) }
      def running?(bundle_id)
        script = <<~JAVASCRIPT
          'use strict';

          ObjC.import('stdlib')

          function run(argv) {
            try {
              var app = Application(argv[0])
              if (app.running()) {
                $.exit(0)
              }
            } catch (err) { }

            $.exit(1)
          }
        JAVASCRIPT

        system_command("osascript", args:         ["-l", "JavaScript", "-e", script, bundle_id],
                                    print_stderr: true).status.success? || false
      end

      RUNNING_BUNDLE_IDS_SCRIPT = <<~JAVASCRIPT
        'use strict';

        ObjC.import('AppKit')

        function run() {
          var apps = $.NSWorkspace.sharedWorkspace.runningApplications
          var bundleIds = []

          for (var i = 0; i < apps.count; i++) {
            var bundleId = apps.objectAtIndex(i).bundleIdentifier
            if (!bundleId.isNil()) {
              bundleIds.push(ObjC.unwrap(bundleId))
            }
          }

          return bundleIds.join("\\n")
        }
      JAVASCRIPT
      private_constant :RUNNING_BUNDLE_IDS_SCRIPT

      # Expands a `*` wildcard to the bundle IDs of matching running applications.
      sig { params(bundle_id: String).returns(T::Array[String]) }
      def expand_bundle_id(bundle_id)
        return [bundle_id] unless bundle_id.include?("*")

        # Listing running applications needs a GUI session, so warn once for the
        # pattern rather than enumerating and matching nothing.
        unless User.current&.gui?
          opoo "Not logged into a GUI; skipping applications matching '#{bundle_id}'."
          return []
        end

        # Anchored so that e.g. `com.example*` cannot match `org.other.com.example`,
        # and case-insensitive because `Application()` resolves bundle IDs that way.
        running_bundle_ids.grep(/\A#{wildcard_pattern(bundle_id)}\z/i)
      end

      # Translates a `*` wildcard into a regular expression fragment, leaving the
      # rest of the ID literal. Anchoring and case are left to the caller.
      sig { params(search: String).returns(String) }
      def wildcard_pattern(search)
        Regexp.escape(search).gsub("\\*", ".*")
      end

      # Whether the application with the given bundle ID is an ancestor of this
      # `brew` process, e.g. the terminal emulator the shell is running in.
      # Quitting or signalling it would take down `brew` itself.
      sig { params(bundle_id: String).returns(T::Boolean) }
      def hosting_brew?(bundle_id)
        AbstractUninstall.ancestor_bundle_ids.any? { |id| id.casecmp?(bundle_id) }
      end

      class << self
        # Bundle IDs of the applications this `brew` process is running inside.
        # The ancestry of the `brew` process cannot change while it runs, so the
        # lookup is shared by every artifact of every cask in the same invocation.
        sig { returns(T::Array[String]) }
        def ancestor_bundle_ids
          @ancestor_bundle_ids ||= begin
            pids = [Process.pid]
            # `launchd` (PID 1) reports a parent of `0` rather than failing.
            while (ppid = parent_pid(pids.last)) && ppid > 1 && pids.exclude?(ppid)
              pids << ppid
            end

            pids.filter_map { |pid| bundle_identifier_for_pid(pid) }
          end
        end

        sig { params(ancestor_bundle_ids: T.nilable(T::Array[String])).returns(T.nilable(T::Array[String])) }
        attr_writer :ancestor_bundle_ids

        sig { params(_pid: Integer).returns(T.nilable(Integer)) }
        def parent_pid(_pid) = nil

        sig { params(_pid: Integer).returns(T.nilable(String)) }
        def bundle_identifier_for_pid(_pid) = nil

        sig { params(_pid: Integer).returns(T.nilable(Integer)) }
        def owner_uid(_pid) = nil
      end

      sig { returns(T::Array[String]) }
      def running_bundle_ids
        @running_bundle_ids ||= T.let(
          system_command("osascript", args:         ["-l", "JavaScript", "-e", RUNNING_BUNDLE_IDS_SCRIPT],
                                      print_stderr: true)
            .stdout.split("\n").map(&:strip).reject(&:empty?),
          T.nilable(T::Array[String]),
        )
      end

      sig { params(bundle_id: String).returns(SystemCommand::Result) }
      def quit(bundle_id)
        script = <<~JAVASCRIPT
          'use strict';

          ObjC.import('stdlib')

          function run(argv) {
            var app = Application(argv[0])

            try {
              app.quit()
            } catch (err) {
              if (app.running()) {
                $.exit(1)
              }
            }

            $.exit(0)
          }
        JAVASCRIPT

        system_command "osascript", args:         ["-l", "JavaScript", "-e", script, bundle_id],
                                    print_stderr: false
      end
      private :quit

      # :signal should come after :quit so it can be used as a backup when :quit fails
      sig {
        params(signals: [String, String], command: T.nilable(T.class_of(SystemCommand)), _kwargs: T.anything).void
      }
      def uninstall_signal(*signals, command: nil, **_kwargs)
        signals = signals.flat_map do |pair|
          raise CaskInvalidError.new(cask, "Each #{stanza} :signal must consist of 2 elements.") if pair.size != 2

          signal, bundle_id = pair
          expand_bundle_id(bundle_id).map { |expanded_id| [signal, expanded_id] }
        end

        signals.each do |pair|
          signal, bundle_id = pair
          pids = running_processes(bundle_id).map(&:first)
          next if pids.none?

          if hosting_brew?(bundle_id)
            opoo "Skipping signalling application '#{bundle_id}' as `brew` is running inside it."
            next
          end

          pids.select! do |pid|
            uid = AbstractUninstall.owner_uid(pid)
            next true if uid == Process.uid

            reason = uid.nil? ? "its owner could not be determined" : "it is owned by another user"
            odebug "Skipping signalling PID #{pid} for '#{bundle_id}': #{reason}."
            false
          end
          next if pids.none?

          ohai "Signalling '#{signal}' to application ID '#{bundle_id}'"

          # Note that unlike :quit, signals are sent from the current user (not
          # upgraded to the superuser). This is a todo item for the future, but
          # there should be some additional thought/safety checks about that, as a
          # misapplied "kill" by root could bring down the system. The fact that we
          # learned the pid from AppleScript is already some degree of protection,
          # though indirect.
          odebug "Unix ids are #{pids.inspect} for processes with bundle identifier #{bundle_id}"
          begin
            Process.kill(signal, *pids)
          rescue Errno::EPERM => e
            opoo "Failed to kill #{bundle_id} PIDs #{pids.join(", ")} with signal #{signal}: #{e}"
          end
          sleep 3
        end
      end

      sig {
        params(
          login_items: T.any(String, T::Hash[Symbol, T.any(String, Pathname)]),
          command:     T.nilable(T.class_of(SystemCommand)),
          successor:   T.nilable(Cask),
          _kwargs:     T.anything,
        ).void
      }
      def uninstall_login_item(*login_items, command: nil, successor: nil, **_kwargs)
        return if successor

        apps = cask.artifacts.select { |a| a.class.dsl_key == :app }
        derived_login_items = apps.map { |a| { path: a.target } }

        [*derived_login_items, *login_items].each do |item|
          type, id = if item.respond_to?(:key) && item.key?(:path)
            ["path", item[:path]]
          else
            ["name", item]
          end

          ohai "Removing login item #{id}"

          result = system_command(
            "osascript",
            args: [
              "-e",
              %Q(tell application "System Events" to delete every login item whose #{type} is #{id.to_s.inspect}),
            ],
          )

          opoo "Removal of login item #{id} failed. #{automation_access_instructions}" unless result.success?

          sleep 1
        end
      end

      # :kext should be unloaded before attempting to delete the relevant file
      sig { params(kexts: String, command: T.nilable(T.class_of(SystemCommand)), _kwargs: T.anything).void }
      def uninstall_kext(*kexts, command: nil, **_kwargs)
        kexts.each do |kext|
          ohai "Unloading kernel extension #{kext}"
          is_loaded = system_command!(
            "/usr/sbin/kextstat",
            args:         ["-l", "-b", kext],
            sudo:         true,
            sudo_as_root: true,
          ).stdout
          if is_loaded.length > 1
            system_command!(
              "/sbin/kextunload",
              args:         ["-b", kext],
              sudo:         true,
              sudo_as_root: true,
            )
            sleep 1
          end
          found_kexts = system_command!(
            "/usr/sbin/kextfind",
            args:         ["-b", kext],
            sudo:         true,
            sudo_as_root: true,
          ).stdout.chomp.lines
          found_kexts.each do |kext_path|
            ohai "Removing kernel extension #{kext_path}"
            system_command!(
              "/bin/rm",
              args:         ["-rf", kext_path],
              sudo:         true,
              sudo_as_root: true,
            )
          end
        end
      end

      # :script must come before :pkgutil, :delete, or :trash so that the script file is not already deleted
      sig {
        params(
          directives:     DirectivesType,
          command:        T.class_of(SystemCommand),
          directive_name: Symbol,
          force:          T::Boolean,
          _kwargs:        T.anything,
        ).void
      }
      def uninstall_script(directives, command:, directive_name: :script, force: false, **_kwargs)
        # TODO: Create a common `Script` class to run this and Artifact::Installer.
        executable, script_arguments = self.class.read_script_arguments(directives,
                                                                        "uninstall",
                                                                        { must_succeed: true, sudo: false },
                                                                        { print_stdout: true },
                                                                        directive_name)

        ohai "Running uninstall script #{executable}"
        raise CaskInvalidError.new(cask, "#{stanza} :#{directive_name} without :executable.") if executable.nil?

        executable_path = staged_path_join_executable(executable)

        if (executable_path.absolute? && !executable_path.exist?) ||
           (!executable_path.absolute? && which(executable_path.to_s).nil?)
          message = "uninstall script #{executable} does not exist"
          raise CaskError, "#{message}." unless force

          opoo "#{message}; skipping."
          return
        end

        command.run(executable_path, **script_arguments)
        sleep 1
      end

      sig { params(pkgs: String, command: T.class_of(SystemCommand), _kwargs: T.anything).void }
      def uninstall_pkgutil(*pkgs, command:, **_kwargs)
        ohai "Uninstalling packages with `sudo` (which may request your password)..."
        pkgs.each do |regex|
          ::Cask::Pkg.all_matching(regex, command).each do |pkg|
            puts pkg.package_id
            pkg.uninstall
          end
        end
      end

      sig { params(paths: T.any(Pathname, String), command: T.class_of(SystemCommand), _kwargs: T.anything).void }
      def uninstall_delete(*paths, command:, **_kwargs)
        return if paths.empty?

        ohai "Removing files:"
        each_resolved_path(:delete, paths) do |path, resolved_paths|
          puts path
          command.run!(
            "/usr/bin/xargs",
            args:  ["-0", "--", "/bin/rm", "-r", "-f", "--"],
            input: resolved_paths.join("\0"),
            sudo:  true,
          )
        end
      end

      sig {
        params(
          paths:   T.any(Pathname, String),
          command: T.nilable(T.class_of(SystemCommand)),
          _kwargs: T.anything,
        ).void
      }
      def uninstall_trash(*paths, command: nil, **_kwargs)
        return if paths.empty?

        resolved_paths = each_resolved_path(:trash, paths).to_a

        ohai "Trashing files:", resolved_paths.map(&:first)
        trash_paths(*resolved_paths.flat_map(&:last), command:)
      end

      sig {
        params(paths: Pathname, command: T.nilable(T.class_of(SystemCommand)))
          .returns(T.nilable([T::Array[String], T::Array[String]]))
      }
      def trash_paths(*paths, command: nil)
        return if paths.empty?

        trashed, untrashable = ::Cask::Utils::Trash.trash(*paths, command:)

        return trashed, untrashable if untrashable.empty?

        opoo "The following files could not be trashed, please do so manually:"
        $stderr.puts untrashable

        [trashed, untrashable]
      end

      sig { params(directories: Pathname).returns(T::Boolean) }
      def all_dirs?(*directories)
        directories.all?(&:directory?)
      end

      sig { params(directories: Pathname, command: T.class_of(SystemCommand)).void }
      def recursive_rmdir(*directories, command:)
        directories.all? do |resolved_path|
          puts resolved_path.sub(Dir.home, "~")
          next false if resolved_path.symlink?

          if resolved_path.readable?
            children = resolved_path.children

            next false unless children.all? { |child| child.directory? || child.basename.to_s == ".DS_Store" }
          else
            lines = command.run!("/bin/ls", args: ["-A", "-F", "--", resolved_path], sudo: true, print_stderr: false)
                           .stdout.lines.map(&:chomp)
                           .flat_map(&:chomp)

            # Using `-F` above outputs directories ending with `/`.
            next false unless lines.all? { |l| l.end_with?("/") || l == ".DS_Store" }

            children = lines.map { |l| resolved_path/l.delete_suffix("/") }
          end

          # Directory counts as empty if it only contains a `.DS_Store`.
          if children.include?(ds_store = resolved_path/".DS_Store")
            Utils.gain_permissions_remove(ds_store, command:)
            children.delete(ds_store)
          end

          next false unless recursive_rmdir(*children, command:)

          begin
            Utils.gain_permissions_rmdir(resolved_path, command:)
          rescue Errno::ENOTEMPTY, ErrorDuringExecution
            next false
          end

          true
        end
      end

      sig {
        params(
          directories: T.any(Pathname, String),
          command:     T.class_of(SystemCommand),
          _kwargs:     T.anything,
        ).void
      }
      def uninstall_rmdir(*directories, command:, **_kwargs)
        return if directories.empty?

        ohai "Removing directories if empty:"

        each_resolved_path(:rmdir, directories) do |_path, resolved_paths|
          next unless resolved_paths.all?(&:directory?)

          recursive_rmdir(*resolved_paths, command:)
        end
      end

      sig { params(target: Pathname).returns(T::Boolean) }
      def undeletable?(target)
        !target.parent.writable?
      end
    end
  end
end

require "extend/os/cask/artifact/abstract_uninstall"
