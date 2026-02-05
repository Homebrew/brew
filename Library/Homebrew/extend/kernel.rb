# typed: strict
# frozen_string_literal: true

require "utils/output"

module Kernel
  sig { params(env: T.nilable(String)).returns(T::Boolean) }
  def superenv?(env)
    return false if env == "std"

    !Superenv.bin.nil?
  end
  private :superenv?

  sig { params(formula: T.nilable(Formula)).void }
  def interactive_shell(formula = nil)
    unless formula.nil?
      ENV["HOMEBREW_DEBUG_PREFIX"] = formula.prefix.to_s
      ENV["HOMEBREW_DEBUG_INSTALL"] = formula.full_name
    end

    if Utils::Shell.preferred == :zsh && (home = Dir.home).start_with?(HOMEBREW_TEMP.resolved_path.to_s)
      FileUtils.mkdir_p home
      FileUtils.touch "#{home}/.zshrc"
    end

    term = ENV.fetch("HOMEBREW_TERM", ENV.fetch("TERM", nil))
    with_env(TERM: term) do
      Process.wait fork { exec Utils::Shell.preferred_path(default: "/bin/bash") }
    end

    return if $CHILD_STATUS.success?
    raise "Aborted due to non-zero exit status (#{$CHILD_STATUS.exitstatus})" if $CHILD_STATUS.exited?

    raise $CHILD_STATUS.inspect
  end

  sig { type_parameters(:U).params(block: T.proc.returns(T.type_parameter(:U))).returns(T.type_parameter(:U)) }
  def with_homebrew_path(&block)
    with_env(PATH: PATH.new(ORIGINAL_PATHS).to_s, &block)
  end

  # Kernel.system but with exceptions.
  sig {
    params(
      cmd:     T.nilable(T.any(Pathname, String, [String, String], T::Hash[String, T.nilable(String)])),
      argv0:   T.nilable(T.any(Pathname, String, [String, String])),
      args:    T.nilable(T.any(Pathname, String)),
      options: T.untyped,
    ).void
  }
  def safe_system(cmd, argv0 = nil, *args, **options)
    # TODO: migrate to utils.rb Homebrew.safe_system
    require "utils"

    return if Homebrew.system(cmd, argv0, *args, **options)

    raise ErrorDuringExecution.new([cmd, argv0, *args], status: $CHILD_STATUS)
  end

  # Run a system command without any output.
  #
  # @api internal
  sig {
    params(
      cmd:   T.nilable(T.any(Pathname, String, [String, String], T::Hash[String, T.nilable(String)])),
      argv0: T.nilable(T.any(String, [String, String])),
      args:  T.any(Pathname, String),
    ).returns(T::Boolean)
  }
  def quiet_system(cmd, argv0 = nil, *args)
    # TODO: migrate to utils.rb Homebrew.quiet_system
    require "utils"

    Homebrew._system(cmd, argv0, *args) do
      # Redirect output streams to `/dev/null` instead of closing as some programs
      # will fail to execute if they can't write to an open stream.
      $stdout.reopen(File::NULL)
      $stderr.reopen(File::NULL)
    end
  end

  # Find a command.
  #
  # @api public
  sig { params(cmd: String, path: PATH::Elements).returns(T.nilable(Pathname)) }
  def which(cmd, path = ENV.fetch("PATH"))
    PATH.new(path).each do |p|
      begin
        pcmd = File.expand_path(cmd, p)
      rescue ArgumentError
        # File.expand_path will raise an ArgumentError if the path is malformed.
        # See https://github.com/Homebrew/legacy-homebrew/issues/32789
        next
      end
      return Pathname.new(pcmd) if File.file?(pcmd) && File.executable?(pcmd)
    end
    nil
  end

  sig { params(silent: T::Boolean).returns(String) }
  def which_editor(silent: false)
    editor = Homebrew::EnvConfig.editor
    return editor if editor

    # Find VS Code variants, Sublime Text, Textmate, BBEdit, or vim
    editor = %w[code codium cursor code-insiders subl mate bbedit vim].find do |candidate|
      candidate if which(candidate, ORIGINAL_PATHS)
    end
    editor ||= "vim"

    unless silent
      Utils::Output.opoo <<~EOS
        Using #{editor} because no editor was set in the environment.
        This may change in the future, so we recommend setting `$EDITOR`
        or `$HOMEBREW_EDITOR` to your preferred text editor.
      EOS
    end

    editor
  end

  sig { params(filenames: T.any(String, Pathname)).void }
  def exec_editor(*filenames)
    puts "Editing #{filenames.join "\n"}"
    with_homebrew_path { safe_system(*which_editor.shellsplit, *filenames) }
  end

  sig { params(args: T.any(String, Pathname)).void }
  def exec_browser(*args)
    browser = Homebrew::EnvConfig.browser
    browser ||= OS::PATH_OPEN if defined?(OS::PATH_OPEN)
    return unless browser

    ENV["DISPLAY"] = Homebrew::EnvConfig.display

    with_env(DBUS_SESSION_BUS_ADDRESS: ENV.fetch("HOMEBREW_DBUS_SESSION_BUS_ADDRESS", nil)) do
      safe_system(browser, *args)
    end
  end

  IGNORE_INTERRUPTS_MUTEX = T.let(Thread::Mutex.new.freeze, Thread::Mutex)

  sig { type_parameters(:U).params(_block: T.proc.returns(T.type_parameter(:U))).returns(T.type_parameter(:U)) }
  def ignore_interrupts(&_block)
    IGNORE_INTERRUPTS_MUTEX.synchronize do
      interrupted = T.let(false, T::Boolean)
      old_sigint_handler = trap(:INT) do
        interrupted = true

        $stderr.print "\n"
        $stderr.puts "One sec, cleaning up..."
      end

      begin
        yield
      ensure
        trap(:INT, old_sigint_handler)

        raise Interrupt if interrupted
      end
    end
  end

  sig {
    type_parameters(:U)
      .params(file: T.any(IO, Pathname, String), _block: T.proc.returns(T.type_parameter(:U)))
      .returns(T.type_parameter(:U))
  }
  def redirect_stdout(file, &_block)
    out = $stdout.dup
    $stdout.reopen(file)
    yield
  ensure
    $stdout.reopen(out)
    out.close
  end

  # Ensure the given executable exists otherwise install the brewed version
  sig { params(name: String, formula_name: T.nilable(String), reason: String, latest: T::Boolean).returns(Pathname) }
  def ensure_executable!(name, formula_name = nil, reason: "", latest: false)
    formula_name ||= name

    executable = [
      which(name),
      which(name, ORIGINAL_PATHS),
      # We prefer the opt_bin path to a formula's executable over the prefix
      # path where available, since the former is stable during upgrades.
      HOMEBREW_PREFIX/"opt/#{formula_name}/bin/#{name}",
      HOMEBREW_PREFIX/"bin/#{name}",
    ].compact.find(&:exist?)
    return executable if executable

    require "formula"
    Formula[formula_name].ensure_installed!(reason:, latest:).opt_bin/name
  end

  # Calls the given block with the passed environment variables
  # added to `ENV`, then restores `ENV` afterwards.
  #
  # NOTE: This method is **not** thread-safe – other threads
  #       which happen to be scheduled during the block will also
  #       see these environment variables.
  #
  # ### Example
  #
  # ```ruby
  # with_env(PATH: "/bin") do
  #   system "echo $PATH"
  # end
  # ```
  #
  # @api public
  sig {
    type_parameters(:U)
      .params(
        hash:   T::Hash[Object, T.nilable(T.any(PATH, Pathname, String))],
        _block: T.proc.returns(T.type_parameter(:U)),
      ).returns(T.type_parameter(:U))
  }
  def with_env(hash, &_block)
    old_values = {}
    begin
      hash.each do |key, value|
        key = key.to_s
        old_values[key] = ENV.delete(key)
        ENV[key] = value&.to_s
      end

      yield
    ensure
      ENV.update(old_values)
    end
  end
end
