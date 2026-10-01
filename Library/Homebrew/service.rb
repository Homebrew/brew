# typed: strict
# frozen_string_literal: true

require "utils/output"
require "utils/shell"

require "ipaddr"
require "on_system"
require "utils/path"
require "utils/service"

module Homebrew
  # The {Service} class implements the DSL methods used in a formula's
  # `service` block and stores related instance variables. Most of these methods
  # also return the related instance variable when no argument is provided.
  class Service
    extend Forwardable
    include OnSystem::MacOSAndLinux
    include Utils::Output::Mixin
    include Utils::Path

    RUN_TYPE_IMMEDIATE = :immediate
    RUN_TYPE_INTERVAL = :interval
    RUN_TYPE_CRON = :cron

    PROCESS_TYPE_BACKGROUND = :background
    PROCESS_TYPE_STANDARD = :standard
    PROCESS_TYPE_INTERACTIVE = :interactive
    PROCESS_TYPE_ADAPTIVE = :adaptive

    KEEP_ALIVE_KEYS = [:always, :successful_exit, :crashed, :path].freeze
    NICE_RANGE = T.let(-20..19, T::Range[Integer])
    SOCKET_STRING_REGEX = %r{^(?<type>[a-z]+)://(?<host>.+):(?<port>[0-9]+)$}i

    RunParam = T.type_alias { T.nilable(T.any(T::Array[T.any(String, Pathname)], String, Pathname)) }
    Sockets = T.type_alias { T::Hash[Symbol, { host: String, port: String, type: String }] }

    sig { returns(String) }
    attr_reader :plist_name, :service_name

    sig { params(formula: Formula, block: T.nilable(T.proc.bind(Homebrew::Service).void)).void }
    def initialize(formula, &block)
      @cron = T.let({}, T::Hash[Symbol, T.any(Integer, String)])
      @environment_variables = T.let({}, T::Hash[Symbol, String])
      @error_log_path = T.let(nil, T.nilable(String))
      @formula = formula
      @input_path = T.let(nil, T.nilable(String))
      @interval = T.let(nil, T.nilable(Integer))
      @keep_alive = T.let({}, T::Hash[Symbol, T.untyped])
      @launch_only_once = T.let(false, T::Boolean)
      @log_path = T.let(nil, T.nilable(String))
      @macos_legacy_timers = T.let(false, T::Boolean)
      @nice = T.let(nil, T.nilable(Integer))
      @plist_name = T.let(default_plist_name, String)
      @plist_name_explicitly_set = T.let(false, T::Boolean)
      @process_type = T.let(nil, T.nilable(Symbol))
      @require_root = T.let(false, T::Boolean)
      @restart_delay = T.let(nil, T.nilable(Integer))
      @throttle_interval = T.let(nil, T.nilable(Integer))
      @root_dir = T.let(nil, T.nilable(String))
      @run = T.let([], T::Array[String])
      @run_at_load = T.let(true, T::Boolean)
      @run_params = T.let(nil, T.any(RunParam, T::Hash[Symbol, RunParam]))
      @run_type = T.let(RUN_TYPE_IMMEDIATE, Symbol)
      @service_name = T.let(default_service_name, String)
      @service_name_explicitly_set = T.let(false, T::Boolean)
      @sockets = T.let({}, Sockets)
      @stop_timeout = T.let(nil, T.nilable(Integer))
      @working_dir = T.let(nil, T.nilable(String))
      instance_eval(&block) if block

      raise TypeError, "Service#nice: require_root true is required for negative nice values" if nice_requires_root?
    end

    sig { returns(T::Boolean) }
    def nice_requires_root?
      @nice&.negative? == true && !requires_root?
    end

    sig { returns(Formula) }
    def f
      @formula
    end

    sig { returns(String) }
    def default_plist_name
      canonical_plist_name
    end

    sig { returns(String) }
    def legacy_plist_name
      "homebrew.mxcl.#{@formula.name}"
    end

    sig { returns(String) }
    def canonical_plist_name
      "sh.brew.#{@formula.name}"
    end

    sig { returns(T::Array[String]) }
    def plist_names
      return [plist_name] if @plist_name_explicitly_set

      [plist_name, canonical_plist_name, legacy_plist_name].uniq
    end

    sig { returns(String) }
    def default_service_name
      canonical_service_name
    end

    sig { returns(String) }
    def legacy_service_name
      "homebrew.#{@formula.name}"
    end

    sig { returns(String) }
    def canonical_service_name
      "sh.brew.#{@formula.name}"
    end

    sig { returns(T::Array[String]) }
    def service_names
      return [service_name] if @service_name_explicitly_set

      [service_name, canonical_service_name, legacy_service_name].uniq
    end

    # A hash with the `launchd` service name on macOS and/or the `systemd`
    # service name on Linux. Homebrew generates a default name for the service
    # file if this is not present.
    #
    # @api public
    sig { params(macos: T.nilable(String), linux: T.nilable(String)).void }
    def name(macos: nil, linux: nil)
      raise TypeError, "Service#name expects at least one String" if [macos, linux].none?(String)

      if macos
        @plist_name = macos
        @plist_name_explicitly_set = true
      end
      return unless linux

      @service_name = linux
      @service_name_explicitly_set = true
    end

    # The command to execute: an array with arguments or a path.
    #
    # @api public
    sig {
      params(
        command: T.nilable(RunParam),
        macos:   T.nilable(RunParam),
        linux:   T.nilable(RunParam),
      ).returns(T.nilable(T::Array[String]))
    }
    def run(command = nil, macos: nil, linux: nil)
      # Save parameters for serialization
      if command
        @run_params = command
      elsif macos || linux
        @run_params = { macos:, linux: }.compact
      end

      command ||= on_system_conditional(macos:, linux:)
      case command
      when nil
        @run
      when String, Pathname
        @run = [command.to_s]
      when Array
        @run = command.map(&:to_s)
      end
    end

    # Directory to operate from.
    #
    # @api public
    sig { params(path: T.nilable(T.any(String, Pathname))).returns(T.nilable(String)) }
    def working_dir(path = nil)
      if path
        @working_dir = path.to_s
      else
        @working_dir
      end
    end

    # Directory to use as a chroot for the process.
    #
    # @api public
    sig { params(path: T.nilable(T.any(String, Pathname))).returns(T.nilable(String)) }
    def root_dir(path = nil)
      if path
        @root_dir = path.to_s
      else
        @root_dir
      end
    end

    # Path to use as input for the process.
    #
    # @api public
    sig { params(path: T.nilable(T.any(String, Pathname))).returns(T.nilable(String)) }
    def input_path(path = nil)
      if path
        @input_path = path.to_s
      else
        @input_path
      end
    end

    # Path to write `stdout` to.
    #
    # @api public
    sig { params(path: T.nilable(T.any(String, Pathname))).returns(T.nilable(String)) }
    def log_path(path = nil)
      if path
        @log_path = path.to_s
      else
        @log_path
      end
    end

    # Path to write `stderr` to.
    #
    # @api public
    sig { params(path: T.nilable(T.any(String, Pathname))).returns(T.nilable(String)) }
    def error_log_path(path = nil)
      if path
        @error_log_path = path.to_s
      else
        @error_log_path
      end
    end

    # Sets contexts in which the service will keep the process running.
    #
    # @api public
    sig {
      params(value: T.nilable(T.any(T::Boolean, T::Hash[Symbol, T.untyped])))
        .returns(T.nilable(T::Hash[Symbol, T.untyped]))
    }
    def keep_alive(value = nil)
      case value
      when nil
        @keep_alive
      when true, false
        @keep_alive = { always: value }
      when Hash
        unless (value.keys - KEEP_ALIVE_KEYS).empty?
          raise TypeError, "Service#keep_alive only allows: #{KEEP_ALIVE_KEYS}"
        end

        @keep_alive = value
      end
    end

    # Whether the service requires root access. If true, Homebrew hints at using
    # `sudo` on various occasions, but does not enforce it.
    #
    # @api public
    sig { params(value: T.nilable(T::Boolean)).returns(T::Boolean) }
    def require_root(value = nil)
      if value.nil?
        @require_root
      else
        @require_root = value
      end
    end

    # Returns a `Boolean` describing if a service requires root access.
    sig { returns(T::Boolean) }
    def requires_root?
      @require_root.present? && @require_root == true
    end

    # Whether the command should run when the service is loaded.
    #
    # @api public
    sig { params(value: T.nilable(T::Boolean)).returns(T.nilable(T::Boolean)) }
    def run_at_load(value = nil)
      if value.nil?
        @run_at_load
      else
        @run_at_load = value
      end
    end

    # Socket that is created as an access point to the service.
    #
    # @api public
    sig {
      params(value: T.nilable(T.any(String, T::Hash[Symbol, String])))
        .returns(T::Hash[Symbol, T::Hash[Symbol, String]])
    }
    def sockets(value = nil)
      return @sockets if value.nil?

      value_hash = value.is_a?(String) ? { listeners: value } : value

      @sockets = value_hash.transform_values do |socket_string|
        match = socket_string.match(SOCKET_STRING_REGEX)
        host, port, type = match.values_at(:host, :port, :type) if match
        if host.nil? || port.nil? || type.nil?
          raise TypeError, "Service#sockets a formatted socket definition as <type>://<host>:<port>"
        end

        begin
          IPAddr.new(host)
        rescue IPAddr::InvalidAddressError
          raise TypeError, "Service#sockets expects a valid ipv4 or ipv6 host address"
        end

        { host:, port:, type: }
      end
    end

    # Returns a `Boolean` describing if a service is set to be kept alive.
    sig { returns(T::Boolean) }
    def keep_alive?
      !@keep_alive.empty? && @keep_alive[:always] != false
    end

    # Whether the command should only run once.
    #
    # @api public
    sig { params(value: T.nilable(T::Boolean)).returns(T::Boolean) }
    def launch_only_once(value = nil)
      if value.nil?
        @launch_only_once
      else
        @launch_only_once = value
      end
    end

    # Number of seconds to delay before restarting a process.
    #
    # @api public
    sig { params(value: T.nilable(Integer)).returns(T.nilable(Integer)) }
    def restart_delay(value = nil)
      if value
        @restart_delay = value
      else
        @restart_delay
      end
    end

    # Minimum seconds to wait before invocations (macOS default is `10`).
    #
    # @api public
    sig { params(value: T.nilable(Integer)).returns(T.nilable(Integer)) }
    def throttle_interval(value = nil)
      return @throttle_interval if value.nil?

      @throttle_interval = value
    end

    # Number of seconds to wait before forcibly stopping a process.
    #
    # @api public
    sig { params(value: T.nilable(Integer)).returns(T.nilable(Integer)) }
    def stop_timeout(value = nil)
      return @stop_timeout if value.nil?

      raise TypeError, "Service#stop_timeout must be a non-negative integer" if value.negative?

      @stop_timeout = value
    end

    # Type of process to manage: `:background`, `:standard`, `:interactive` or
    # `:adaptive`.
    #
    # @api public
    sig { params(value: T.nilable(Symbol)).returns(T.nilable(Symbol)) }
    def process_type(value = nil)
      case value
      when nil
        @process_type
      when :background, :standard, :interactive, :adaptive
        @process_type = value
      when Symbol
        raise TypeError, "Service#process_type allows: " \
                         "'#{PROCESS_TYPE_BACKGROUND}'/'#{PROCESS_TYPE_STANDARD}'/" \
                         "'#{PROCESS_TYPE_INTERACTIVE}'/'#{PROCESS_TYPE_ADAPTIVE}'"
      end
    end

    # The type of service: `:immediate`, `:interval` or `:cron`.
    #
    # @api public
    sig { params(value: T.nilable(Symbol)).returns(T.nilable(Symbol)) }
    def run_type(value = nil)
      case value
      when nil
        @run_type
      when :immediate, :interval, :cron
        @run_type = value
      when Symbol
        raise TypeError, "Service#run_type allows: '#{RUN_TYPE_IMMEDIATE}'/'#{RUN_TYPE_INTERVAL}'/'#{RUN_TYPE_CRON}'"
      end
    end

    # Controls the start interval, required for the `:interval` type.
    #
    # @api public
    sig { params(value: T.nilable(Integer)).returns(T.nilable(Integer)) }
    def interval(value = nil)
      if value
        @interval = value
      else
        @interval
      end
    end

    # Controls the trigger times, required for the `:cron` type.
    #
    # @api public
    sig { params(value: T.nilable(String)).returns(T::Hash[Symbol, T.any(Integer, String)]) }
    def cron(value = nil)
      if value
        @cron = parse_cron(value)
      else
        @cron
      end
    end

    sig { returns(T::Hash[Symbol, T.any(Integer, String)]) }
    def default_cron_values
      {
        Month:   "*",
        Day:     "*",
        Weekday: "*",
        Hour:    "*",
        Minute:  "*",
      }
    end

    sig { params(cron_statement: String).returns(T::Hash[Symbol, T.any(Integer, String)]) }
    def parse_cron(cron_statement)
      parsed = default_cron_values

      case cron_statement
      when "@hourly"
        parsed[:Minute] = 0
      when "@daily"
        parsed[:Minute] = 0
        parsed[:Hour] = 0
      when "@weekly"
        parsed[:Minute] = 0
        parsed[:Hour] = 0
        parsed[:Weekday] = 0
      when "@monthly"
        parsed[:Minute] = 0
        parsed[:Hour] = 0
        parsed[:Day] = 1
      when "@yearly", "@annually"
        parsed[:Minute] = 0
        parsed[:Hour] = 0
        parsed[:Day] = 1
        parsed[:Month] = 1
      else
        cron_parts = cron_statement.split
        raise TypeError, "Service#parse_cron expects a valid cron syntax" if cron_parts.length != 5

        [:Minute, :Hour, :Day, :Month, :Weekday].each_with_index do |selector, index|
          parsed[selector] = Integer(cron_parts.fetch(index)) if cron_parts.fetch(index) != "*"
        end
      end

      parsed
    end

    # Hash of variables to set.
    #
    # @api public
    sig { params(variables: T::Hash[Symbol, T.any(Pathname, String)]).returns(T.nilable(T::Hash[Symbol, String])) }
    def environment_variables(variables = {})
      @environment_variables = variables.transform_values(&:to_s)
    end

    # Returns the effective environment variables with user overrides merged
    # in from `$HOMEBREW_USER_CONFIG_HOME/services/<formula>.env`.  User
    # overrides take precedence over formula-defined variables.
    sig { returns(T::Hash[Symbol, String]) }
    def effective_environment_variables
      env_vars = @environment_variables.dup

      env_file = Pathname.new("#{ENV.fetch("HOMEBREW_USER_CONFIG_HOME")}/services/#{@formula.name}.env")
      return env_vars unless env_file.file?

      # User env overrides are not supported for root services.
      # `sudo -E` can preserve a caller-controlled HOME, and TOCTOU
      # between symlink resolution, permission checks, and reading makes
      # it impossible to safely validate a user-owned override file when
      # generating a root service definition.
      if Process.euid.zero?
        opoo "Skipping #{env_file}: user env overrides are not supported for root services."
        return env_vars
      end

      if env_file.world_writable?
        opoo "Skipping #{env_file}: file is world-writable."
        return env_vars
      end

      if env_file.stat.mode.anybits?(020)
        opoo "Skipping #{env_file}: file is group-writable."
        return env_vars
      end

      # Read each line, strip whitespace, and remove blank lines and
      # comments (lines starting with `#`). Then parse remaining lines
      # as KEY=value pairs, warning on lines missing a `=` separator.
      overrides = env_file.each_line
                          .map(&:strip)
                          .reject { |line| line.empty? || line.start_with?("#") }
                          .each_with_object({}) do |line, hash|
                            key, value = line.split("=", 2)
                            if key.blank? || value.nil?
                              opoo "Skipping invalid line in #{env_file}: #{line}"
                              next
                            end

                            hash[key.strip] = value.strip
                          end

      overrides.each { |key, value| env_vars[key.to_sym] = value }

      env_vars
    end

    # Timers created by `launchd` jobs are coalesced unless this is set.
    #
    # @api public
    sig { params(value: T.nilable(T::Boolean)).returns(T::Boolean) }
    def macos_legacy_timers(value = nil)
      if value.nil?
        @macos_legacy_timers
      else
        @macos_legacy_timers = value
      end
    end

    # Default scheduling priority (nice level), from `-20` highest to `19`
    # lowest. **Note:** Negative nice values (higher priority) require
    # `require_root: true` to be set.
    #
    # @api public
    sig { params(value: T.nilable(Integer)).returns(T.nilable(Integer)) }
    def nice(value = nil)
      return @nice if value.nil?

      raise TypeError, "Service#nice value should be in #{NICE_RANGE}" unless NICE_RANGE.cover?(value)

      @nice = value
    end

    delegate [:bin, :etc, :libexec, :opt_bin, :opt_libexec, :opt_pkgshare, :opt_prefix, :opt_sbin, :var] => :@formula

    # @api internal
    sig { returns(String) }
    def std_service_path_env
      "#{HOMEBREW_PREFIX}/bin:#{HOMEBREW_PREFIX}/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
    end

    sig { returns(T::Array[String]) }
    def command
      @run.map(&:to_s).map { |arg| arg.start_with?("~") ? File.expand_path(arg) : arg }
    end

    sig { returns(T::Boolean) }
    def command?
      !@run.empty?
    end

    sig { returns(T::Array[Pathname]) }
    def path_dirs
      [
        path_dir(@working_dir),
        path_dir(@root_dir),
      ].push(
        path_parent_dir(@input_path),
        path_parent_dir(@log_path),
        path_parent_dir(@error_log_path),
      )
       .compact
       .uniq
    end

    # Returns the `String` command to run manually instead of the service.
    sig { returns(String) }
    def manual_command
      env_vars = effective_environment_variables.except(:PATH)
                                                .map { |k, v| "#{k}=\"#{v}\"" }

      env_vars.concat(command.map { |arg| Utils::Shell.sh_quote(arg) })
      env_vars.join(" ")
    end

    # Returns a `Boolean` describing if a service is timed.
    sig { returns(T::Boolean) }
    def timed?
      @run_type == RUN_TYPE_CRON || @run_type == RUN_TYPE_INTERVAL
    end

    # Returns a `String` plist.
    sig { returns(String) }
    def to_plist
      # command needs to be first because it initializes all other values
      base = {
        Label:            plist_name,
        ProgramArguments: command,
        RunAtLoad:        @run_at_load == true,
      }

      base[:LaunchOnlyOnce] = @launch_only_once if @launch_only_once == true
      base[:LegacyTimers] = @macos_legacy_timers if @macos_legacy_timers == true
      base[:ExitTimeOut] = @stop_timeout if @stop_timeout.present?
      base[:TimeOut] = @restart_delay if @restart_delay.present?
      base[:ThrottleInterval] = @throttle_interval if @throttle_interval.present?
      base[:ProcessType] = @process_type.to_s.capitalize if @process_type.present?
      base[:Nice] = @nice if @nice.present?
      base[:StartInterval] = @interval if @interval.present? && @run_type == RUN_TYPE_INTERVAL
      base[:WorkingDirectory] = File.expand_path(@working_dir) if @working_dir.present?
      base[:RootDirectory] = File.expand_path(@root_dir) if @root_dir.present?
      base[:StandardInPath] = File.expand_path(@input_path) if @input_path.present?
      base[:StandardOutPath] = File.expand_path(@log_path) if @log_path.present?
      base[:StandardErrorPath] = File.expand_path(@error_log_path) if @error_log_path.present?
      if (env_vars = effective_environment_variables).present?
        base[:EnvironmentVariables] = env_vars
      end

      if keep_alive?
        if (always = @keep_alive[:always].presence)
          base[:KeepAlive] = always
        elsif @keep_alive.key?(:successful_exit)
          base[:KeepAlive] = { SuccessfulExit: @keep_alive[:successful_exit] }
        elsif @keep_alive.key?(:crashed)
          base[:KeepAlive] = { Crashed: @keep_alive[:crashed] }
        elsif @keep_alive.key?(:path) && @keep_alive[:path].present?
          base[:KeepAlive] = { PathState: @keep_alive[:path].to_s }
        end
      end

      unless @sockets.empty?
        base[:Sockets] = {}
        @sockets.each do |name, info|
          base[:Sockets][name] = {
            SockNodeName:    info[:host],
            SockServiceName: info[:port],
            SockProtocol:    info[:type].upcase,
          }
        end
      end

      if !@cron.empty? && @run_type == RUN_TYPE_CRON
        base[:StartCalendarInterval] = @cron.reject { |_, value| value == "*" }
      end

      # Adding all session types has as the primary effect that if you initialise it through e.g. a Background session
      # and you later "physically" sign in to the owning account (Aqua session), things shouldn't flip out.
      # Also, we're not checking @process_type here because that is used to indicate process priority and not
      # necessarily if it should run in a specific session type. Like database services could run with ProcessType
      # Interactive so they have no resource limitations enforced upon them, but they aren't really interactive in the
      # general sense.
      base[:LimitLoadToSessionType] = %w[Aqua Background LoginWindow StandardIO System]

      require "plist"
      base.to_plist
    end

    # Returns a `String` systemd unit.
    sig { returns(String) }
    def to_systemd_unit
      # command needs to be first because it initializes all other values
      cmd = command.map { |arg| Utils::Service.systemd_quote(arg) }
                   .join(" ")

      options = []
      options << "Type=#{(@launch_only_once == true) ? "oneshot" : "simple"}"
      options << "ExecStart=#{cmd}"

      if @keep_alive.present?
        if @keep_alive[:always].present? || @keep_alive[:crashed].present?
          # Use on-failure instead of always to allow manual stops via systemctl
          options << "Restart=on-failure"
        elsif @keep_alive[:successful_exit].present?
          options << "Restart=on-success"
        end
      end
      options << "RestartSec=#{restart_delay}" if @restart_delay.present?
      options << "TimeoutStopSec=#{@stop_timeout}" if @stop_timeout.present?
      options << "Nice=#{@nice}" if @nice.present?
      options << "WorkingDirectory=#{File.expand_path(@working_dir)}" if @working_dir.present?
      options << "RootDirectory=#{File.expand_path(@root_dir)}" if @root_dir.present?
      options << "StandardInput=file:#{File.expand_path(@input_path)}" if @input_path.present?
      options << "StandardOutput=append:#{File.expand_path(@log_path)}" if @log_path.present?
      options << "StandardError=append:#{File.expand_path(@error_log_path)}" if @error_log_path.present?
      if (env_vars = effective_environment_variables).present?
        options += env_vars.map do |k, v|
          "Environment=\"#{k}=#{v}\""
        end
      end

      <<~SYSTEMD
        [Unit]
        Description=Homebrew generated unit for #{@formula.name}

        [Install]
        WantedBy=default.target

        [Service]
        #{options.join("\n")}
      SYSTEMD
    end

    sig { params(cron_weekday: T.nilable(T.any(Integer, String))).returns(String) }
    def cron_weekday_to_systemd_weekday(cron_weekday)
      if cron_weekday != "*" &&
         (weekday_number = cron_weekday&.to_i) &&
         (0..7).cover?(weekday_number)
        "#{Date::ABBR_DAYNAMES[weekday_number % 7]} "
      else
        ""
      end
    end

    # Returns a `String` systemd unit timer.
    sig { returns(String) }
    def to_systemd_timer
      options = []
      options << "Persistent=true" if @run_type == RUN_TYPE_CRON
      options << "OnUnitActiveSec=#{@interval}" if @run_type == RUN_TYPE_INTERVAL

      if @run_type == RUN_TYPE_CRON
        minutes = (@cron[:Minute] == "*") ? "*" : format("%02d", @cron[:Minute])
        hours   = (@cron[:Hour] == "*") ? "*" : format("%02d", @cron[:Hour])
        options << "OnCalendar=#{cron_weekday_to_systemd_weekday(@cron[:Weekday])}" \
                   "*-#{@cron[:Month]}-#{@cron[:Day]} #{hours}:#{minutes}:00"
      end

      <<~SYSTEMD
        [Unit]
        Description=Homebrew generated timer for #{@formula.name}

        [Install]
        WantedBy=timers.target

        [Timer]
        Unit=#{service_name}.service
        #{options.join("\n")}
      SYSTEMD
    end

    # Prepare the service hash for inclusion in the formula API JSON.
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_hash
      name_params = {
        macos: (plist_name if @plist_name_explicitly_set),
        linux: (service_name if @service_name_explicitly_set),
      }.compact

      return { name: name_params }.compact_blank if @run_params.blank?

      cron_string = if @cron.present?
        [:Minute, :Hour, :Day, :Month, :Weekday]
          .filter_map { |key| @cron[key].to_s.presence }
          .join(" ")
      end

      sockets_var = unless @sockets.empty?
        @sockets.transform_values { |info| "#{info[:type]}://#{info[:host]}:#{info[:port]}" }
                .then do |sockets_hash|
                  # TODO: Remove this code when all users are running on versions of Homebrew
                  #       that can process sockets hashes (this commit or later).
                  if sockets_hash.size == 1 && sockets_hash.key?(:listeners)
                    # When original #sockets argument was a string: `sockets "tcp://127.0.0.1:80"`
                    sockets_hash.fetch(:listeners)
                  else
                    # When original #sockets argument was a hash: `sockets http: "tcp://0.0.0.0:80"`
                    sockets_hash
                  end
                end
      end

      {
        name:                  name_params.presence,
        run:                   @run_params,
        run_type:              @run_type,
        interval:              @interval,
        cron:                  cron_string.presence,
        keep_alive:            @keep_alive,
        launch_only_once:      @launch_only_once,
        require_root:          @require_root,
        environment_variables: @environment_variables.presence,
        working_dir:           @working_dir,
        root_dir:              @root_dir,
        input_path:            @input_path,
        log_path:              @log_path,
        error_log_path:        @error_log_path,
        restart_delay:         @restart_delay,
        throttle_interval:     @throttle_interval,
        stop_timeout:          @stop_timeout,
        nice:                  @nice,
        process_type:          @process_type,
        macos_legacy_timers:   @macos_legacy_timers,
        sockets:               sockets_var,
      }.compact_blank
    end

    # Turn the service API hash values back into what is expected by the formula DSL.
    sig { params(api_hash: T::Hash[String, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def self.from_hash(api_hash)
      hash = {}
      hash[:name] = api_hash["name"].transform_keys(&:to_sym) if api_hash.key?("name")

      # The service hash might not have a "run" command if it only documents
      # an existing service file with the "name" command.
      return hash unless api_hash.key?("run")

      hash[:run] =
        case api_hash["run"]
        when String, Pathname
          replace_placeholders(api_hash["run"])
        when Array
          api_hash["run"].map { replace_placeholders(it) }
        when Hash
          api_hash["run"].to_h do |key, elem|
            run_cmd = if elem.is_a?(Array)
              elem.map { replace_placeholders(it) }
            else
              replace_placeholders(elem)
            end

            [key.to_sym, run_cmd]
          end
        else
          raise ArgumentError, "Unexpected run command: #{api_hash["run"]}"
        end

      if api_hash.key?("environment_variables")
        hash[:environment_variables] = api_hash["environment_variables"].to_h do |key, value|
          [key.to_sym, replace_placeholders(value)]
        end
      end

      %w[run_type process_type].each do |key|
        next unless (value = api_hash[key])

        hash[key.to_sym] = value.to_sym
      end

      %w[working_dir root_dir input_path log_path error_log_path].each do |key|
        next unless (value = api_hash[key])

        hash[key.to_sym] = replace_placeholders(value)
      end

      %w[interval cron launch_only_once require_root restart_delay throttle_interval stop_timeout nice
         macos_legacy_timers].each do |key|
        next if (value = api_hash[key]).nil?

        hash[key.to_sym] = value
      end

      %w[sockets keep_alive].each do |key|
        next unless (value = api_hash[key])

        hash[key.to_sym] = if value.is_a?(Hash)
          value.transform_keys(&:to_sym)
        else
          value
        end
      end

      hash
    end

    # Replace API path placeholders with local paths.
    sig { params(string: T.any(String, Pathname)).returns(String) }
    def self.replace_placeholders(string)
      string.to_s
            .gsub(HOMEBREW_PREFIX_PLACEHOLDER, HOMEBREW_PREFIX)
            .gsub(HOMEBREW_CELLAR_PLACEHOLDER, HOMEBREW_CELLAR)
            .gsub(HOMEBREW_HOME_PLACEHOLDER, Dir.home)
    end

    sig { params(path: T.nilable(String)).returns(T.nilable(Pathname)) }
    def path_dir(path)
      return if path.blank?
      return unless path.start_with?("/", "~")

      Pathname.new(File.expand_path(path))
    end

    sig { params(path: T.nilable(String)).returns(T.nilable(Pathname)) }
    def path_parent_dir(path)
      path_dir(path)&.dirname
    end
  end
end
