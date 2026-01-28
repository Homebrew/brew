# typed: strict
# frozen_string_literal: true

require "ipaddr"
require "on_system"
require "utils/service"

module Homebrew
  # The {Service} class implements the DSL methods used in a formula's
  # `service` block and stores related instance variables. Most of these methods
  # also return the related instance variable when no argument is provided.
  class Service
    extend Forwardable
    include OnSystem::MacOSAndLinux

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

    sig { params(formula: Formula, block: T.nilable(T.proc.void)).void }
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
      @sockets = T.let({}, Sockets)
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
      "homebrew.mxcl.#{@formula.name}"
    end

    sig { returns(String) }
    def default_service_name
      "homebrew.#{@formula.name}"
    end

    sig { params(macos: T.nilable(String), linux: T.nilable(String)).void }
    def name(macos: nil, linux: nil)
      raise TypeError, "Service#name expects at least one String" if [macos, linux].none?(String)

      @plist_name = macos if macos
      @service_name = linux if linux
    end

    sig {
      params(
        command: T.nilable(RunParam),
        macos:   T.nilable(RunParam),
        linux:   T.nilable(RunParam),
      ).returns(T.nilable(T::Array[T.any(String, Pathname)]))
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

    sig { params(path: T.any(String, Pathname)).returns(T.nilable(String)) }
    def working_dir(path = T.unsafe(nil))
      if path
        @working_dir = path.to_s
      else
        @working_dir
      end
    end

    sig { params(path: T.any(String, Pathname)).returns(T.nilable(String)) }
    def root_dir(path = T.unsafe(nil))
      if path
        @root_dir = path.to_s
      else
        @root_dir
      end
    end

    sig { params(path: T.any(String, Pathname)).returns(T.nilable(String)) }
    def input_path(path = T.unsafe(nil))
      if path
        @input_path = path.to_s
      else
        @input_path
      end
    end

    sig { params(path: T.any(String, Pathname)).returns(T.nilable(String)) }
    def log_path(path = T.unsafe(nil))
      if path
        @log_path = path.to_s
      else
        @log_path
      end
    end

    sig { params(path: T.any(String, Pathname)).returns(T.nilable(String)) }
    def error_log_path(path = T.unsafe(nil))
      if path
        @error_log_path = path.to_s
      else
        @error_log_path
      end
    end

    sig {
      params(value: T.any(T::Boolean, T::Hash[Symbol, T.untyped]))
        .returns(T.nilable(T::Hash[Symbol, T.untyped]))
    }
    def keep_alive(value = T.unsafe(nil))
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

    sig { params(value: T::Boolean).returns(T::Boolean) }
    def require_root(value = T.unsafe(nil))
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

    sig { params(value: T::Boolean).returns(T.nilable(T::Boolean)) }
    def run_at_load(value = T.unsafe(nil))
      if value.nil?
        @run_at_load
      else
        @run_at_load = value
      end
    end

    sig {
      params(value: T.any(String, T::Hash[Symbol, String]))
        .returns(T::Hash[Symbol, T::Hash[Symbol, String]])
    }
    def sockets(value = T.unsafe(nil))
      return @sockets if value.nil?

      value_hash = case value
      when String
        { listeners: value }
      when Hash
        value
      end

      @sockets = T.must(value_hash).transform_values do |socket_string|
        match = socket_string.match(SOCKET_STRING_REGEX)
        raise TypeError, "Service#sockets a formatted socket definition as <type>://<host>:<port>" unless match

        begin
          IPAddr.new(match[:host])
        rescue IPAddr::InvalidAddressError
          raise TypeError, "Service#sockets expects a valid ipv4 or ipv6 host address"
        end

        { host: match[:host], port: match[:port], type: match[:type] }
      end
    end

    # Returns a `Boolean` describing if a service is set to be kept alive.
    sig { returns(T::Boolean) }
    def keep_alive?
      !@keep_alive.empty? && @keep_alive[:always] != false
    end

    sig { params(value: T::Boolean).returns(T::Boolean) }
    def launch_only_once(value = T.unsafe(nil))
      if value.nil?
        @launch_only_once
      else
        @launch_only_once = value
      end
    end

    sig { params(value: Integer).returns(T.nilable(Integer)) }
    def restart_delay(value = T.unsafe(nil))
      if value
        @restart_delay = value
      else
        @restart_delay
      end
    end

    sig { params(value: Integer).returns(T.nilable(Integer)) }
    def throttle_interval(value = T.unsafe(nil))
      return @throttle_interval if value.nil?

      @throttle_interval = value
    end

    sig { params(value: Symbol).returns(T.nilable(Symbol)) }
    def process_type(value = T.unsafe(nil))
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

    sig { params(value: Symbol).returns(T.nilable(Symbol)) }
    def run_type(value = T.unsafe(nil))
      case value
      when nil
        @run_type
      when :immediate, :interval, :cron
        @run_type = value
      when Symbol
        raise TypeError, "Service#run_type allows: '#{RUN_TYPE_IMMEDIATE}'/'#{RUN_TYPE_INTERVAL}'/'#{RUN_TYPE_CRON}'"
      end
    end

    sig { params(value: Integer).returns(T.nilable(Integer)) }
    def interval(value = T.unsafe(nil))
      if value
        @interval = value
      else
        @interval
      end
    end

    sig { params(value: String).returns(T::Hash[Symbol, T.any(Integer, String)]) }
    def cron(value = T.unsafe(nil))
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

    sig { params(variables: T::Hash[Symbol, T.any(Pathname, String)]).returns(T.nilable(T::Hash[Symbol, String])) }
    def environment_variables(variables = {})
      @environment_variables = variables.transform_values(&:to_s)
    end

    sig { params(value: T::Boolean).returns(T::Boolean) }
    def macos_legacy_timers(value = T.unsafe(nil))
      if value.nil?
        @macos_legacy_timers
      else
        @macos_legacy_timers = value
      end
    end

    sig { params(value: Integer).returns(T.nilable(Integer)) }
    def nice(value = T.unsafe(nil))
      return @nice if value.nil?

      raise TypeError, "Service#nice value should be in #{NICE_RANGE}" unless NICE_RANGE.cover?(value)

      @nice = value
    end

    delegate [:bin, :etc, :libexec, :opt_bin, :opt_libexec, :opt_pkgshare, :opt_prefix, :opt_sbin, :var] => :@formula

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

    # Returns the `String` command to run manually instead of the service.
    sig { returns(String) }
    def manual_command
      vars = @environment_variables.except(:PATH)
                                   .map { |k, v| "#{k}=\"#{v}\"" }

      vars.concat(command.map { |arg| Utils::Shell.sh_quote(arg) })
      vars.join(" ")
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
      base[:EnvironmentVariables] = @environment_variables unless @environment_variables.empty?

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
      options << "Nice=#{@nice}" if @nice.present?
      options << "WorkingDirectory=#{File.expand_path(@working_dir)}" if @working_dir.present?
      options << "RootDirectory=#{File.expand_path(@root_dir)}" if @root_dir.present?
      options << "StandardInput=file:#{File.expand_path(@input_path)}" if @input_path.present?
      options << "StandardOutput=append:#{File.expand_path(@log_path)}" if @log_path.present?
      options << "StandardError=append:#{File.expand_path(@error_log_path)}" if @error_log_path.present?
      options += @environment_variables.map { |k, v| "Environment=\"#{k}=#{v}\"" } if @environment_variables.present?

      <<~SYSTEMD
        [Unit]
        Description=Homebrew generated unit for #{@formula.name}

        [Install]
        WantedBy=default.target

        [Service]
        #{options.join("\n")}
      SYSTEMD
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
        options << "OnCalendar=#{@cron[:Weekday]}-*-#{@cron[:Month]}-#{@cron[:Day]} #{hours}:#{minutes}:00"
      end

      <<~SYSTEMD
        [Unit]
        Description=Homebrew generated timer for #{@formula.name}

        [Install]
        WantedBy=timers.target

        [Timer]
        Unit=#{service_name}
        #{options.join("\n")}
      SYSTEMD
    end

    # Prepare the service hash for inclusion in the formula API JSON.
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_hash
      name_params = {
        macos: (plist_name if plist_name != default_plist_name),
        linux: (service_name if service_name != default_service_name),
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
        when String
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

      %w[interval cron launch_only_once require_root restart_delay throttle_interval nice
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
    sig { params(string: String).returns(String) }
    def self.replace_placeholders(string)
      string.gsub(HOMEBREW_PREFIX_PLACEHOLDER, HOMEBREW_PREFIX)
            .gsub(HOMEBREW_CELLAR_PLACEHOLDER, HOMEBREW_CELLAR)
            .gsub(HOMEBREW_HOME_PLACEHOLDER, Dir.home)
    end
  end
end
