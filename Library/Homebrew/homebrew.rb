# typed: strict
# frozen_string_literal: true

require "context"

module Homebrew
  extend Context

  sig { params(path: T.nilable(T.any(String, Pathname))).returns(T::Boolean) }
  def self.require?(path)
    return false if path.nil?

    if defined?(Warnings)
      # Work around require warning when done repeatedly:
      # https://bugs.ruby-lang.org/issues/21091
      Warnings.ignore(/already initialized constant/, /previous definition of/) do
        require path.to_s
      end
    else
      require path.to_s
    end
    true
  rescue LoadError
    false
  end

  # Need to keep this naming as-is for backwards compatibility.
  # rubocop:disable Naming/PredicateMethod
  sig {
    params(
      cmd:     T.nilable(T.any(Pathname, String, [String, String], T::Hash[String, T.nilable(String)])),
      argv0:   T.nilable(T.any(Pathname, String, [String, String])),
      args:    T.any(Pathname, String),
      options: T.untyped,
      _block:  T.nilable(T.proc.void),
    ).returns(T::Boolean)
  }
  def self._system(cmd, argv0 = nil, *args, **options, &_block)
    pid = fork do
      yield if block_given?
      args.map!(&:to_s)
      begin
        if argv0
          exec(cmd, argv0, *args, **options)
        else
          exec(cmd, *args, **options)
        end
      rescue
        nil
      end
      exit! 1 # never gets here unless exec failed
    end
    Process.wait(pid)
    $CHILD_STATUS.success? || false
  end
  private_class_method :_system
  # rubocop:enable Naming/PredicateMethod

  sig {
    params(
      cmd:     T.any(Pathname, String, [String, String], T::Hash[String, T.nilable(String)]),
      argv0:   T.nilable(T.any(Pathname, String, [String, String])),
      args:    T.any(Pathname, String),
      options: T.untyped,
    ).returns(T::Boolean)
  }
  def self.system(cmd, argv0 = nil, *args, **options)
    if verbose?
      out = (options[:out] == :err) ? $stderr : $stdout
      out.puts "#{cmd} #{args * " "}".gsub(RUBY_PATH.to_s, "ruby")
                                     .gsub($LOAD_PATH.join(File::PATH_SEPARATOR).to_s, "$LOAD_PATH")
    end
    _system(cmd, argv0, *args, **options)
  end

  sig {
    params(
      cmd:     T.nilable(T.any(Pathname, String, [String, String], T::Hash[String, T.nilable(String)])),
      argv0:   T.nilable(T.any(Pathname, String, [String, String])),
      args:    T.nilable(T.any(Pathname, String)),
      options: T.untyped,
    ).void
  }
  def self.safe_system(cmd, argv0 = nil, *args, **options)
    return if system(cmd, argv0, *args, **options)

    raise ErrorDuringExecution.new([cmd, argv0, *args], status: $CHILD_STATUS)
  end

  sig {
    params(
      cmd:   T.nilable(T.any(Pathname, String, [String, String], T::Hash[String, T.nilable(String)])),
      argv0: T.nilable(T.any(String, [String, String])),
      args:  T.any(Pathname, String),
    ).returns(T::Boolean)
  }
  def self.quiet_system(cmd, argv0 = nil, *args)
    _system(cmd, argv0, *args) do
      # Redirect output streams to `/dev/null` instead of closing as some programs
      # will fail to execute if they can't write to an open stream.
      $stdout.reopen(File::NULL)
      $stderr.reopen(File::NULL)
    end
  end

  # Uses $times global to share timing data between wrapped methods and the at_exit reporter.
  # rubocop:disable Style/GlobalVars
  sig { params(the_module: T::Module[T.anything], pattern: Regexp).void }
  def self.inject_dump_stats!(the_module, pattern)
    @injected_dump_stat_modules ||= T.let({}, T.nilable(T::Hash[T::Module[T.anything], T::Array[Symbol]]))
    @injected_dump_stat_modules[the_module] ||= []
    injected_methods = @injected_dump_stat_modules.fetch(the_module)
    wrapper = Module.new
    the_module.instance_methods.grep(pattern).each do |name|
      next if injected_methods.include? name

      injected_methods << name
      wrapper.define_method(name) do |*args, &block|
        require "time"

        time = Time.now

        begin
          super(*args, &block)
        ensure
          $times[name] ||= 0
          $times[name] += Time.now - time
        end
      end
    end
    the_module.prepend(wrapper)

    return unless $times.nil?

    $times = {}
    at_exit do
      col_width = [$times.keys.map(&:size).max.to_i + 2, 15].max
      $times.sort_by { |_k, v| v }.each do |method, time|
        puts format("%<method>-#{col_width}s %<time>0.4f sec", method: "#{method}:", time:)
      end
    end
  end
  # rubocop:enable Style/GlobalVars
end
