# frozen_string_literal: true

#
# = open3.rb: Popen, but with stderr, too
#
# Author:: Yukihiro Matsumoto
# Documentation:: Konrad Meyer
#
# Open3 gives you access to stdin, stdout, and stderr when running other
# programs.
#

#
# Open3 grants you access to stdin, stdout, stderr and a thread to wait for the
# child process when running another program.
# You can specify various attributes, redirections, current directory, etc., of
# the program in the same way as for Process.spawn.
#
# - Open3.popen3 : pipes for stdin, stdout, stderr
# - Open3.popen2 : pipes for stdin, stdout
# - Open3.popen2e : pipes for stdin, merged stdout and stderr
# - Open3.capture3 : give a string for stdin; get strings for stdout, stderr
# - Open3.capture2 : give a string for stdin; get a string for stdout
# - Open3.capture2e : give a string for stdin; get a string for merged stdout and stderr
# - Open3.pipeline_rw : pipes for first stdin and last stdout of a pipeline
# - Open3.pipeline_r : pipe for last stdout of a pipeline
# - Open3.pipeline_w : pipe for first stdin of a pipeline
# - Open3.pipeline_start : run a pipeline without waiting
# - Open3.pipeline : run a pipeline and wait for its completion
#

require 'open3/version'

# \Module \Open3 supports creating child processes
# with access to their $stdin, $stdout, and $stderr streams.
#
# == What's Here
#
# Each of these methods executes a given command in a new process or subshell,
# or multiple commands in new processes and/or subshells:
#
# - Each of these methods executes a single command in a process or subshell,
#   accepts a string for input to $stdin,
#   and returns string output from $stdout, $stderr, or both:
#
#   - Open3.capture2: Executes the command;
#     returns the string from $stdout.
#   - Open3.capture2e: Executes the command;
#     returns the string from merged $stdout and $stderr.
#   - Open3.capture3: Executes the command;
#     returns strings from $stdout and $stderr.
#
# - Each of these methods executes a single command in a process or subshell,
#   and returns pipes for $stdin, $stdout, and/or $stderr:
#
#   - Open3.popen2: Executes the command;
#     returns pipes for $stdin and $stdout.
#   - Open3.popen2e: Executes the command;
#     returns pipes for $stdin and merged $stdout and $stderr.
#   - Open3.popen3: Executes the command;
#     returns pipes for $stdin, $stdout, and $stderr.
#
# - Each of these methods executes one or more commands in processes and/or subshells,
#   returns pipes for the first $stdin, the last $stdout, or both:
#
#   - Open3.pipeline_r: Returns a pipe for the last $stdout.
#   - Open3.pipeline_rw: Returns pipes for the first $stdin and the last $stdout.
#   - Open3.pipeline_w: Returns a pipe for the first $stdin.
#   - Open3.pipeline_start: Does not wait for processes to complete.
#   - Open3.pipeline: Waits for processes to complete.
#
# Each of the methods above accepts:
#
# - An optional hash of environment variable names and values;
#   see {Execution Environment}[rdoc-ref:Process@Execution+Environment].
# - A required string argument that is a +command_line+ or +exe_path+;
#   see {Argument command_line or exe_path}[rdoc-ref:Process@Argument+command_line+or+exe_path].
# - An optional hash of execution options;
#   see {Execution Options}[rdoc-ref:Process@Execution+Options].
#
module Open3

  # :call-seq:
  #   Open3.popen3([env, ] command_line, options = {}) -> [stdin, stdout, stderr, wait_thread]
  #   Open3.popen3([env, ] exe_path, *args, options = {}) -> [stdin, stdout, stderr, wait_thread]
  #   Open3.popen3([env, ] command_line, options = {}) {|stdin, stdout, stderr, wait_thread| ... } -> object
  #   Open3.popen3([env, ] exe_path, *args, options = {}) {|stdin, stdout, stderr, wait_thread| ... } -> object
  #
  # Basically a wrapper for
  # {Process.spawn}[rdoc-ref:Process.spawn]
  # that:
  #
  # - Creates a child process, by calling Process.spawn with the given arguments.
  # - Creates streams +stdin+, +stdout+, and +stderr+,
  #   which are the standard input, standard output, and standard error streams
  #   in the child process.
  # - Creates thread +wait_thread+ that waits for the child process to exit;
  #   the thread has method +pid+, which returns the process ID
  #   of the child process.
  #
  # With no block given, returns the array
  # <tt>[stdin, stdout, stderr, wait_thread]</tt>.
  # The caller should close each of the three returned streams.
  #
  #   stdin, stdout, stderr, wait_thread = Open3.popen3('echo')
  #   # => [#<IO:fd 8>, #<IO:fd 10>, #<IO:fd 12>, #<Process::Waiter:0x00007f58d5428f58 run>]
  #   stdin.close
  #   stdout.close
  #   stderr.close
  #   wait_thread.pid   # => 2210481
  #   wait_thread.value # => #<Process::Status: pid 2210481 exit 0>
  #
  # With a block given, calls the block with the four variables
  # (three streams and the wait thread)
  # and returns the block's return value.
  # The caller need not close the streams:
  #
  #   Open3.popen3('echo') do |stdin, stdout, stderr, wait_thread|
  #     p stdin
  #     p stdout
  #     p stderr
  #     p wait_thread
  #     p wait_thread.pid
  #     p wait_thread.value
  #   end
  #
  # Output:
  #
  #   #<IO:fd 6>
  #   #<IO:fd 7>
  #   #<IO:fd 9>
  #   #<Process::Waiter:0x00007f58d53606e8 sleep>
  #   2211047
  #   #<Process::Status: pid 2211047 exit 0>
  #
  # Like Process.spawn, this method has potential security vulnerabilities
  # if called with untrusted input;
  # see {Command Injection}[rdoc-ref:command_injection.rdoc@Command+Injection].
  #
  # Unlike Process.spawn, this method waits for the child process to exit
  # before returning, so the caller need not do so.
  #
  # If the first argument is a hash, it becomes leading argument +env+
  # in the call to Process.spawn;
  # see {Execution Environment}[rdoc-ref:Process@Execution+Environment].
  #
  # If the last argument is a hash, it becomes trailing argument +options+
  # in the call to Process.spawn;
  # see {Execution Options}[rdoc-ref:Process@Execution+Options].
  #
  # The single required argument is one of the following:
  #
  # - +command_line+ if it is a string,
  #   and if it begins with a shell reserved word or special built-in,
  #   or if it contains one or more metacharacters.
  # - +exe_path+ otherwise.
  #
  # <b>Argument +command_line+</b>
  #
  # \String argument +command_line+ is a command line to be passed to a shell;
  # it must begin with a shell reserved word, begin with a special built-in,
  # or contain meta characters:
  #
  #   Open3.popen3('if true; then echo "Foo"; fi') {|*args| p args } # Shell reserved word.
  #   Open3.popen3('echo') {|*args| p args }                         # Built-in.
  #   Open3.popen3('date > date.tmp') {|*args| p args }              # Contains meta character.
  #
  # Output (similar for each call above):
  #
  #   [#<IO:(closed)>, #<IO:(closed)>, #<IO:(closed)>, #<Process::Waiter:0x00007f58d52f28c8 dead>]
  #
  # The command line may also contain arguments and options for the command:
  #
  #   Open3.popen3('echo "Foo"') { |i, o, e, t| o.gets }
  #   "Foo\n"
  #
  # <b>Argument +exe_path+</b>
  #
  # Argument +exe_path+ is one of the following:
  #
  # - The string path to an executable to be called.
  # - A 2-element array containing the path to an executable
  #   and the string to be used as the name of the executing process.
  #
  # Example:
  #
  #   Open3.popen3('/usr/bin/date') { |i, o, e, t| o.gets }
  #   # => "Wed Sep 27 02:56:44 PM CDT 2023\n"
  #
  # Ruby invokes the executable directly, with no shell and no shell expansion:
  #
  #   Open3.popen3('doesnt_exist') { |i, o, e, t| o.gets } # Raises Errno::ENOENT
  #
  # If one or more +args+ is given, each is an argument or option
  # to be passed to the executable:
  #
  #   Open3.popen3('echo', 'C #') { |i, o, e, t| o.gets }
  #   # => "C #\n"
  #   Open3.popen3('echo', 'hello', 'world') { |i, o, e, t| o.gets }
  #   # => "hello world\n"
  #
  # Take care to avoid deadlocks.
  # Output streams +stdout+ and +stderr+ have fixed-size buffers,
  # so reading extensively from one but not the other can cause a deadlock
  # when the unread buffer fills.
  # To avoid that, +stdout+ and +stderr+ should be read simultaneously
  # (using threads or IO.select).
  #
  # Related:
  #
  # - Open3.popen2: Makes the standard input and standard output streams
  #   of the child process available as separate streams,
  #   with no access to the standard error stream.
  # - Open3.popen2e: Makes the standard input and the merge
  #   of the standard output and standard error streams
  #   of the child process available as separate streams.
  #
  def popen3(*cmd, &block)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    in_r, in_w = IO.pipe
    opts[:in] = in_r
    in_w.sync = true

    out_r, out_w = IO.pipe
    opts[:out] = out_w

    err_r, err_w = IO.pipe
    opts[:err] = err_w

    popen_run(cmd, opts, [in_r, out_w, err_w], [in_w, out_r, err_r], &block)
  end
  module_function :popen3

  # :call-seq:
  #   Open3.popen2([env, ] command_line, options = {}) -> [stdin, stdout, wait_thread]
  #   Open3.popen2([env, ] exe_path, *args, options = {}) -> [stdin, stdout, wait_thread]
  #   Open3.popen2([env, ] command_line, options = {}) {|stdin, stdout, wait_thread| ... } -> object
  #   Open3.popen2([env, ] exe_path, *args, options = {}) {|stdin, stdout, wait_thread| ... } -> object
  #
  # Basically a wrapper for
  # {Process.spawn}[rdoc-ref:Process.spawn]
  # that:
  #
  # - Creates a child process, by calling Process.spawn with the given arguments.
  # - Creates streams +stdin+ and +stdout+,
  #   which are the standard input and standard output streams
  #   in the child process.
  # - Creates thread +wait_thread+ that waits for the child process to exit;
  #   the thread has method +pid+, which returns the process ID
  #   of the child process.
  #
  # With no block given, returns the array
  # <tt>[stdin, stdout, wait_thread]</tt>.
  # The caller should close each of the two returned streams.
  #
  #   stdin, stdout, wait_thread = Open3.popen2('echo')
  #   # => [#<IO:fd 6>, #<IO:fd 7>, #<Process::Waiter:0x00007f58d52dbe98 run>]
  #   stdin.close
  #   stdout.close
  #   wait_thread.pid   # => 2263572
  #   wait_thread.value # => #<Process::Status: pid 2263572 exit 0>
  #
  # With a block given, calls the block with the three variables
  # (two streams and the wait thread)
  # and returns the block's return value.
  # The caller need not close the streams:
  #
  #   Open3.popen2('echo') do |stdin, stdout, wait_thread|
  #     p stdin
  #     p stdout
  #     p wait_thread
  #     p wait_thread.pid
  #     p wait_thread.value
  #   end
  #
  # Output:
  #
  #   #<IO:fd 6>
  #   #<IO:fd 7>
  #   #<Process::Waiter:0x00007f58d59a34b0 sleep>
  #   2263636
  #   #<Process::Status: pid 2263636 exit 0>
  #
  # Like Process.spawn, this method has potential security vulnerabilities
  # if called with untrusted input;
  # see {Command Injection}[rdoc-ref:command_injection.rdoc@Command+Injection].
  #
  # Unlike Process.spawn, this method waits for the child process to exit
  # before returning, so the caller need not do so.
  #
  # If the first argument is a hash, it becomes leading argument +env+
  # in the call to Process.spawn;
  # see {Execution Environment}[rdoc-ref:Process@Execution+Environment].
  #
  # If the last argument is a hash, it becomes trailing argument +options+
  # in the call to Process.spawn;
  # see {Execution Options}[rdoc-ref:Process@Execution+Options].
  #
  # The single required argument is one of the following:
  #
  # - +command_line+ if it is a string,
  #   and if it begins with a shell reserved word or special built-in,
  #   or if it contains one or more metacharacters.
  # - +exe_path+ otherwise.
  #
  # <b>Argument +command_line+</b>
  #
  # \String argument +command_line+ is a command line to be passed to a shell;
  # it must begin with a shell reserved word, begin with a special built-in,
  # or contain meta characters:
  #
  #   Open3.popen2('if true; then echo "Foo"; fi') {|*args| p args } # Shell reserved word.
  #   Open3.popen2('echo') {|*args| p args }                         # Built-in.
  #   Open3.popen2('date > date.tmp') {|*args| p args }              # Contains meta character.
  #
  # Output (similar for each call above):
  #
  #   # => [#<IO:(closed)>, #<IO:(closed)>, #<Process::Waiter:0x00007f7577dfe410 dead>]
  #
  # The command line may also contain arguments and options for the command:
  #
  #   Open3.popen2('echo "Foo"') { |i, o, t| o.gets }
  #   "Foo\n"
  #
  # <b>Argument +exe_path+</b>
  #
  # Argument +exe_path+ is one of the following:
  #
  # - The string path to an executable to be called.
  # - A 2-element array containing the path to an executable
  #   and the string to be used as the name of the executing process.
  #
  # Example:
  #
  #   Open3.popen2('/usr/bin/date') { |i, o, t| o.gets }
  #   # => "Thu Sep 28 09:41:06 AM CDT 2023\n"
  #
  # Ruby invokes the executable directly, with no shell and no shell expansion:
  #
  #   Open3.popen2('doesnt_exist') { |i, o, t| o.gets } # Raises Errno::ENOENT
  #
  # If one or more +args+ is given, each is an argument or option
  # to be passed to the executable:
  #
  #   Open3.popen2('echo', 'C #') { |i, o, t| o.gets }
  #   # => "C #\n"
  #   Open3.popen2('echo', 'hello', 'world') { |i, o, t| o.gets }
  #   # => "hello world\n"
  #
  #
  # Related:
  #
  # - Open3.popen2e: Makes the standard input and the merge
  #   of the standard output and standard error streams
  #   of the child process available as separate streams.
  # - Open3.popen3: Makes the standard input, standard output,
  #   and standard error streams
  #   of the child process available as separate streams.
  #
  def popen2(*cmd, &block)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    in_r, in_w = IO.pipe
    opts[:in] = in_r
    in_w.sync = true

    out_r, out_w = IO.pipe
    opts[:out] = out_w

    popen_run(cmd, opts, [in_r, out_w], [in_w, out_r], &block)
  end
  module_function :popen2

  # :call-seq:
  #   Open3.popen2e([env, ] command_line, options = {}) -> [stdin, stdout_and_stderr, wait_thread]
  #   Open3.popen2e([env, ] exe_path, *args, options = {}) -> [stdin, stdout_and_stderr, wait_thread]
  #   Open3.popen2e([env, ] command_line, options = {}) {|stdin, stdout_and_stderr, wait_thread| ... } -> object
  #   Open3.popen2e([env, ] exe_path, *args, options = {}) {|stdin, stdout_and_stderr, wait_thread| ... } -> object
  #
  # Basically a wrapper for
  # {Process.spawn}[rdoc-ref:Process.spawn]
  # that:
  #
  # - Creates a child process, by calling Process.spawn with the given arguments.
  # - Creates streams +stdin+, +stdout_and_stderr+,
  #   which are the standard input and the merge of the standard output
  #   and standard error streams in the child process.
  # - Creates thread +wait_thread+ that waits for the child process to exit;
  #   the thread has method +pid+, which returns the process ID
  #   of the child process.
  #
  # With no block given, returns the array
  # <tt>[stdin, stdout_and_stderr, wait_thread]</tt>.
  # The caller should close each of the two returned streams.
  #
  #   stdin, stdout_and_stderr, wait_thread = Open3.popen2e('echo')
  #   # => [#<IO:fd 6>, #<IO:fd 7>, #<Process::Waiter:0x00007f7577da4398 run>]
  #   stdin.close
  #   stdout_and_stderr.close
  #   wait_thread.pid   # => 2274600
  #   wait_thread.value # => #<Process::Status: pid 2274600 exit 0>
  #
  # With a block given, calls the block with the three variables
  # (two streams and the wait thread)
  # and returns the block's return value.
  # The caller need not close the streams:
  #
  #   Open3.popen2e('echo') do |stdin, stdout_and_stderr, wait_thread|
  #     p stdin
  #     p stdout_and_stderr
  #     p wait_thread
  #     p wait_thread.pid
  #     p wait_thread.value
  #   end
  #
  # Output:
  #
  #   #<IO:fd 6>
  #   #<IO:fd 7>
  #   #<Process::Waiter:0x00007f75777578c8 sleep>
  #   2274763
  #   #<Process::Status: pid 2274763 exit 0>
  #
  # Like Process.spawn, this method has potential security vulnerabilities
  # if called with untrusted input;
  # see {Command Injection}[rdoc-ref:command_injection.rdoc@Command+Injection].
  #
  # Unlike Process.spawn, this method waits for the child process to exit
  # before returning, so the caller need not do so.
  #
  # If the first argument is a hash, it becomes leading argument +env+
  # in the call to Process.spawn;
  # see {Execution Environment}[rdoc-ref:Process@Execution+Environment].
  #
  # If the last argument is a hash, it becomes trailing argument +options+
  # in the call to Process.spawn;
  # see {Execution Options}[rdoc-ref:Process@Execution+Options].
  #
  # The single required argument is one of the following:
  #
  # - +command_line+ if it is a string,
  #   and if it begins with a shell reserved word or special built-in,
  #   or if it contains one or more metacharacters.
  # - +exe_path+ otherwise.
  #
  # <b>Argument +command_line+</b>
  #
  # \String argument +command_line+ is a command line to be passed to a shell;
  # it must begin with a shell reserved word, begin with a special built-in,
  # or contain meta characters:
  #
  #   Open3.popen2e('if true; then echo "Foo"; fi') {|*args| p args } # Shell reserved word.
  #   Open3.popen2e('echo') {|*args| p args }                         # Built-in.
  #   Open3.popen2e('date > date.tmp') {|*args| p args }              # Contains meta character.
  #
  # Output (similar for each call above):
  #
  #   # => [#<IO:(closed)>, #<IO:(closed)>, #<Process::Waiter:0x00007f7577d8a1f0 dead>]
  #
  # The command line may also contain arguments and options for the command:
  #
  #   Open3.popen2e('echo "Foo"') { |i, o_and_e, t| o_and_e.gets }
  #   "Foo\n"
  #
  # <b>Argument +exe_path+</b>
  #
  # Argument +exe_path+ is one of the following:
  #
  # - The string path to an executable to be called.
  # - A 2-element array containing the path to an executable
  #   and the string to be used as the name of the executing process.
  #
  # Example:
  #
  #   Open3.popen2e('/usr/bin/date') { |i, o_and_e, t| o_and_e.gets }
  #   # => "Thu Sep 28 01:58:45 PM CDT 2023\n"
  #
  # Ruby invokes the executable directly, with no shell and no shell expansion:
  #
  #   Open3.popen2e('doesnt_exist') { |i, o_and_e, t| o_and_e.gets } # Raises Errno::ENOENT
  #
  # If one or more +args+ is given, each is an argument or option
  # to be passed to the executable:
  #
  #   Open3.popen2e('echo', 'C #') { |i, o_and_e, t| o_and_e.gets }
  #   # => "C #\n"
  #   Open3.popen2e('echo', 'hello', 'world') { |i, o_and_e, t| o_and_e.gets }
  #   # => "hello world\n"
  #
  # Related:
  #
  # - Open3.popen2: Makes the standard input and standard output streams
  #   of the child process available as separate streams,
  #   with no access to the standard error stream.
  # - Open3.popen3: Makes the standard input, standard output,
  #   and standard error streams
  #   of the child process available as separate streams.
  #
  def popen2e(*cmd, &block)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    in_r, in_w = IO.pipe
    opts[:in] = in_r
    in_w.sync = true

    out_r, out_w = IO.pipe
    opts[[:out, :err]] = out_w

    popen_run(cmd, opts, [in_r, out_w], [in_w, out_r], &block)
  ensure
    if block
      in_r.close
      in_w.close
      out_r.close
      out_w.close
    end
  end
  module_function :popen2e

  def popen_run(cmd, opts, child_io, parent_io) # :nodoc:
    pid = spawn(*cmd, opts)
    wait_thr = Process.detach(pid)
    child_io.each(&:close)
    result = [*parent_io, wait_thr]
    if defined? yield
      begin
        return yield(*result)
      ensure
        parent_io.each(&:close)
        wait_thr.join
      end
    end
    result
  end
  module_function :popen_run
  class << self
    private :popen_run
  end

  # :call-seq:
  #   Open3.capture3([env, ] command_line, options = {}) -> [stdout_s, stderr_s, status]
  #   Open3.capture3([env, ] exe_path, *args, options = {}) -> [stdout_s, stderr_s, status]
  #
  # Basically a wrapper for Open3.popen3 that:
  #
  # - Creates a child process, by calling Open3.popen3 with the given arguments
  #   (except for certain entries in hash +options+; see below).
  # - Returns as strings +stdout_s+ and +stderr_s+ the standard output
  #   and standard error of the child process.
  # - Returns as +status+ a <tt>Process::Status</tt> object
  #   that represents the exit status of the child process.
  #
  # Returns the array <tt>[stdout_s, stderr_s, status]</tt>:
  #
  #   stdout_s, stderr_s, status = Open3.capture3('echo "Foo"')
  #   # => ["Foo\n", "", #<Process::Status: pid 2281954 exit 0>]
  #
  # Like Process.spawn, this method has potential security vulnerabilities
  # if called with untrusted input;
  # see {Command Injection}[rdoc-ref:command_injection.rdoc@Command+Injection].
  #
  # Unlike Process.spawn, this method waits for the child process to exit
  # before returning, so the caller need not do so.
  #
  # If the first argument is a hash, it becomes leading argument +env+
  # in the call to Open3.popen3;
  # see {Execution Environment}[rdoc-ref:Process@Execution+Environment].
  #
  # If the last argument is a hash, it becomes trailing argument +options+
  # in the call to Open3.popen3;
  # see {Execution Options}[rdoc-ref:Process@Execution+Options].
  #
  # The hash +options+ is given;
  # two options have local effect in method Open3.capture3:
  #
  # - If entry <tt>options[:stdin_data]</tt> exists, the entry is removed
  #   and its string value is sent to the command's standard input:
  #
  #     Open3.capture3('tee', stdin_data: 'Foo')
  #     # => ["Foo", "", #<Process::Status: pid 2319575 exit 0>]
  #
  # - If entry <tt>options[:binmode]</tt> exists, the entry is removed and
  #   the internal streams are set to binary mode.
  #
  # The single required argument is one of the following:
  #
  # - +command_line+ if it is a string,
  #   and if it begins with a shell reserved word or special built-in,
  #   or if it contains one or more metacharacters.
  # - +exe_path+ otherwise.
  #
  # <b>Argument +command_line+</b>
  #
  # \String argument +command_line+ is a command line to be passed to a shell;
  # it must begin with a shell reserved word, begin with a special built-in,
  # or contain meta characters:
  #
  #   Open3.capture3('if true; then echo "Foo"; fi') # Shell reserved word.
  #   # => ["Foo\n", "", #<Process::Status: pid 2282025 exit 0>]
  #   Open3.capture3('echo')                         # Built-in.
  #   # => ["\n", "", #<Process::Status: pid 2282092 exit 0>]
  #   Open3.capture3('date > date.tmp')              # Contains meta character.
  #   # => ["", "", #<Process::Status: pid 2282110 exit 0>]
  #
  # The command line may also contain arguments and options for the command:
  #
  #   Open3.capture3('echo "Foo"')
  #   # => ["Foo\n", "", #<Process::Status: pid 2282092 exit 0>]
  #
  # <b>Argument +exe_path+</b>
  #
  # Argument +exe_path+ is one of the following:
  #
  # - The string path to an executable to be called.
  # - A 2-element array containing the path to an executable
  #   and the string to be used as the name of the executing process.
  #
  # Example:
  #
  #   Open3.capture3('/usr/bin/date')
  #   # => ["Thu Sep 28 05:03:51 PM CDT 2023\n", "", #<Process::Status: pid 2282300 exit 0>]
  #
  # Ruby invokes the executable directly, with no shell and no shell expansion:
  #
  #   Open3.capture3('doesnt_exist') # Raises Errno::ENOENT
  #
  # If one or more +args+ is given, each is an argument or option
  # to be passed to the executable:
  #
  #   Open3.capture3('echo', 'C #')
  #   # => ["C #\n", "", #<Process::Status: pid 2282368 exit 0>]
  #   Open3.capture3('echo', 'hello', 'world')
  #   # => ["hello world\n", "", #<Process::Status: pid 2282372 exit 0>]
  #
  def capture3(*cmd)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    stdin_data = opts.delete(:stdin_data) || ''
    binmode = opts.delete(:binmode)

    popen3(*cmd, opts) {|i, o, e, t|
      if binmode
        i.binmode
        o.binmode
        e.binmode
      end
      out_reader = Thread.new { o.read }
      err_reader = Thread.new { e.read }
      begin
        if stdin_data.respond_to? :readpartial
          IO.copy_stream(stdin_data, i)
        else
          i.write stdin_data
        end
      rescue Errno::EPIPE
      end
      i.close
      [out_reader.value, err_reader.value, t.value]
    }
  end
  module_function :capture3

  # :call-seq:
  #   Open3.capture2([env, ] command_line, options = {}) -> [stdout_s, status]
  #   Open3.capture2([env, ] exe_path, *args, options = {}) -> [stdout_s, status]
  #
  # Basically a wrapper for Open3.popen3 that:
  #
  # - Creates a child process, by calling Open3.popen3 with the given arguments
  #   (except for certain entries in hash +options+; see below).
  # - Returns as string +stdout_s+ the standard output of the child process.
  # - Returns as +status+ a <tt>Process::Status</tt> object
  #   that represents the exit status of the child process.
  #
  # Returns the array <tt>[stdout_s, status]</tt>:
  #
  #   stdout_s, status = Open3.capture2('echo "Foo"')
  #   # => ["Foo\n", #<Process::Status: pid 2326047 exit 0>]
  #
  # Like Process.spawn, this method has potential security vulnerabilities
  # if called with untrusted input;
  # see {Command Injection}[rdoc-ref:command_injection.rdoc@Command+Injection].
  #
  # Unlike Process.spawn, this method waits for the child process to exit
  # before returning, so the caller need not do so.
  #
  # If the first argument is a hash, it becomes leading argument +env+
  # in the call to Open3.popen3;
  # see {Execution Environment}[rdoc-ref:Process@Execution+Environment].
  #
  # If the last argument is a hash, it becomes trailing argument +options+
  # in the call to Open3.popen3;
  # see {Execution Options}[rdoc-ref:Process@Execution+Options].
  #
  # The hash +options+ is given;
  # two options have local effect in method Open3.capture2:
  #
  # - If entry <tt>options[:stdin_data]</tt> exists, the entry is removed
  #   and its string value is sent to the command's standard input:
  #
  #     Open3.capture2('tee', stdin_data: 'Foo')
  #
  #     # => ["Foo", #<Process::Status: pid 2326087 exit 0>]
  #
  # - If entry <tt>options[:binmode]</tt> exists, the entry is removed and
  #   the internal streams are set to binary mode.
  #
  # The single required argument is one of the following:
  #
  # - +command_line+ if it is a string,
  #   and if it begins with a shell reserved word or special built-in,
  #   or if it contains one or more metacharacters.
  # - +exe_path+ otherwise.
  #
  # <b>Argument +command_line+</b>
  #
  # \String argument +command_line+ is a command line to be passed to a shell;
  # it must begin with a shell reserved word, begin with a special built-in,
  # or contain meta characters:
  #
  #   Open3.capture2('if true; then echo "Foo"; fi') # Shell reserved word.
  #   # => ["Foo\n", #<Process::Status: pid 2326131 exit 0>]
  #   Open3.capture2('echo')                         # Built-in.
  #   # => ["\n", #<Process::Status: pid 2326139 exit 0>]
  #   Open3.capture2('date > date.tmp')              # Contains meta character.
  #   # => ["", #<Process::Status: pid 2326174 exit 0>]
  #
  # The command line may also contain arguments and options for the command:
  #
  #   Open3.capture2('echo "Foo"')
  #   # => ["Foo\n", #<Process::Status: pid 2326183 exit 0>]
  #
  # <b>Argument +exe_path+</b>
  #
  # Argument +exe_path+ is one of the following:
  #
  # - The string path to an executable to be called.
  # - A 2-element array containing the path to an executable
  #   and the string to be used as the name of the executing process.
  #
  # Example:
  #
  #   Open3.capture2('/usr/bin/date')
  #   # => ["Fri Sep 29 01:00:39 PM CDT 2023\n", #<Process::Status: pid 2326222 exit 0>]
  #
  # Ruby invokes the executable directly, with no shell and no shell expansion:
  #
  #   Open3.capture2('doesnt_exist') # Raises Errno::ENOENT
  #
  # If one or more +args+ is given, each is an argument or option
  # to be passed to the executable:
  #
  #   Open3.capture2('echo', 'C #')
  #   # => ["C #\n", #<Process::Status: pid 2326267 exit 0>]
  #   Open3.capture2('echo', 'hello', 'world')
  #   # => ["hello world\n", #<Process::Status: pid 2326299 exit 0>]
  #
  def capture2(*cmd)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    stdin_data = opts.delete(:stdin_data)
    binmode = opts.delete(:binmode)

    popen2(*cmd, opts) {|i, o, t|
      if binmode
        i.binmode
        o.binmode
      end
      out_reader = Thread.new { o.read }
      if stdin_data
        begin
          if stdin_data.respond_to? :readpartial
            IO.copy_stream(stdin_data, i)
          else
            i.write stdin_data
          end
        rescue Errno::EPIPE
        end
      end
      i.close
      [out_reader.value, t.value]
    }
  end
  module_function :capture2

  # :call-seq:
  #   Open3.capture2e([env, ] command_line, options = {}) -> [stdout_and_stderr_s, status]
  #   Open3.capture2e([env, ] exe_path, *args, options = {}) -> [stdout_and_stderr_s, status]
  #
  # Basically a wrapper for Open3.popen3 that:
  #
  # - Creates a child process, by calling Open3.popen3 with the given arguments
  #   (except for certain entries in hash +options+; see below).
  # - Returns as string +stdout_and_stderr_s+ the merged standard output
  #   and standard error of the child process.
  # - Returns as +status+ a <tt>Process::Status</tt> object
  #   that represents the exit status of the child process.
  #
  # Returns the array <tt>[stdout_and_stderr_s, status]</tt>:
  #
  #   stdout_and_stderr_s, status = Open3.capture2e('echo "Foo"')
  #   # => ["Foo\n", #<Process::Status: pid 2371692 exit 0>]
  #
  # Like Process.spawn, this method has potential security vulnerabilities
  # if called with untrusted input;
  # see {Command Injection}[rdoc-ref:command_injection.rdoc@Command+Injection].
  #
  # Unlike Process.spawn, this method waits for the child process to exit
  # before returning, so the caller need not do so.
  #
  # If the first argument is a hash, it becomes leading argument +env+
  # in the call to Open3.popen3;
  # see {Execution Environment}[rdoc-ref:Process@Execution+Environment].
  #
  # If the last argument is a hash, it becomes trailing argument +options+
  # in the call to Open3.popen3;
  # see {Execution Options}[rdoc-ref:Process@Execution+Options].
  #
  # The hash +options+ is given;
  # two options have local effect in method Open3.capture2e:
  #
  # - If entry <tt>options[:stdin_data]</tt> exists, the entry is removed
  #   and its string value is sent to the command's standard input:
  #
  #     Open3.capture2e('tee', stdin_data: 'Foo')
  #     # => ["Foo", #<Process::Status: pid 2371732 exit 0>]
  #
  # - If entry <tt>options[:binmode]</tt> exists, the entry is removed and
  #   the internal streams are set to binary mode.
  #
  # The single required argument is one of the following:
  #
  # - +command_line+ if it is a string,
  #   and if it begins with a shell reserved word or special built-in,
  #   or if it contains one or more metacharacters.
  # - +exe_path+ otherwise.
  #
  # <b>Argument +command_line+</b>
  #
  # \String argument +command_line+ is a command line to be passed to a shell;
  # it must begin with a shell reserved word, begin with a special built-in,
  # or contain meta characters:
  #
  #   Open3.capture2e('if true; then echo "Foo"; fi') # Shell reserved word.
  #   # => ["Foo\n", #<Process::Status: pid 2371740 exit 0>]
  #   Open3.capture2e('echo')                         # Built-in.
  #   # => ["\n", #<Process::Status: pid 2371774 exit 0>]
  #   Open3.capture2e('date > date.tmp')              # Contains meta character.
  #   # => ["", #<Process::Status: pid 2371812 exit 0>]
  #
  # The command line may also contain arguments and options for the command:
  #
  #   Open3.capture2e('echo "Foo"')
  #   # => ["Foo\n", #<Process::Status: pid 2326183 exit 0>]
  #
  # <b>Argument +exe_path+</b>
  #
  # Argument +exe_path+ is one of the following:
  #
  # - The string path to an executable to be called.
  # - A 2-element array containing the path to an executable
  #   and the string to be used as the name of the executing process.
  #
  # Example:
  #
  #   Open3.capture2e('/usr/bin/date')
  #   # => ["Sat Sep 30 09:01:46 AM CDT 2023\n", #<Process::Status: pid 2371820 exit 0>]
  #
  # Ruby invokes the executable directly, with no shell and no shell expansion:
  #
  #   Open3.capture2e('doesnt_exist') # Raises Errno::ENOENT
  #
  # If one or more +args+ is given, each is an argument or option
  # to be passed to the executable:
  #
  #   Open3.capture2e('echo', 'C #')
  #   # => ["C #\n", #<Process::Status: pid 2371856 exit 0>]
  #   Open3.capture2e('echo', 'hello', 'world')
  #   # => ["hello world\n", #<Process::Status: pid 2371894 exit 0>]
  #
  def capture2e(*cmd)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    stdin_data = opts.delete(:stdin_data)
    binmode = opts.delete(:binmode)

    popen2e(*cmd, opts) {|i, oe, t|
      if binmode
        i.binmode
        oe.binmode
      end
      outerr_reader = Thread.new { oe.read }
      if stdin_data
        begin
          if stdin_data.respond_to? :readpartial
            IO.copy_stream(stdin_data, i)
          else
            i.write stdin_data
          end
        rescue Errno::EPIPE
        end
      end
      i.close
      [outerr_reader.value, t.value]
    }
  end
  module_function :capture2e

  # :call-seq:
  #   Open3.pipeline_rw([env, ] *cmds, options = {}) -> [first_stdin, last_stdout, wait_threads]
  #
  # Basically a wrapper for
  # {Process.spawn}[rdoc-ref:Process.spawn]
  # that:
  #
  # - Creates a child process for each of the given +cmds+
  #   by calling Process.spawn.
  # - Pipes the +stdout+ from each child to the +stdin+ of the next child,
  #   or, for the first child, from the caller's +stdin+,
  #   or, for the last child, to the caller's +stdout+.
  #
  # The method does not wait for child processes to exit,
  # so the caller must do so.
  #
  # With no block given, returns a 3-element array containing:
  #
  # - The +stdin+ stream of the first child process.
  # - The +stdout+ stream of the last child process.
  # - An array of the wait threads for all of the child processes.
  #
  # Example:
  #
  #   first_stdin, last_stdout, wait_threads = Open3.pipeline_rw('sort', 'cat -n')
  #   # => [#<IO:fd 20>, #<IO:fd 21>, [#<Process::Waiter:0x000055e8de29ab40 sleep>, #<Process::Waiter:0x000055e8de29a690 sleep>]]
  #   first_stdin.puts("foo\nbar\nbaz")
  #   first_stdin.close # Send EOF to sort.
  #   puts last_stdout.read
  #   wait_threads.each do |wait_thread|
  #     wait_thread.join
  #   end
  #
  # Output:
  #
  #   1	bar
  #   2	baz
  #   3	foo
  #
  # With a block given, calls the block with the +stdin+ stream of the first child,
  # the +stdout+ stream  of the last child,
  # and an array of the wait processes:
  #
  #   Open3.pipeline_rw('sort', 'cat -n') do |first_stdin, last_stdout, wait_threads|
  #     first_stdin.puts "foo\nbar\nbaz"
  #     first_stdin.close # send EOF to sort.
  #     puts last_stdout.read
  #     wait_threads.each do |wait_thread|
  #       wait_thread.join
  #     end
  #   end
  #
  # Output:
  #
  #   1	bar
  #   2	baz
  #   3	foo
  #
  # Like Process.spawn, this method has potential security vulnerabilities
  # if called with untrusted input;
  # see {Command Injection}[rdoc-ref:command_injection.rdoc@Command+Injection].
  #
  # If the first argument is a hash, it becomes leading argument +env+
  # in each call to Process.spawn;
  # see {Execution Environment}[rdoc-ref:Process@Execution+Environment].
  #
  # If the last argument is a hash, it becomes trailing argument +options+
  # in each call to Process.spawn;
  # see {Execution Options}[rdoc-ref:Process@Execution+Options].
  #
  # Each remaining argument in +cmds+ is one of:
  #
  # - A +command_line+: a string that begins with a shell reserved word
  #   or special built-in, or contains one or more metacharacters.
  # - An +exe_path+: the string path to an executable to be called.
  # - An array containing a +command_line+ or an +exe_path+,
  #   along with zero or more string arguments for the command.
  #
  # See {Argument command_line or exe_path}[rdoc-ref:Process@Argument+command_line+or+exe_path].
  #
  def pipeline_rw(*cmds, &block)
    if Hash === cmds.last
      opts = cmds.pop.dup
    else
      opts = {}
    end

    in_r, in_w = IO.pipe
    opts[:in] = in_r
    in_w.sync = true

    out_r, out_w = IO.pipe
    opts[:out] = out_w

    pipeline_run(cmds, opts, [in_r, out_w], [in_w, out_r], &block)
  end
  module_function :pipeline_rw

  # :call-seq:
  #   Open3.pipeline_r([env, ] *cmds, options = {}) -> [last_stdout, wait_threads]
  #
  # Basically a wrapper for
  # {Process.spawn}[rdoc-ref:Process.spawn]
  # that:
  #
  # - Creates a child process for each of the given +cmds+
  #   by calling Process.spawn.
  # - Pipes the +stdout+ from each child to the +stdin+ of the next child,
  #   or, for the last child, to the caller's +stdout+.
  #
  # The method does not wait for child processes to exit,
  # so the caller must do so.
  #
  # With no block given, returns a 2-element array containing:
  #
  # - The +stdout+ stream of the last child process.
  # - An array of the wait threads for all of the child processes.
  #
  # Example:
  #
  #   last_stdout, wait_threads = Open3.pipeline_r('ls', 'grep R')
  #   # => [#<IO:fd 5>, [#<Process::Waiter:0x000055e8de2f9898 dead>, #<Process::Waiter:0x000055e8de2f94b0 sleep>]]
  #   puts last_stdout.read
  #   wait_threads.each do |wait_thread|
  #     wait_thread.join
  #   end
  #
  # Output:
  #
  #   Rakefile
  #   README.md
  #
  # With a block given, calls the block with the +stdout+ stream
  # of the last child process,
  # and an array of the wait processes:
  #
  #   Open3.pipeline_r('ls', 'grep R') do |last_stdout, wait_threads|
  #     puts last_stdout.read
  #     wait_threads.each do |wait_thread|
  #       wait_thread.join
  #     end
  #   end
  #
  # Output:
  #
  #   Rakefile
  #   README.md
  #
  # Like Process.spawn, this method has potential security vulnerabilities
  # if called with untrusted input;
  # see {Command Injection}[rdoc-ref:command_injection.rdoc@Command+Injection].
  #
  # If the first argument is a hash, it becomes leading argument +env+
  # in each call to Process.spawn;
  # see {Execution Environment}[rdoc-ref:Process@Execution+Environment].
  #
  # If the last argument is a hash, it becomes trailing argument +options+
  # in each call to Process.spawn;
  # see {Execution Options}[rdoc-ref:Process@Execution+Options].
  #
  # Each remaining argument in +cmds+ is one of:
  #
  # - A +command_line+: a string that begins with a shell reserved word
  #   or special built-in, or contains one or more metacharacters.
  # - An +exe_path+: the string path to an executable to be called.
  # - An array containing a +command_line+ or an +exe_path+,
  #   along with zero or more string arguments for the command.
  #
  # See {Argument command_line or exe_path}[rdoc-ref:Process@Argument+command_line+or+exe_path].
  #
  def pipeline_r(*cmds, &block)
    if Hash === cmds.last
      opts = cmds.pop.dup
    else
      opts = {}
    end

    out_r, out_w = IO.pipe
    opts[:out] = out_w

    pipeline_run(cmds, opts, [out_w], [out_r], &block)
  end
  module_function :pipeline_r


  # :call-seq:
  #   Open3.pipeline_w([env, ] *cmds, options = {}) -> [first_stdin, wait_threads]
  #
  # Basically a wrapper for
  # {Process.spawn}[rdoc-ref:Process.spawn]
  # that:
  #
  # - Creates a child process for each of the given +cmds+
  #   by calling Process.spawn.
  # - Pipes the +stdout+ from each child to the +stdin+ of the next child,
  #   or, for the first child, pipes the caller's +stdout+ to the child's +stdin+.
  #
  # The method does not wait for child processes to exit,
  # so the caller must do so.
  #
  # With no block given, returns a 2-element array containing:
  #
  # - The +stdin+ stream of the first child process.
  # - An array of the wait threads for all of the child processes.
  #
  # Example:
  #
  #   first_stdin, wait_threads = Open3.pipeline_w('sort', 'cat -n')
  #   # => [#<IO:fd 7>, [#<Process::Waiter:0x000055e8de928278 run>, #<Process::Waiter:0x000055e8de923e80 run>]]
  #   first_stdin.puts("foo\nbar\nbaz")
  #   first_stdin.close # Send EOF to sort.
  #   wait_threads.each do |wait_thread|
  #     wait_thread.join
  #   end
  #
  # Output:
  #
  #   1	bar
  #   2	baz
  #   3	foo
  #
  # With a block given, calls the block with the +stdin+ stream
  # of the first child process,
  # and an array of the wait processes:
  #
  #   Open3.pipeline_w('sort', 'cat -n') do |first_stdin, wait_threads|
  #     first_stdin.puts("foo\nbar\nbaz")
  #     first_stdin.close # Send EOF to sort.
  #     wait_threads.each do |wait_thread|
  #       wait_thread.join
  #     end
  #   end
  #
  # Output:
  #
  #   1	bar
  #   2	baz
  #   3	foo
  #
  # Like Process.spawn, this method has potential security vulnerabilities
  # if called with untrusted input;
  # see {Command Injection}[rdoc-ref:command_injection.rdoc@Command+Injection].
  #
  # If the first argument is a hash, it becomes leading argument +env+
  # in each call to Process.spawn;
  # see {Execution Environment}[rdoc-ref:Process@Execution+Environment].
  #
  # If the last argument is a hash, it becomes trailing argument +options+
  # in each call to Process.spawn;
  # see {Execution Options}[rdoc-ref:Process@Execution+Options].
  #
  # Each remaining argument in +cmds+ is one of:
  #
  # - A +command_line+: a string that begins with a shell reserved word
  #   or special built-in, or contains one or more metacharacters.
  # - An +exe_path+: the string path to an executable to be called.
  # - An array containing a +command_line+ or an +exe_path+,
  #   along with zero or more string arguments for the command.
  #
  # See {Argument command_line or exe_path}[rdoc-ref:Process@Argument+command_line+or+exe_path].
  #
  def pipeline_w(*cmds, &block)
    if Hash === cmds.last
      opts = cmds.pop.dup
    else
      opts = {}
    end

    in_r, in_w = IO.pipe
    opts[:in] = in_r
    in_w.sync = true

    pipeline_run(cmds, opts, [in_r], [in_w], &block)
  end
  module_function :pipeline_w

  # :call-seq:
  #   Open3.pipeline_start([env, ] *cmds, options = {}) -> [wait_threads]
  #
  # Basically a wrapper for
  # {Process.spawn}[rdoc-ref:Process.spawn]
  # that:
  #
  # - Creates a child process for each of the given +cmds+
  #   by calling Process.spawn.
  # - Does not wait for child processes to exit.
  #
  # With no block given, returns an array of the wait threads
  # for all of the child processes.
  #
  # Example:
  #
  #   wait_threads = Open3.pipeline_start('ls', 'grep R')
  #   # => [#<Process::Waiter:0x000055e8de9d2bb0 run>, #<Process::Waiter:0x000055e8de9d2890 run>]
  #   wait_threads.each do |wait_thread|
  #     wait_thread.join
  #   end
  #
  # Output:
  #
  #   Rakefile
  #   README.md
  #
  # With a block given, calls the block with an array of the wait processes:
  #
  #   Open3.pipeline_start('ls', 'grep R') do |wait_threads|
  #     wait_threads.each do |wait_thread|
  #       wait_thread.join
  #     end
  #   end
  #
  # Output:
  #
  #   Rakefile
  #   README.md
  #
  # Like Process.spawn, this method has potential security vulnerabilities
  # if called with untrusted input;
  # see {Command Injection}[rdoc-ref:command_injection.rdoc@Command+Injection].
  #
  # If the first argument is a hash, it becomes leading argument +env+
  # in each call to Process.spawn;
  # see {Execution Environment}[rdoc-ref:Process@Execution+Environment].
  #
  # If the last argument is a hash, it becomes trailing argument +options+
  # in each call to Process.spawn;
  # see {Execution Options}[rdoc-ref:Process@Execution+Options].
  #
  # Each remaining argument in +cmds+ is one of:
  #
  # - A +command_line+: a string that begins with a shell reserved word
  #   or special built-in, or contains one or more metacharacters.
  # - An +exe_path+: the string path to an executable to be called.
  # - An array containing a +command_line+ or an +exe_path+,
  #   along with zero or more string arguments for the command.
  #
  # See {Argument command_line or exe_path}[rdoc-ref:Process@Argument+command_line+or+exe_path].
  #
  def pipeline_start(*cmds, &block)
    if Hash === cmds.last
      opts = cmds.pop.dup
    else
      opts = {}
    end

    if block
      pipeline_run(cmds, opts, [], [], &block)
    else
      ts, = pipeline_run(cmds, opts, [], [])
      ts
    end
  end
  module_function :pipeline_start

  # :call-seq:
  #   Open3.pipeline([env, ] *cmds, options = {}) -> array_of_statuses
  #
  # Basically a wrapper for
  # {Process.spawn}[rdoc-ref:Process.spawn]
  # that:
  #
  # - Creates a child process for each of the given +cmds+
  #   by calling Process.spawn.
  # - Pipes the +stdout+ from each child to the +stdin+ of the next child,
  #   or, for the last child, to the caller's +stdout+.
  # - Waits for the child processes to exit.
  # - Returns an array of Process::Status objects (one for each child).
  #
  # Example:
  #
  #   wait_threads = Open3.pipeline('ls', 'grep R')
  #   # => [#<Process::Status: pid 2139200 exit 0>, #<Process::Status: pid 2139202 exit 0>]
  #
  # Output:
  #
  #   Rakefile
  #   README.md
  #
  # Like Process.spawn, this method has potential security vulnerabilities
  # if called with untrusted input;
  # see {Command Injection}[rdoc-ref:command_injection.rdoc@Command+Injection].
  #
  # If the first argument is a hash, it becomes leading argument +env+
  # in each call to Process.spawn;
  # see {Execution Environment}[rdoc-ref:Process@Execution+Environment].
  #
  # If the last argument is a hash, it becomes trailing argument +options+
  # in each call to Process.spawn'
  # see {Execution Options}[rdoc-ref:Process@Execution+Options].
  #
  # Each remaining argument in +cmds+ is one of:
  #
  # - A +command_line+: a string that begins with a shell reserved word
  #   or special built-in, or contains one or more metacharacters.
  # - An +exe_path+: the string path to an executable to be called.
  # - An array containing a +command_line+ or an +exe_path+,
  #   along with zero or more string arguments for the command.
  #
  # See {Argument command_line or exe_path}[rdoc-ref:Process@Argument+command_line+or+exe_path].
  #
  def pipeline(*cmds)
    if Hash === cmds.last
      opts = cmds.pop.dup
    else
      opts = {}
    end

    pipeline_run(cmds, opts, [], []) {|ts|
      ts.map(&:value)
    }
  end
  module_function :pipeline

  def pipeline_run(cmds, pipeline_opts, child_io, parent_io) # :nodoc:
    if cmds.empty?
      raise ArgumentError, "no commands"
    end

    opts_base = pipeline_opts.dup
    opts_base.delete :in
    opts_base.delete :out

    wait_thrs = []
    r = nil
    cmds.each_with_index {|cmd, i|
      cmd_opts = opts_base.dup
      if String === cmd
        cmd = [cmd]
      else
        cmd_opts.update cmd.pop if Hash === cmd.last
      end
      if i == 0
        if !cmd_opts.include?(:in)
          if pipeline_opts.include?(:in)
            cmd_opts[:in] = pipeline_opts[:in]
          end
        end
      else
        cmd_opts[:in] = r
      end
      if i != cmds.length - 1
        r2, w2 = IO.pipe
        cmd_opts[:out] = w2
      else
        if !cmd_opts.include?(:out)
          if pipeline_opts.include?(:out)
            cmd_opts[:out] = pipeline_opts[:out]
          end
        end
      end
      pid = spawn(*cmd, cmd_opts)
      wait_thrs << Process.detach(pid)
      r&.close
      w2&.close
      r = r2
    }
    result = parent_io + [wait_thrs]
    child_io.each(&:close)
    if defined? yield
      begin
        return yield(*result)
      ensure
        parent_io.each(&:close)
        wait_thrs.each(&:join)
      end
    end
    result
  end
  module_function :pipeline_run
  class << self
    private :pipeline_run
  end

end

# JRuby uses different popen logic on Windows, require it here to reuse wrapper methods above.
require 'open3/jruby_windows' if RUBY_ENGINE == 'jruby' && JRuby::Util::ON_WINDOWS
