# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

# Contains shorthand Homebrew utility methods like `ohai`, `opoo`, `odisabled`.
# TODO: move these out of `Kernel`.

module Kernel
  def require?(path)
    return false if path.nil?

    require path
    true
  rescue LoadError => e
    # we should raise on syntax errors but not if the file doesn't exist.
    raise unless e.message.include?(path)
  end

  def ohai_title(title)
    verbose = if respond_to?(:verbose?)
      T.unsafe(self).verbose?
    else
      Context.current.verbose?
    end

    title = Tty.truncate(title.to_s) if $stdout.tty? && !verbose
    Formatter.headline(title, color: :blue)
  end

  def ohai(title, *sput)
    puts ohai_title(title)
    puts sput
  end

  def odebug(title, *sput, always_display: false)
    debug = if respond_to?(:debug)
      T.unsafe(self).debug?
    else
      Context.current.debug?
    end

    return if !debug && !always_display

    $stderr.puts Formatter.headline(title, color: :magenta)
    $stderr.puts sput unless sput.empty?
  end

  def oh1_title(title, truncate: :auto)
    verbose = if respond_to?(:verbose?)
      T.unsafe(self).verbose?
    else
      Context.current.verbose?
    end

    title = Tty.truncate(title.to_s) if $stdout.tty? && !verbose && truncate == :auto
    Formatter.headline(title, color: :green)
  end

  def oh1(title, truncate: :auto)
    puts oh1_title(title, truncate:)
  end

  # Print a warning message.
  #
  # @api public
  sig { params(message: T.any(String, Exception)).void }
  def opoo(message)
    require "utils/github/actions"
    return if GitHub::Actions.puts_annotation_if_env_set(:warning, message.to_s)

    require "utils/formatter"

    Tty.with($stderr) do |stderr|
      stderr.puts Formatter.warning(message, label: "Warning")
    end
  end

  # Print an error message.
  #
  # @api public
  sig { params(message: T.any(String, Exception)).void }
  def onoe(message)
    require "utils/github/actions"
    return if GitHub::Actions.puts_annotation_if_env_set(:error, message.to_s)

    require "utils/formatter"

    Tty.with($stderr) do |stderr|
      stderr.puts Formatter.error(message, label: "Error")
    end
  end

  # Print an error message and fail at the end of the program.
  #
  # @api public
  sig { params(error: T.any(String, Exception)).void }
  def ofail(error)
    onoe error
    Homebrew.failed = true
  end

  # Print an error message and fail immediately.
  #
  # @api public
  sig { params(error: T.any(String, Exception)).returns(T.noreturn) }
  def odie(error)
    onoe error
    exit 1
  end

  # Output a deprecation warning/error message.
  def odeprecated(method, replacement = nil,
                  disable:                false,
                  disable_on:             nil,
                  disable_for_developers: true,
                  caller:                 send(:caller))
    replacement_message = if replacement
      "Use #{replacement} instead."
    else
      "There is no replacement."
    end

    unless disable_on.nil?
      if disable_on > Time.now
        will_be_disabled_message = " and will be disabled on #{disable_on.strftime("%Y-%m-%d")}"
      else
        disable = true
      end
    end

    verb = if disable
      "disabled"
    else
      "deprecated#{will_be_disabled_message}"
    end

    # Try to show the most relevant location in message, i.e. (if applicable):
    # - Location in a formula.
    # - Location of caller of deprecated method (if all else fails).
    backtrace = caller

    # Don't throw deprecations at all for cached, .brew or .metadata files.
    return if backtrace.any? do |line|
      next true if line.include?(HOMEBREW_CACHE.to_s)
      next true if line.include?("/.brew/")
      next true if line.include?("/.metadata/")

      next false unless line.match?(HOMEBREW_TAP_PATH_REGEX)

      path = Pathname(line.split(":", 2).first)
      next false unless path.file?
      next false unless path.readable?

      formula_contents = path.read
      formula_contents.include?(" deprecate! ") || formula_contents.include?(" disable! ")
    end

    tap_message = T.let(nil, T.nilable(String))

    backtrace.each do |line|
      next unless (match = line.match(HOMEBREW_TAP_PATH_REGEX))

      require "tap"

      tap = Tap.fetch(match[:user], match[:repository])
      tap_message = "\nPlease report this issue to the #{tap.full_name} tap"
      tap_message += " (not Homebrew/brew or Homebrew/homebrew-core)" unless tap.official?
      tap_message += ", or even better, submit a PR to fix it" if replacement
      tap_message << ":\n  #{line.sub(/^(.*:\d+):.*$/, '\1')}\n\n"
      break
    end
    file, line, = backtrace.first.split(":")
    line = line.to_i if line.present?

    message = "Calling #{method} is #{verb}! #{replacement_message}"
    message << tap_message if tap_message
    message.freeze

    disable = true if disable_for_developers && Homebrew::EnvConfig.developer?
    if disable || Homebrew.raise_deprecation_exceptions?
      require "utils/github/actions"
      GitHub::Actions.puts_annotation_if_env_set(:error, message, file:, line:)
      exception = MethodDeprecatedError.new(message)
      exception.set_backtrace(backtrace)
      raise exception
    elsif !Homebrew.auditing?
      opoo message
    end
  end

  def odisabled(method, replacement = nil, **options)
    options = { disable: true, caller: }.merge(options)
    # This odeprecated should stick around indefinitely.
    odeprecated(method, replacement, **options)
  end

  def pretty_installed(formula)
    if !$stdout.tty?
      formula.to_s
    elsif Homebrew::EnvConfig.no_emoji?
      Formatter.success("#{Tty.bold}#{formula} (installed)#{Tty.reset}")
    else
      "#{Tty.bold}#{formula} #{Formatter.success("✔")}#{Tty.reset}"
    end
  end

  def pretty_outdated(formula)
    if !$stdout.tty?
      formula.to_s
    elsif Homebrew::EnvConfig.no_emoji?
      Formatter.error("#{Tty.bold}#{formula} (outdated)#{Tty.reset}")
    else
      "#{Tty.bold}#{formula} #{Formatter.warning("⚠")}#{Tty.reset}"
    end
  end

  def pretty_uninstalled(formula)
    if !$stdout.tty?
      formula.to_s
    elsif Homebrew::EnvConfig.no_emoji?
      Formatter.error("#{Tty.bold}#{formula} (uninstalled)#{Tty.reset}")
    else
      "#{Tty.bold}#{formula} #{Formatter.error("✘")}#{Tty.reset}"
    end
  end

  def pretty_duration(seconds)
    seconds = seconds.to_i
    res = +""

    if seconds > 59
      minutes = seconds / 60
      seconds %= 60
      res = +Utils.pluralize("minute", minutes, include_count: true)
      return res.freeze if seconds.zero?

      res << " "
    end

    res << Utils.pluralize("second", seconds, include_count: true)
    res.freeze
  end

  def interactive_shell(formula = nil)
    unless formula.nil?
      ENV["HOMEBREW_DEBUG_PREFIX"] = formula.prefix
      ENV["HOMEBREW_DEBUG_INSTALL"] = formula.full_name
    end

    if Utils::Shell.preferred == :zsh && (home = Dir.home).start_with?(HOMEBREW_TEMP.resolved_path.to_s)
      FileUtils.mkdir_p home
      FileUtils.touch "#{home}/.zshrc"
    end

    Process.wait fork { exec Utils::Shell.preferred_path(default: "/bin/bash") }

    return if $CHILD_STATUS.success?
    raise "Aborted due to non-zero exit status (#{$CHILD_STATUS.exitstatus})" if $CHILD_STATUS.exited?

    raise $CHILD_STATUS.inspect
  end

  def with_homebrew_path(&block)
    with_env(PATH: PATH.new(ORIGINAL_PATHS), &block)
  end

  def with_custom_locale(locale, &block)
    with_env(LC_ALL: locale, &block)
  end

  # Kernel.system but with exceptions.
  def safe_system(cmd, *args, **options)
    require "utils"

    return if Homebrew.system(cmd, *args, **options)

    raise ErrorDuringExecution.new([cmd, *args], status: $CHILD_STATUS)
  end

  # Run a system command without any output.
  #
  # @api internal
  def quiet_system(cmd, *args)
    require "utils"

    Homebrew._system(cmd, *args) do
      # Redirect output streams to `/dev/null` instead of closing as some programs
      # will fail to execute if they can't write to an open stream.
      $stdout.reopen(File::NULL)
      $stderr.reopen(File::NULL)
    end
  end

  # Find a command.
  #
  # @api public
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

  def which_all(cmd, path = ENV.fetch("PATH"))
    PATH.new(path).filter_map do |p|
      begin
        pcmd = File.expand_path(cmd, p)
      rescue ArgumentError
        # File.expand_path will raise an ArgumentError if the path is malformed.
        # See https://github.com/Homebrew/legacy-homebrew/issues/32789
        next
      end
      Pathname.new(pcmd) if File.file?(pcmd) && File.executable?(pcmd)
    end.uniq
  end

  def which_editor(silent: false)
    editor = Homebrew::EnvConfig.editor
    return editor if editor

    # Find VS Code, Sublime Text, Textmate, BBEdit, or vim
    editor = %w[code subl mate bbedit vim].find do |candidate|
      candidate if which(candidate, ORIGINAL_PATHS)
    end
    editor ||= "vim"

    unless silent
      opoo <<~EOS
        Using #{editor} because no editor was set in the environment.
        This may change in the future, so we recommend setting EDITOR
        or HOMEBREW_EDITOR to your preferred text editor.
      EOS
    end

    editor
  end

  def exec_editor(*args)
    puts "Editing #{args.join "\n"}"
    with_homebrew_path { safe_system(*which_editor.shellsplit, *args) }
  end

  def exec_browser(*args)
    browser = Homebrew::EnvConfig.browser
    browser ||= OS::PATH_OPEN if defined?(OS::PATH_OPEN)
    return unless browser

    ENV["DISPLAY"] = Homebrew::EnvConfig.display

    with_env(DBUS_SESSION_BUS_ADDRESS: ENV.fetch("HOMEBREW_DBUS_SESSION_BUS_ADDRESS", nil)) do
      safe_system(browser, *args)
    end
  end

  IGNORE_INTERRUPTS_MUTEX = Thread::Mutex.new.freeze

  def ignore_interrupts
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

  def redirect_stdout(file)
    out = $stdout.dup
    $stdout.reopen(file)
    yield
  ensure
    $stdout.reopen(out)
    out.close
  end

  # Ensure the given formula is installed
  # This is useful for installing a utility formula (e.g. `shellcheck` for `brew style`)
  def ensure_formula_installed!(formula_or_name, reason: "", latest: false,
                                output_to_stderr: true, quiet: false)
    if output_to_stderr || quiet
      file = if quiet
        File::NULL
      else
        $stderr
      end
      # Call this method itself with redirected stdout
      redirect_stdout(file) do
        return ensure_formula_installed!(formula_or_name, latest:,
                                         reason:, output_to_stderr: false)
      end
    end

    require "formula"

    formula = if formula_or_name.is_a?(Formula)
      formula_or_name
    else
      Formula[formula_or_name]
    end

    reason = " for #{reason}" if reason.present?

    unless formula.any_version_installed?
      ohai "Installing `#{formula.name}`#{reason}..."
      safe_system HOMEBREW_BREW_FILE, "install", "--formula", formula.full_name
    end

    if latest && !formula.latest_version_installed?
      ohai "Upgrading `#{formula.name}`#{reason}..."
      safe_system HOMEBREW_BREW_FILE, "upgrade", "--formula", formula.full_name
    end

    formula
  end

  # Ensure the given executable is exist otherwise install the brewed version
  def ensure_executable!(name, formula_name = nil, reason: "", latest: false)
    formula_name ||= name

    executable = [
      which(name),
      which(name, ORIGINAL_PATHS),
      # We prefer the opt_bin path to a formula's executable over the prefix
      # path where available, since the former is stable during upgrades.
      HOMEBREW_PREFIX/"opt/#{formula_name}/bin/#{name}",
      HOMEBREW_PREFIX/"bin/#{name}",
    ].compact.first
    return executable if executable.exist?

    ensure_formula_installed!(formula_name, reason:, latest:).opt_bin/name
  end

  def paths
    @paths ||= ORIGINAL_PATHS.uniq.map(&:to_s)
  end

  def disk_usage_readable(size_in_bytes)
    if size_in_bytes >= 1_073_741_824
      size = size_in_bytes.to_f / 1_073_741_824
      unit = "GB"
    elsif size_in_bytes >= 1_048_576
      size = size_in_bytes.to_f / 1_048_576
      unit = "MB"
    elsif size_in_bytes >= 1_024
      size = size_in_bytes.to_f / 1_024
      unit = "KB"
    else
      size = size_in_bytes
      unit = "B"
    end

    # avoid trailing zero after decimal point
    if ((size * 10).to_i % 10).zero?
      "#{size.to_i}#{unit}"
    else
      "#{format("%<size>.1f", size:)}#{unit}"
    end
  end

  def number_readable(number)
    numstr = number.to_i.to_s
    (numstr.size - 3).step(1, -3) { |i| numstr.insert(i, ",") }
    numstr
  end

  # Truncates a text string to fit within a byte size constraint,
  # preserving character encoding validity. The returned string will
  # be not much longer than the specified max_bytes, though the exact
  # shortfall or overrun may vary.
  def truncate_text_to_approximate_size(str, max_bytes, options = {})
    front_weight = options.fetch(:front_weight, 0.5)
    raise "opts[:front_weight] must be between 0.0 and 1.0" if front_weight < 0.0 || front_weight > 1.0
    return str if str.bytesize <= max_bytes

    glue = "\n[...snip...]\n"
    max_bytes_in = [max_bytes - glue.bytesize, 1].max
    bytes = str.dup.force_encoding("BINARY")
    glue_bytes = glue.encode("BINARY")
    n_front_bytes = (max_bytes_in * front_weight).floor
    n_back_bytes = max_bytes_in - n_front_bytes
    if n_front_bytes.zero?
      front = bytes[1..0]
      back = bytes[-max_bytes_in..]
    elsif n_back_bytes.zero?
      front = bytes[0..(max_bytes_in - 1)]
      back = bytes[1..0]
    else
      front = bytes[0..(n_front_bytes - 1)]
      back = bytes[-n_back_bytes..]
    end
    out = front + glue_bytes + back
    out.force_encoding("UTF-8")
    out.encode!("UTF-16", invalid: :replace)
    out.encode!("UTF-8")
    out
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
  def with_env(hash)
    old_values = {}
    begin
      hash.each do |key, value|
        key = key.to_s
        old_values[key] = ENV.delete(key)
        ENV[key] = value
      end

      yield if block_given?
    ensure
      ENV.update(old_values)
    end
  end

  def tap_and_name_comparison
    proc do |a, b|
      if a.include?("/") && b.exclude?("/")
        1
      elsif a.exclude?("/") && b.include?("/")
        -1
      else
        a <=> b
      end
    end
  end

  def redact_secrets(input, secrets)
    secrets.compact
           .reduce(input) { |str, secret| str.gsub secret, "******" }
           .freeze
  end
end
