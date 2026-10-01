# typed: strict
# frozen_string_literal: true

require "system_command"

require "services/formula_wrapper"
require "fileutils"
require "utils/output"

module Homebrew
  module Services
    module Cli
      extend FileUtils
      extend Utils::Output::Mixin

      sig { returns(T.nilable(String)) }
      def self.sudo_service_user
        @sudo_service_user
      end

      sig { params(sudo_service_user: String).void }
      def self.sudo_service_user=(sudo_service_user)
        @sudo_service_user = T.let(sudo_service_user, T.nilable(String))
      end

      # Binary name.
      sig { returns(String) }
      def self.bin
        "brew services"
      end

      # Find all currently running services via launchctl list or systemctl list-units.
      sig { returns(T::Array[String]) }
      def self.running
        if System.launchctl?
          Utils.popen_read(System.launchctl, "list")
        else
          System::Systemctl.popen_read("list-units",
                                       "--type=service",
                                       "--state=running",
                                       "--no-pager",
                                       "--no-legend")
        end.chomp.split("\n").filter_map do |svc|
          svc[/(?:homebrew(?>\.mxcl)?|sh\.brew)\.[\w+-.@]+/]&.delete_suffix(".service")
        end
      end

      # Check if formula has been found.
      sig { params(targets: T::Array[Services::FormulaWrapper]).returns(T::Boolean) }
      def self.check!(targets)
        raise UsageError, "Formula(e) missing, please provide a formula name or use `--all`." if targets.empty?

        true
      end

      sig { params(service: Services::FormulaWrapper, running_status: String).returns(T::Boolean) }
      def self.report_service_running_or_loaded?(service, running_status:)
        running = service.pid?
        loaded_name = if running
          service.active_service_name
        else
          service.loaded_service_names.find { |name| name != service.service_name }
        end

        if loaded_name.present? && loaded_name != service.service_name
          if service.service_file_generated? && service.service_names.include?(loaded_name)
            puts "Service `#{service.name}` is already loaded as `#{loaded_name}`; " \
                 "a service label migration is pending. Use `#{bin} restart #{service.name}` " \
                 "to migrate to `#{service.service_name}`."
          else
            status = running ? running_status : "loaded"
            puts "Service `#{service.name}` already #{status} " \
                 "(label: #{loaded_name}), use `#{bin} restart #{service.name}` to restart."
          end
          return true
        end

        status = if running
          running_status
        end
        return false if status.nil?

        puts "Service `#{service.name}` already #{status}, use `#{bin} restart #{service.name}` to restart."
        true
      end

      # Kill services that don't have a service file
      sig { returns(T::Array[String]) }
      def self.kill_orphaned_services
        cleaned_labels = []
        cleaned_services = []
        running.each do |label|
          if (service = FormulaWrapper.from(label))
            unless service.dest.file?
              cleaned_labels << label
              cleaned_services << service
            end
          else
            opoo "Service #{label} not managed by `#{bin}` => skipping"
          end
        end
        kill(cleaned_services)
        cleaned_labels
      end

      sig { returns(T::Array[String]) }
      def self.remove_unused_service_files
        cleaned = []
        running_services = running
        System.path.glob("{homebrew.*,sh.brew.*}.{plist,service,timer}").each do |file|
          label = FormulaWrapper.service_file_label(file) if file.extname.casecmp?(".plist")
          service_name = label || File.basename(file).sub(/\.(?:plist|service|timer)$/i, "")
          next if running_services.include?(service_name)
          next if System.systemctl? && !file.extname.casecmp?(".plist") &&
                  System::Systemctl.quiet_run("status", "#{service_name}.timer")
          next if label && System.launchctl? && System.launchctl_service_running?(label)

          puts "Removing unused service file: #{file}"
          rm file
          cleaned << file.to_s
        end

        cleaned
      end

      sig {
        params(
          service:        Services::FormulaWrapper,
          disabled_units: T::Array[String],
        ).void
      }
      private_class_method def self.remove_service_files(service, disabled_units: [])
        files = service.destinations
        files += service.timer_destinations if System.systemctl? && service.timed?
        files.each do |file|
          next unless file.exist?

          unit_name = file.basename.to_s
          if System.systemctl? && disabled_units.exclude?(unit_name)
            System::Systemctl.quiet_run("disable", unit_name)
          end
          rm file
        end
      end

      # Run a service as defined in the formula. This does not clean the service file like `start` does.
      sig {
        params(
          targets:      T::Array[Services::FormulaWrapper],
          service_file: T.nilable(String),
          verbose:      T::Boolean,
        ).void
      }
      def self.run(targets, service_file = nil, verbose: false)
        if service_file.present?
          file = Pathname.new service_file
          raise UsageError, "Provided service file does not exist." unless file.exist?
        end

        targets.each do |service|
          next if report_service_running_or_loaded?(service, running_status: "running")

          if System.root?
            puts "Service `#{service.name}` cannot be run (but can be started) as root."
            next
          end

          service_load(service, file, enable: false)
        end
      end

      # Start a service.
      sig {
        params(
          targets:      T::Array[Services::FormulaWrapper],
          service_file: T.nilable(String),
          verbose:      T::Boolean,
        ).void
      }
      def self.start(targets, service_file = nil, verbose: false)
        file = T.let(nil, T.nilable(Pathname))

        if service_file.present?
          file = Pathname.new service_file
          raise UsageError, "Provided service file does not exist." unless file.exist?
        end

        targets.each do |service|
          next if report_service_running_or_loaded?(service, running_status: "started")

          odie "Formula `#{service.name}` is not installed." unless service.installed?

          file ||= if service.source_service_file.exist? || System.systemctl?
            nil
          elsif service.formula.opt_prefix.exist? &&
                (keg = Keg.for service.formula.opt_prefix) &&
                keg.plist_installed?
            service_file = Dir["#{keg}/*#{service.service_file.extname}"].first
            Pathname.new service_file if service_file.present?
          end

          install_service_file(service, file)

          if !file && verbose
            ohai "Generated service file for #{service.formula.name}:"
            puts "   #{service.dest.read.gsub("\n", "\n   ")}"
            puts
          end

          # Never skip loading when ownership was taken, otherwise
          # only skip a `--sudo-service-user` service when not root.
          root_ownership_taken = take_root_ownership?(service)
          next if !root_ownership_taken && sudo_service_user && !System.root?

          service_load(service, nil, enable: true)
        end
      end

      # Stop a service and unload it.
      sig {
        params(
          targets:  T::Array[Services::FormulaWrapper],
          verbose:  T::Boolean,
          no_wait:  T::Boolean,
          max_wait: T.any(Integer, Float),
          keep:     T::Boolean,
        ).void
      }
      def self.stop(targets, verbose: false, no_wait: false, max_wait: 0, keep: false)
        targets.each do |service|
          loaded = service.loaded?
          running = !loaded && service.pid?
          if !loaded && !running
            remove_service_files(service) unless keep
            if service.service_file_present?
              odie <<~EOS
                Service `#{service.name}` is started as `#{service.owner}`. Try:
                  #{"sudo " unless System.root?}#{bin} stop #{service.name}
              EOS
            elsif System.launchctl? && (stopped_name = service.service_names.find do |name|
              SystemCommand.quiet_system(System.launchctl, "bootout", "#{System.domain_target}/#{name}")
            end)
              ohai "Successfully stopped `#{service.name}` (label: #{stopped_name})"
            else
              opoo "Service `#{service.name}` is not started."
            end
            next
          end

          systemctl_args = []
          systemctl_stop_results = T.let([], T::Array[T::Boolean])
          disabled_units = T.let([], T::Array[String])
          loaded_service_names = service.loaded_service_names
          loaded_service_names = [service.active_service_name] if loaded_service_names.empty? && running
          if no_wait
            systemctl_args << "--no-block"
            puts "Stopping `#{service.name}`..."
          else
            puts "Stopping `#{service.name}`... (might take a while)"
          end

          if System.systemctl?
            loaded_service_names.each do |service_name|
              if keep
                if service.timed?
                  systemctl_stop_results << System::Systemctl.quiet_run(
                    *systemctl_args, "stop", "#{service_name}.timer"
                  )
                end
                systemctl_stop_results << System::Systemctl.quiet_run(*systemctl_args, "stop", service_name)
              elsif service.timed?
                timer_name = "#{service_name}.timer"
                result = System::Systemctl.quiet_run(*systemctl_args, "disable", "--now", timer_name)
                systemctl_stop_results << result
                disabled_units << timer_name if result

                result = System::Systemctl.quiet_run(*systemctl_args, "disable", "--now", service_name)
                systemctl_stop_results << result
                disabled_units << "#{service_name}.service" if result
              else
                result = System::Systemctl.quiet_run(*systemctl_args, "disable", "--now", service_name)
                systemctl_stop_results << result
                disabled_units << "#{service_name}.service" if result
              end
            end
          elsif System.launchctl?
            launchctl = System.launchctl
            raise "launchctl is unavailable" if launchctl.nil?

            dont_wait_statuses = [
              Errno::ESRCH::Errno,
              System::LAUNCHCTL_DOMAIN_ACTION_NOT_SUPPORTED,
            ]
            loaded_service_names.each do |service_name|
              System.candidate_domain_targets.each do |domain_target|
                break unless System.launchctl_service_running?(service_name)

                if no_wait
                  SystemCommand.quiet_system launchctl, "bootout", "#{domain_target}/#{service_name}"
                else
                  time_slept = 0
                  sleep_time = 1
                  exit_status = SystemCommand.run(
                    launchctl,
                    args:         ["bootout", "#{domain_target}/#{service_name}"],
                    print_stderr: false,
                    debug:        false,
                    verbose:      false,
                  ).exit_status
                  while dont_wait_statuses.exclude?(exit_status) &&
                        (exit_status == Errno::EINPROGRESS::Errno ||
                         System.launchctl_service_running?(service_name)) &&
                        (max_wait.zero? || time_slept < max_wait)
                    sleep(sleep_time)
                    time_slept += sleep_time
                    exit_status = SystemCommand.run(
                      launchctl,
                      args:         ["bootout", "#{domain_target}/#{service_name}"],
                      print_stderr: false,
                      debug:        false,
                      verbose:      false,
                    ).exit_status
                  end
                end
                SystemCommand.quiet_system launchctl, "stop", service_name if
                  System.launchctl_service_running?(service_name)
              end
            end
          end

          service.reset_cache!

          service_still_loaded = if System.systemctl?
            if no_wait && systemctl_stop_results.present? && systemctl_stop_results.all?
              false
            else
              service.loaded? || service.pid?
            end
          else # System.launchctl?
            loaded_service_names.any? { |service_name| System.launchctl_service_running?(service_name) }
          end

          if !keep && !service_still_loaded
            remove_service_files(service, disabled_units:)
            # Run daemon-reload on systemctl to finish unloading stopped and deleted service.
            System::Systemctl.run(*systemctl_args, "daemon-reload") if System.systemctl?
          end

          labels = loaded_service_names.presence || service.service_names
          if service_still_loaded
            opoo "Unable to stop `#{service.name}` (label: #{labels.join(", ")})"
          else
            ohai "Successfully stopped `#{service.name}` (label: #{labels.join(", ")})"
          end
        end
      end

      # Stop a service but keep it registered.
      sig { params(targets: T::Array[Services::FormulaWrapper], verbose: T::Boolean).void }
      def self.kill(targets, verbose: false)
        targets.each do |service|
          if !service.pid?
            puts "Service `#{service.name}` is not started."
          elsif service.keep_alive?
            puts "Service `#{service.name}` is set to automatically restart and can't be killed."
          else
            puts "Killing `#{service.name}`... (might take a while)"
            killed_service_names = service.loaded_service_names.presence || [service.active_service_name]
            if System.systemctl?
              killed_service_names.each { |service_name| System::Systemctl.quiet_run("stop", service_name) }
            elsif System.launchctl?
              killed_service_names.each do |service_name|
                SystemCommand.quiet_system System.launchctl, "stop", service_name
              end
            end
            service.reset_cache!

            if service.pid?
              opoo "Unable to kill `#{service.name}` (label: #{killed_service_names.join(", ")})"
            else
              ohai "Successfully killed `#{service.name}` (label: #{killed_service_names.join(", ")})"
            end
          end
        end
      end

      # protections to avoid users editing root services
      sig { params(service: Services::FormulaWrapper).returns(T::Boolean) }
      def self.take_root_ownership?(service)
        return false unless System.root?
        return false if sudo_service_user

        root_paths = T.let([], T::Array[Pathname])

        if System.systemctl?
          group = "root"
        elsif System.launchctl?
          group = "admin"
          chown "root", group, service.dest
          require "plist"
          plist_data = service.dest.read
          plist = begin
            Plist.parse_xml(plist_data, marshal: false)
          rescue
            nil
          end
          return false unless plist

          program_location = plist["ProgramArguments"]&.first
          key = "first ProgramArguments value"
          if program_location.blank?
            program_location = plist["Program"]
            key = "Program"
          end

          if program_location.present?
            Dir.chdir("/") do
              if File.exist?(program_location)
                program_location_path = Pathname(program_location).realpath
                root_paths += [
                  program_location_path,
                  program_location_path.parent.realpath,
                ]
              else
                opoo <<~EOS
                  #{service.name}: the #{key} does not exist:
                    #{program_location}
                EOS
              end
            end
          end
        end

        if (formula = service.formula)
          root_paths += [
            formula.opt_prefix,
            formula.linked_keg,
            formula.bin,
            formula.sbin,
          ]
        end
        root_paths = root_paths.sort.uniq.select(&:exist?)

        opoo <<~EOS
          Taking root:#{group} ownership of some #{service.formula} paths:
            #{root_paths.join("\n  ")}
          This will require manual removal of these paths using `sudo rm` on
          brew upgrade/reinstall/uninstall.
        EOS
        chown "root", group, root_paths
        chmod "+t", root_paths
        true
      end

      sig {
        params(
          service: Services::FormulaWrapper,
          file:    T.nilable(T.any(String, Pathname)),
          enable:  T::Boolean,
        ).returns(String)
      }
      def self.launchctl_load(service, file:, enable:)
        service_name = FormulaWrapper.service_file_label(file) || service.service_name
        if enable
          SystemCommand.safe_system System.launchctl, "enable",
                                    "#{System.domain_target}/#{service_name}"
        end
        SystemCommand.safe_system System.launchctl, "bootstrap", System.domain_target, file
        service_name
      end

      sig { params(service: Services::FormulaWrapper, enable: T::Boolean).void }
      def self.systemd_load(service, enable:)
        System::Systemctl.run("start", service.service_name)
        if service.timed?
          System::Systemctl.run("start", service.timer_name)
          System::Systemctl.run("enable", service.timer_name) if enable
        elsif enable
          System::Systemctl.run("enable", service.service_name)
        end
      end

      sig { params(service: Services::FormulaWrapper, file: T.nilable(Pathname), enable: T::Boolean).void }
      def self.service_load(service, file, enable:)
        if System.root? && !service.service_startup? && !sudo_service_user
          opoo "`#{service.name}` must be run as non-root to start at user login!"
        elsif !System.root? && service.service_startup?
          opoo "`#{service.name}` must be run as root to start at system startup!"
        end

        if (service_user = sudo_service_user) && !System.user_exists?(service_user)
          function = enable ? "start" : "run"
          odie "Cannot #{function} `#{service.name}` as `#{service_user}` is not a user!"
        end

        loaded_service_name = service.service_name
        if System.launchctl?
          service.path_dirs.each(&:mkpath)
          if file.nil? && !enable && service.service_file_generated? &&
             (contents = service.service_contents) != service.source_service_file.read
            Tempfile.create([service.service_name, ".plist"]) do |tempfile|
              tempfile.write(contents)
              tempfile.flush
              loaded_service_name = launchctl_load(service, file: Pathname(tempfile.path), enable:)
            end
          else
            file ||= enable ? service.dest : service.source_service_file
            loaded_service_name = launchctl_load(service, file:, enable:)
          end
        elsif System.systemctl?
          # Systemctl loads based upon location so only install service
          # file when it is not installed. Used with the `run` command.
          install_service_file(service, file) unless service.dest.exist?
          service.path_dirs.each(&:mkpath)
          systemd_load(service, enable:)
        end

        function = enable ? "started" : "ran"
        ohai("Successfully #{function} `#{service.name}` (label: #{loaded_service_name})")
      end

      sig { params(service: Services::FormulaWrapper, file: T.nilable(Pathname)).void }
      def self.install_service_file(service, file)
        raise UsageError, "Formula `#{service.name}` is not installed." unless service.installed?

        unless service.source_service_file.exist?
          raise UsageError,
                "Formula `#{service.name}` has not implemented #plist, #service or provided a locatable service file."
        end

        temp = Tempfile.new(service.service_name)
        temp << if file.nil?
          contents = service.service_contents

          if sudo_service_user && System.launchctl?
            # set the username in the new plist file
            ohai "Setting username in #{service.service_name} to: #{sudo_service_user}"
            require "plist"
            plist_data = Plist.parse_xml(contents, marshal: false)
            plist_data["UserName"] = sudo_service_user
            plist_data.to_plist
          else
            contents
          end
        else
          file.read
        end
        temp.flush

        remove_service_files(service)
        service.dest_dir.mkpath unless service.dest_dir.directory?
        temp_path = temp.path
        raise "Could not create a temporary service file for `#{service.name}`." if temp_path.nil?

        cp temp_path, service.dest

        # Clear tempfile.
        temp.close

        chmod 0644, service.dest
        if System.systemctl? && service.timed?
          service.timer_dest.atomic_write(service.timer_contents)
          chmod 0644, service.timer_dest
        end

        System::Systemctl.run("daemon-reload") if System.systemctl?
      end
    end
  end
end
