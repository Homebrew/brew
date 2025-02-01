# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "timeout"

require "utils/user"
require "cask/artifact/abstract_artifact"
require "cask/pkg"
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

      def self.from_args(cask, **directives)
        new(cask, **directives)
      end

      attr_reader :directives

      def initialize(cask, **directives)
        directives.assert_valid_keys(*ORDERED_DIRECTIVES)

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

      def to_h
        directives.to_h
      end

      sig { override.returns(String) }
      def summarize
        to_h.flat_map { |key, val| Array(val).map { |v| "#{key.inspect} => #{v.inspect}" } }.join(", ")
      end

      private

      def dispatch_uninstall_directives(**options)
        ORDERED_DIRECTIVES.each do |directive_sym|
          dispatch_uninstall_directive(directive_sym, **options)
        end
      end

      def dispatch_uninstall_directive(directive_sym, **options)
        return unless directives.key?(directive_sym)

        args = directives[directive_sym]

        send(:"uninstall_#{directive_sym}", *(args.is_a?(Hash) ? [args] : args), **options)
      end

      def stanza
        self.class.dsl_key
      end

      # Preserve prior functionality of script which runs first. Should rarely be needed.
      # :early_script should not delete files, better defer that to :script.
      # If cask writers never need :early_script it may be removed in the future.
      def uninstall_early_script(directives, **options)
        uninstall_script(directives, directive_name: :early_script, **options)
      end

      # :launchctl must come before :quit/:signal for cases where app would instantly re-launch
      def uninstall_launchctl(*services, command: nil, **_)
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
            plist_status = command.run(
              "/bin/launchctl",
              args:         ["list", service],
              sudo:,
              sudo_as_root: sudo,
              print_stderr: false,
            ).stdout
            if plist_status.start_with?("{")
              result = command.run(
                "/bin/launchctl",
                args:         ["remove", service],
                must_succeed: sudo,
                sudo:,
                sudo_as_root: sudo,
              )
              next if !sudo && !result.success?

              sleep 1
            end
            paths = [
              "/Library/LaunchAgents/#{service}.plist",
              "/Library/LaunchDaemons/#{service}.plist",
            ]
            paths.each { |elt| elt.prepend(Dir.home).freeze } unless sudo
            paths = paths.map { |elt| Pathname(elt) }.select(&:exist?)
            paths.each do |path|
              command.run!("/bin/rm", args: ["-f", "--", path], sudo:, sudo_as_root: sudo)
            end
            # undocumented and untested: pass a path to uninstall :launchctl
            next unless Pathname(service).exist?

            command.run!(
              "/bin/launchctl",
              args:         ["unload", "-w", "--", service],
              sudo:,
              sudo_as_root: sudo,
            )
            command.run!(
              "/bin/rm",
              args:         ["-f", "--", service],
              sudo:,
              sudo_as_root: sudo,
            )
            sleep 1
          end
        end
      end

      def running_processes(bundle_id)
        system_command!("/bin/launchctl", args: ["list"])
          .stdout.lines.drop(1)
          .map { |line| line.chomp.split("\t") }
          .map { |pid, state, id| [pid.to_i, state.to_i, id] }
          .select do |(pid, _, id)|
            pid.nonzero? && /\A(?:application\.)?#{Regexp.escape(bundle_id)}(?:\.\d+){0,2}\Z/.match?(id)
          end
      end

      def find_launchctl_with_wildcard(search)
        regex = Regexp.escape(search).gsub("\\*", ".*")
        system_command!("/bin/launchctl", args: ["list"])
          .stdout.lines.drop(1) # skip stdout column headers
          .filter_map do |line|
            pid, _state, id = line.chomp.split(/\s+/)
            id if pid.to_i.nonzero? && id.match?(regex)
          end
      end

      sig { returns(String) }
      def automation_access_instructions
        navigation_path = if MacOS.version >= :ventura
          "System Settings → Privacy & Security"
        else
          "System Preferences → Security & Privacy → Privacy"
        end

        <<~EOS
          Enable Automation access for "Terminal → System Events" in:
            #{navigation_path} → Automation
          if you haven't already.
        EOS
      end

      # :quit/:signal must come before :kext so the kext will not be in use by a running process
      def uninstall_quit(*bundle_ids, command: nil, **_)
        bundle_ids.each do |bundle_id|
          next unless running?(bundle_id)

          unless T.must(User.current).gui?
            opoo "Not logged into a GUI; skipping quitting application ID '#{bundle_id}'."
            next
          end

          ohai "Quitting application '#{bundle_id}'..."

          begin
            Timeout.timeout(10) do
              Kernel.loop do
                next unless quit(bundle_id).success?

                next if running?(bundle_id)

                puts "Application '#{bundle_id}' quit successfully."
                break
              end
            end
          rescue Timeout::Error
            opoo "Application '#{bundle_id}' did not quit. #{automation_access_instructions}"
          end
        end
      end

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
                                    print_stderr: true).status.success?
      end

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
      def uninstall_signal(*signals, command: nil, **_)
        signals.each do |pair|
          raise CaskInvalidError.new(cask, "Each #{stanza} :signal must consist of 2 elements.") if pair.size != 2

          signal, bundle_id = pair
          ohai "Signalling '#{signal}' to application ID '#{bundle_id}'"
          pids = running_processes(bundle_id).map(&:first)
          next if pids.none?

          # Note that unlike :quit, signals are sent from the current user (not
          # upgraded to the superuser). This is a todo item for the future, but
          # there should be some additional thought/safety checks about that, as a
          # misapplied "kill" by root could bring down the system. The fact that we
          # learned the pid from AppleScript is already some degree of protection,
          # though indirect.
          # TODO: check the user that owns the PID and don't try to kill those from other users.
          odebug "Unix ids are #{pids.inspect} for processes with bundle identifier #{bundle_id}"
          begin
            Process.kill(signal, *pids)
          rescue Errno::EPERM => e
            opoo "Failed to kill #{bundle_id} PIDs #{pids.join(", ")} with signal #{signal}: #{e}"
          end
          sleep 3
        end
      end

      def uninstall_login_item(*login_items, command: nil, successor: nil, **_)
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
      def uninstall_kext(*kexts, command: nil, **_)
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
      def uninstall_script(directives, directive_name: :script, force: false, command: nil, **_)
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
           (!executable_path.absolute? && (which executable_path).nil?)
          message = "uninstall script #{executable} does not exist"
          raise CaskError, "#{message}." unless force

          opoo "#{message}; skipping."
          return
        end

        command.run(executable_path, **script_arguments)
        sleep 1
      end

      def uninstall_pkgutil(*pkgs, command: nil, **_)
        ohai "Uninstalling packages with sudo; the password may be necessary:"
        pkgs.each do |regex|
          ::Cask::Pkg.all_matching(regex, command).each do |pkg|
            puts pkg.package_id
            pkg.uninstall
          end
        end
      end

      def each_resolved_path(action, paths)
        return enum_for(:each_resolved_path, action, paths) unless block_given?

        paths.each do |path|
          resolved_path = Pathname.new(path)

          resolved_path = resolved_path.expand_path if path.to_s.start_with?("~")

          if resolved_path.relative? || resolved_path.split.any? { |part| part.to_s == ".." }
            opoo "Skipping #{Formatter.identifier(action)} for relative path '#{path}'."
            next
          end

          if undeletable?(resolved_path)
            opoo "Skipping #{Formatter.identifier(action)} for undeletable path '#{path}'."
            next
          end

          begin
            yield path, Pathname.glob(resolved_path)
          rescue Errno::EPERM
            raise if File.readable?(File.expand_path("~/Library/Application Support/com.apple.TCC"))

            navigation_path = if MacOS.version >= :ventura
              "System Settings → Privacy & Security"
            else
              "System Preferences → Security & Privacy → Privacy"
            end

            odie "Unable to remove some files. Please enable Full Disk Access for your terminal under " \
                 "#{navigation_path} → Full Disk Access."
          end
        end
      end

      def uninstall_delete(*paths, command: nil, **_)
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

      def uninstall_trash(*paths, **options)
        return if paths.empty?

        resolved_paths = each_resolved_path(:trash, paths).to_a

        ohai "Trashing files:", resolved_paths.map(&:first)
        trash_paths(*resolved_paths.flat_map(&:last), **options)
      end

      def trash_paths(*paths, command: nil, **_)
        return if paths.empty?

        stdout, = system_command HOMEBREW_LIBRARY_PATH/"cask/utils/trash.swift",
                                 args:         paths,
                                 print_stderr: Homebrew::EnvConfig.developer?

        trashed, _, untrashable = stdout.partition("\n")
        trashed = trashed.split(":")
        untrashable = untrashable.split(":")

        trashed_with_permissions, untrashable = untrashable.partition do |path|
          Utils.gain_permissions(path, ["-R"], SystemCommand) do
            system_command! HOMEBREW_LIBRARY_PATH/"cask/utils/trash.swift",
                            args:         [path],
                            print_stderr: Homebrew::EnvConfig.developer?
          end

          true
        rescue
          false
        end

        trashed += trashed_with_permissions

        return trashed, untrashable if untrashable.empty?

        opoo "The following files could not be trashed, please do so manually:"
        $stderr.puts untrashable

        [trashed, untrashable]
      end

      def all_dirs?(*directories)
        directories.all?(&:directory?)
      end

      def recursive_rmdir(*directories, command: nil, **_)
        directories.all? do |resolved_path|
          puts resolved_path.sub(Dir.home, "~")

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
          if children.include?((ds_store = resolved_path/".DS_Store"))
            Utils.gain_permissions_remove(ds_store, command:)
            children.delete(ds_store)
          end

          next false unless recursive_rmdir(*children, command:)

          Utils.gain_permissions_rmdir(resolved_path, command:)

          true
        end
      end

      def uninstall_rmdir(*directories, **kwargs)
        return if directories.empty?

        ohai "Removing directories if empty:"

        each_resolved_path(:rmdir, directories) do |_path, resolved_paths|
          next unless resolved_paths.all?(&:directory?)

          recursive_rmdir(*resolved_paths, **kwargs)
        end
      end

      def undeletable?(target); end
    end
  end
end

require "extend/os/cask/artifact/abstract_uninstall"
