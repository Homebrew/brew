# typed: strict
# frozen_string_literal: true

# Wrapper for a formula to handle service-related stuff like parsing and
# generating the service/plist files.
module Service
  class FormulaWrapper
    # Access the `Formula` instance.
    sig { returns(Formula) }
    attr_reader :formula

    # Create a new `Service` instance from either a path or label.
    sig { params(path_or_label: T.any(Pathname, String)).returns(T.nilable(FormulaWrapper)) }
    def self.from(path_or_label)
      return unless path_or_label =~ path_or_label_regex

      begin
        new(Formulary.factory(T.must(Regexp.last_match(1))))
      rescue
        nil
      end
    end

    # Initialize a new `Service` instance with supplied formula.
    sig { params(formula: Formula).void }
    def initialize(formula)
      @formula = T.let(formula, Formula)
      @service = T.let(@formula.service? || false, T::Boolean)
      @service_name = T.let(if System.launchctl?
                              formula.plist_name
                            elsif System.systemctl?
                              formula.service_name
      end, T.nilable(String))
      @service_file = T.let(if System.launchctl?
                              formula.launchd_service_path
                            elsif System.systemctl?
                              formula.systemd_service_path
      end, T.nilable(Pathname))
      @service_startup = T.let(
        if service?
          T.must(load_service).requires_root?
        else
          false
        end, T.nilable(T::Boolean)
      )
      @name = T.let(formula.name, String)
    end

    # Delegate access to `formula.name`.
    sig { returns(String) }
    attr_reader :name

    # Delegate access to `formula.service?`.
    sig { returns(T::Boolean) }
    def service?
      @service
    end

    # Delegate access to `formula.service.timed?`.
    sig { returns(T.nilable(T::Boolean)) }
    def timed?
      @timed ||= T.let(service? ? T.must(load_service).timed? : nil, T.nilable(T::Boolean))
    end

    # Delegate access to `formula.service.keep_alive?`.`
    sig { returns(T.nilable(T::Boolean)) }
    def keep_alive?
      @keep_alive ||= T.let(T.must(load_service).keep_alive?, T.nilable(T::Boolean)) if service?
    end

    # service_name delegates with formula.plist_name or formula.service_name for systemd (e.g., `homebrew.<formula>`).
    sig { returns(T.nilable(String)) }
    attr_reader :service_name

    # service_file delegates with formula.launchd_service_path or formula.systemd_service_path for systemd.
    sig { returns(T.nilable(Pathname)) }
    attr_reader :service_file

    # Whether the service should be launched at startup
    sig { returns(T.nilable(T::Boolean)) }
    def service_startup?
      @service_startup ||= service? ? T.must(load_service).requires_root? : false
    end

    # Path to destination service directory. If run as root, it's `boot_path`, else `user_path`.
    sig { returns(Pathname) }
    def dest_dir
      System.root? ? T.must(System.boot_path) : T.must(System.user_path)
    end

    # Path to destination service. If run as root, it's in `boot_path`, else `user_path`.
    sig { returns(Pathname) }
    def dest
      dest_dir + T.must(service_file).basename
    end

    # Returns `true` if any version of the formula is installed.
    sig { returns(T::Boolean) }
    def installed?
      formula.any_version_installed?
    end

    # Returns `true` if the plist file exists.
    sig { returns(T::Boolean) }
    def plist?
      return false unless installed?
      return true if T.must(service_file).file?
      return false unless formula.opt_prefix.exist?
      return true if Keg.for(formula.opt_prefix).plist_installed?

      false
    rescue NotAKegError
      false
    end

    # Returns `true` if the service is loaded, else false.
    sig { params(cached: T::Boolean).returns(T.nilable(T::Boolean)) }
    def loaded?(cached: false)
      if System.launchctl?
        @status_output_success_type = nil unless cached
        _, status_success, = status_output_success_type
        status_success
      elsif System.systemctl?
        System::Systemctl.quiet_run("status", T.must(service_file).basename)
      end
    end

    # Returns `true` if service is present (e.g. .plist is present in boot or user service path), else `false`
    # Accepts Hash option `:for` with values `:root` for boot path or `:user` for user path.
    sig { params(opts: T.untyped).returns(T::Boolean) }
    def service_file_present?(opts = { for: false })
      if opts[:for] && opts[:for] == :root
        boot_path_service_file_present?
      elsif opts[:for] && opts[:for] == :user
        user_path_service_file_present?
      else
        boot_path_service_file_present? || user_path_service_file_present?
      end
    end

    sig { returns(T.nilable(String)) }
    def owner
      if System.launchctl? && dest.exist?
        # read the username from the plist file
        plist = begin
          Plist.parse_xml(dest.read, marshal: false)
        rescue
          nil
        end
        plist_username = plist["UserName"] if plist

        return plist_username if plist_username.present?
      end
      return "root" if boot_path_service_file_present?
      return System.user if user_path_service_file_present?

      nil
    end

    sig { returns(T::Boolean) }
    def pid?
      return false if pid.nil?

      !T.must(pid).zero?
    end

    sig { returns(T.nilable(T.any(T::Boolean, Integer))) }
    def error?
      return false if pid? || pid.nil?
      return exit_code if exit_code.nil?

      T.must(exit_code).nonzero?
    end

    sig { returns(T.nilable(T::Boolean)) }
    def unknown_status?
      status_output.blank? && !pid?
    end

    # Get current PID of daemon process from status output.
    sig { returns(T.nilable(Integer)) }
    def pid
      status_output, _, status_type = status_output_success_type
      Regexp.last_match(1).to_i if status_output =~ pid_regex(status_type)
    end

    # Get current exit code of daemon process from status output.
    sig { returns(T.nilable(Integer)) }
    def exit_code
      status_output, _, status_type = status_output_success_type
      Regexp.last_match(1).to_i if status_output =~ exit_code_regex(status_type)
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def to_hash
      hash = {
        name:,
        service_name:,
        running:      pid?,
        loaded:       loaded?(cached: true),
        schedulable:  timed?,
        pid:,
        exit_code:,
        user:         owner,
        status:       status_symbol,
        file:         service_file_present? ? dest : service_file,
      }

      return hash unless service?

      service = load_service

      return hash if T.must(service).command.blank?

      hash[:command] = T.must(service).manual_command
      hash[:working_dir] = T.must(service).working_dir
      hash[:root_dir] = T.must(service).root_dir
      hash[:log_path] = T.must(service).log_path
      hash[:error_log_path] = T.must(service).error_log_path
      hash[:interval] = T.must(service).interval
      hash[:cron] = T.must(service).cron

      hash
    end

    private

    # The purpose of this function is to lazy load the Homebrew::Service class
    # and avoid nameclashes with the current Service module.
    # It should be used instead of calling formula.service directly.
    sig { returns(T.nilable(Homebrew::Service)) }
    def load_service
      require "formula"

      formula.service
    end

    sig { returns(T.nilable(T::Array[T.untyped])) }
    def status_output_success_type
      @status_output_success_type ||= T.let(nil, T.nilable(T::Array[T.untyped]))
      @status_output_success_type ||= if System.launchctl?
        cmd = [System.launchctl.to_s, "list", service_name]
        output = Utils.popen_read(*cmd).chomp
        if $CHILD_STATUS.present? && $CHILD_STATUS.success? && output.present?
          success = true
          odebug cmd.join(" "), output
          [output, success, :launchctl_list]
        else
          cmd = [System.launchctl.to_s, "print",
                 "#{System.domain_target}/#{service_name}"]
          output = Utils.popen_read(*cmd).chomp
          success = $CHILD_STATUS.present? && $CHILD_STATUS.success? && output.present?
          odebug cmd.join(" "), output
          [output, success, :launchctl_print]
        end
      elsif System.systemctl?
        cmd = ["status", service_name]
        output = System::Systemctl.popen_read(*cmd).chomp
        success = $CHILD_STATUS.present? && $CHILD_STATUS.success? && output.present?
        odebug [System::Systemctl.executable, System::Systemctl.scope, *cmd].join(" "),
               output
        [output, success, :systemctl]
      end
    end

    sig { returns(T.nilable(String)) }
    def status_output
      status_output, = status_output_success_type
      status_output
    end

    sig { returns(Symbol) }
    def status_symbol
      if pid?
        :started
      elsif !loaded?(cached: true)
        :none
      elsif T.must(exit_code).zero?
        if timed?
          :scheduled
        else
          :stopped
        end
      elsif error?
        :error
      elsif unknown_status?
        :unknown
      else
        :other
      end
    end

    sig { params(status_type: Symbol).returns(Regexp) }
    def exit_code_regex(status_type)
      @exit_code_regex ||= T.let({
        launchctl_list:  /"LastExitStatus"\ =\ ([0-9]*);/,
        launchctl_print: /last exit code = ([0-9]+)/,
        systemctl:       /\(code=exited, status=([0-9]*)\)|\(dead\)/,
      }, T.nilable(T::Hash[T.untyped, Regexp]))
      @exit_code_regex.fetch(status_type)
    end

    sig { params(status_type: Symbol).returns(Regexp) }
    def pid_regex(status_type)
      @pid_regex ||= T.let({
        launchctl_list:  /"PID"\ =\ ([0-9]*);/,
        launchctl_print: /pid = ([0-9]+)/,
        systemctl:       /Main PID: ([0-9]*) \((?!code=)/,
      }, T.nilable(T::Hash[T.untyped, Regexp]))
      @pid_regex.fetch(status_type)
    end

    sig { returns(T::Boolean) }
    def boot_path_service_file_present?
      (T.must(System.boot_path) + T.must(service_file).basename).exist?
    end

    sig { returns(T::Boolean) }
    def user_path_service_file_present?
      (T.must(System.user_path) + T.must(service_file).basename).exist?
    end

    sig { returns(Regexp) }
    private_class_method def self.path_or_label_regex
      /homebrew(?>\.mxcl)?\.([\w+-.@]+)(\.plist|\.service)?\z/
    end
  end
end
