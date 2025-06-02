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

module Open3

  # Open stdin, stdout, and stderr streams and start external executable.
  # In addition, a thread to wait for the started process is created.
  # The thread has a pid method and a thread variable :pid which is the pid of
  # the started process.
  #
  # Block form:
  #
  #   Open3.popen3([env,] cmd... [, opts]) {|stdin, stdout, stderr, wait_thr|
  #     pid = wait_thr.pid # pid of the started process.
  #     ...
  #     exit_status = wait_thr.value # Process::Status object returned.
  #   }
  #
  # Non-block form:
  #
  #   stdin, stdout, stderr, wait_thr = Open3.popen3([env,] cmd... [, opts])
  #   pid = wait_thr[:pid]  # pid of the started process
  #   ...
  #   stdin.close  # stdin, stdout and stderr should be closed explicitly in this form.
  #   stdout.close
  #   stderr.close
  #   exit_status = wait_thr.value  # Process::Status object returned.
  #
  # The parameters env, cmd, and opts are passed to Process.spawn.
  # A commandline string and a list of argument strings can be accepted as follows:
  #
  #   Open3.popen3("echo abc") {|i, o, e, t| ... }
  #   Open3.popen3("echo", "abc") {|i, o, e, t| ... }
  #   Open3.popen3(["echo", "argv0"], "abc") {|i, o, e, t| ... }
  #
  # If the last parameter, opts, is a Hash, it is recognized as an option for Process.spawn.
  #
  #   Open3.popen3("pwd", :chdir=>"/") {|i,o,e,t|
  #     p o.read.chomp #=> "/"
  #   }
  #
  # wait_thr.value waits for the termination of the process.
  # The block form also waits for the process when it returns.
  #
  # Closing stdin, stdout and stderr does not wait for the process to complete.
  #
  # You should be careful to avoid deadlocks.
  # Since pipes are fixed length buffers,
  # Open3.popen3("prog") {|i, o, e, t| o.read } deadlocks if
  # the program generates too much output on stderr.
  # You should read stdout and stderr simultaneously (using threads or IO.select).
  # However, if you don't need stderr output, you can use Open3.popen2.
  # If merged stdout and stderr output is not a problem, you can use Open3.popen2e.
  # If you really need stdout and stderr output as separate strings, you can consider Open3.capture3.
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

  # Open3.popen2 is similar to Open3.popen3 except that it doesn't create a pipe for
  # the standard error stream.
  #
  # Block form:
  #
  #   Open3.popen2([env,] cmd... [, opts]) {|stdin, stdout, wait_thr|
  #     pid = wait_thr.pid # pid of the started process.
  #     ...
  #     exit_status = wait_thr.value # Process::Status object returned.
  #   }
  #
  # Non-block form:
  #
  #   stdin, stdout, wait_thr = Open3.popen2([env,] cmd... [, opts])
  #   ...
  #   stdin.close  # stdin and stdout should be closed explicitly in this form.
  #   stdout.close
  #
  # See Process.spawn for the optional hash arguments _env_ and _opts_.
  #
  # Example:
  #
  #   Open3.popen2("wc -c") {|i,o,t|
  #     i.print "answer to life the universe and everything"
  #     i.close
  #     p o.gets #=> "42\n"
  #   }
  #
  #   Open3.popen2("bc -q") {|i,o,t|
  #     i.puts "obase=13"
  #     i.puts "6 * 9"
  #     p o.gets #=> "42\n"
  #   }
  #
  #   Open3.popen2("dc") {|i,o,t|
  #     i.print "42P"
  #     i.close
  #     p o.read #=> "*"
  #   }
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

  # Open3.popen2e is similar to Open3.popen3 except that it merges
  # the standard output stream and the standard error stream.
  #
  # Block form:
  #
  #   Open3.popen2e([env,] cmd... [, opts]) {|stdin, stdout_and_stderr, wait_thr|
  #     pid = wait_thr.pid # pid of the started process.
  #     ...
  #     exit_status = wait_thr.value # Process::Status object returned.
  #   }
  #
  # Non-block form:
  #
  #   stdin, stdout_and_stderr, wait_thr = Open3.popen2e([env,] cmd... [, opts])
  #   ...
  #   stdin.close  # stdin and stdout_and_stderr should be closed explicitly in this form.
  #   stdout_and_stderr.close
  #
  # See Process.spawn for the optional hash arguments _env_ and _opts_.
  #
  # Example:
  #   # check gcc warnings
  #   source = "foo.c"
  #   Open3.popen2e("gcc", "-Wall", source) {|i,oe,t|
  #     oe.each {|line|
  #       if /warning/ =~ line
  #         ...
  #       end
  #     }
  #   }
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

  # Open3.capture3 captures the standard output and the standard error of a command.
  #
  #   stdout_str, stderr_str, status = Open3.capture3([env,] cmd... [, opts])
  #
  # The arguments env, cmd and opts are passed to Open3.popen3 except
  # <code>opts[:stdin_data]</code> and <code>opts[:binmode]</code>.  See Process.spawn.
  #
  # If <code>opts[:stdin_data]</code> is specified, it is sent to the command's standard input.
  #
  # If <code>opts[:binmode]</code> is true, internal pipes are set to binary mode.
  #
  # Examples:
  #
  #   # dot is a command of graphviz.
  #   graph = <<'End'
  #     digraph g {
  #       a -> b
  #     }
  #   End
  #   drawn_graph, dot_log = Open3.capture3("dot -v", :stdin_data=>graph)
  #
  #   o, e, s = Open3.capture3("echo abc; sort >&2", :stdin_data=>"foo\nbar\nbaz\n")
  #   p o #=> "abc\n"
  #   p e #=> "bar\nbaz\nfoo\n"
  #   p s #=> #<Process::Status: pid 32682 exit 0>
  #
  #   # generate a thumbnail image using the convert command of ImageMagick.
  #   # However, if the image is really stored in a file,
  #   # system("convert", "-thumbnail", "80", "png:#{filename}", "png:-") is better
  #   # because of reduced memory consumption.
  #   # But if the image is stored in a DB or generated by the gnuplot Open3.capture2 example,
  #   # Open3.capture3 should be considered.
  #   #
  #   image = File.read("/usr/share/openclipart/png/animals/mammals/sheep-md-v0.1.png", :binmode=>true)
  #   thumbnail, err, s = Open3.capture3("convert -thumbnail 80 png:- png:-", :stdin_data=>image, :binmode=>true)
  #   if s.success?
  #     STDOUT.binmode; print thumbnail
  #   end
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

  # Open3.capture2 captures the standard output of a command.
  #
  #   stdout_str, status = Open3.capture2([env,] cmd... [, opts])
  #
  # The arguments env, cmd and opts are passed to Open3.popen3 except
  # <code>opts[:stdin_data]</code> and <code>opts[:binmode]</code>.  See Process.spawn.
  #
  # If <code>opts[:stdin_data]</code> is specified, it is sent to the command's standard input.
  #
  # If <code>opts[:binmode]</code> is true, internal pipes are set to binary mode.
  #
  # Example:
  #
  #   # factor is a command for integer factorization.
  #   o, s = Open3.capture2("factor", :stdin_data=>"42")
  #   p o #=> "42: 2 3 7\n"
  #
  #   # generate x**2 graph in png using gnuplot.
  #   gnuplot_commands = <<"End"
  #     set terminal png
  #     plot x**2, "-" with lines
  #     1 14
  #     2 1
  #     3 8
  #     4 5
  #     e
  #   End
  #   image, s = Open3.capture2("gnuplot", :stdin_data=>gnuplot_commands, :binmode=>true)
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

  # Open3.capture2e captures the standard output and the standard error of a command.
  #
  #   stdout_and_stderr_str, status = Open3.capture2e([env,] cmd... [, opts])
  #
  # The arguments env, cmd and opts are passed to Open3.popen3 except
  # <code>opts[:stdin_data]</code> and <code>opts[:binmode]</code>.  See Process.spawn.
  #
  # If <code>opts[:stdin_data]</code> is specified, it is sent to the command's standard input.
  #
  # If <code>opts[:binmode]</code> is true, internal pipes are set to binary mode.
  #
  # Example:
  #
  #   # capture make log
  #   make_log, s = Open3.capture2e("make")
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

  # Open3.pipeline_rw starts a list of commands as a pipeline with pipes
  # which connect to stdin of the first command and stdout of the last command.
  #
  #   Open3.pipeline_rw(cmd1, cmd2, ... [, opts]) {|first_stdin, last_stdout, wait_threads|
  #     ...
  #   }
  #
  #   first_stdin, last_stdout, wait_threads = Open3.pipeline_rw(cmd1, cmd2, ... [, opts])
  #   ...
  #   first_stdin.close
  #   last_stdout.close
  #
  # Each cmd is a string or an array.
  # If it is an array, the elements are passed to Process.spawn.
  #
  #   cmd:
  #     commandline                              command line string which is passed to a shell
  #     [env, commandline, opts]                 command line string which is passed to a shell
  #     [env, cmdname, arg1, ..., opts]          command name and one or more arguments (no shell)
  #     [env, [cmdname, argv0], arg1, ..., opts] command name and arguments including argv[0] (no shell)
  #
  #   Note that env and opts are optional, as for Process.spawn.
  #
  # The options to pass to Process.spawn are constructed by merging
  # +opts+, the last hash element of the array, and
  # specifications for the pipes between each of the commands.
  #
  # Example:
  #
  #   Open3.pipeline_rw("tr -dc A-Za-z", "wc -c") {|i, o, ts|
  #     i.puts "All persons more than a mile high to leave the court."
  #     i.close
  #     p o.gets #=> "42\n"
  #   }
  #
  #   Open3.pipeline_rw("sort", "cat -n") {|stdin, stdout, wait_thrs|
  #     stdin.puts "foo"
  #     stdin.puts "bar"
  #     stdin.puts "baz"
  #     stdin.close     # send EOF to sort.
  #     p stdout.read   #=> "     1\tbar\n     2\tbaz\n     3\tfoo\n"
  #   }
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

  # Open3.pipeline_r starts a list of commands as a pipeline with a pipe
  # which connects to stdout of the last command.
  #
  #   Open3.pipeline_r(cmd1, cmd2, ... [, opts]) {|last_stdout, wait_threads|
  #     ...
  #   }
  #
  #   last_stdout, wait_threads = Open3.pipeline_r(cmd1, cmd2, ... [, opts])
  #   ...
  #   last_stdout.close
  #
  # Each cmd is a string or an array.
  # If it is an array, the elements are passed to Process.spawn.
  #
  #   cmd:
  #     commandline                              command line string which is passed to a shell
  #     [env, commandline, opts]                 command line string which is passed to a shell
  #     [env, cmdname, arg1, ..., opts]          command name and one or more arguments (no shell)
  #     [env, [cmdname, argv0], arg1, ..., opts] command name and arguments including argv[0] (no shell)
  #
  #   Note that env and opts are optional, as for Process.spawn.
  #
  # Example:
  #
  #   Open3.pipeline_r("zcat /var/log/apache2/access.log.*.gz",
  #                    [{"LANG"=>"C"}, "grep", "GET /favicon.ico"],
  #                    "logresolve") {|o, ts|
  #     o.each_line {|line|
  #       ...
  #     }
  #   }
  #
  #   Open3.pipeline_r("yes", "head -10") {|o, ts|
  #     p o.read      #=> "y\ny\ny\ny\ny\ny\ny\ny\ny\ny\n"
  #     p ts[0].value #=> #<Process::Status: pid 24910 SIGPIPE (signal 13)>
  #     p ts[1].value #=> #<Process::Status: pid 24913 exit 0>
  #   }
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

  # Open3.pipeline_w starts a list of commands as a pipeline with a pipe
  # which connects to stdin of the first command.
  #
  #   Open3.pipeline_w(cmd1, cmd2, ... [, opts]) {|first_stdin, wait_threads|
  #     ...
  #   }
  #
  #   first_stdin, wait_threads = Open3.pipeline_w(cmd1, cmd2, ... [, opts])
  #   ...
  #   first_stdin.close
  #
  # Each cmd is a string or an array.
  # If it is an array, the elements are passed to Process.spawn.
  #
  #   cmd:
  #     commandline                              command line string which is passed to a shell
  #     [env, commandline, opts]                 command line string which is passed to a shell
  #     [env, cmdname, arg1, ..., opts]          command name and one or more arguments (no shell)
  #     [env, [cmdname, argv0], arg1, ..., opts] command name and arguments including argv[0] (no shell)
  #
  #   Note that env and opts are optional, as for Process.spawn.
  #
  # Example:
  #
  #   Open3.pipeline_w("bzip2 -c", :out=>"/tmp/hello.bz2") {|i, ts|
  #     i.puts "hello"
  #   }
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

  # Open3.pipeline_start starts a list of commands as a pipeline.
  # No pipes are created for stdin of the first command and
  # stdout of the last command.
  #
  #   Open3.pipeline_start(cmd1, cmd2, ... [, opts]) {|wait_threads|
  #     ...
  #   }
  #
  #   wait_threads = Open3.pipeline_start(cmd1, cmd2, ... [, opts])
  #   ...
  #
  # Each cmd is a string or an array.
  # If it is an array, the elements are passed to Process.spawn.
  #
  #   cmd:
  #     commandline                              command line string which is passed to a shell
  #     [env, commandline, opts]                 command line string which is passed to a shell
  #     [env, cmdname, arg1, ..., opts]          command name and one or more arguments (no shell)
  #     [env, [cmdname, argv0], arg1, ..., opts] command name and arguments including argv[0] (no shell)
  #
  #   Note that env and opts are optional, as for Process.spawn.
  #
  # Example:
  #
  #   # Run xeyes in 10 seconds.
  #   Open3.pipeline_start("xeyes") {|ts|
  #     sleep 10
  #     t = ts[0]
  #     Process.kill("TERM", t.pid)
  #     p t.value #=> #<Process::Status: pid 911 SIGTERM (signal 15)>
  #   }
  #
  #   # Convert pdf to ps and send it to a printer.
  #   # Collect error message of pdftops and lpr.
  #   pdf_file = "paper.pdf"
  #   printer = "printer-name"
  #   err_r, err_w = IO.pipe
  #   Open3.pipeline_start(["pdftops", pdf_file, "-"],
  #                        ["lpr", "-P#{printer}"],
  #                        :err=>err_w) {|ts|
  #     err_w.close
  #     p err_r.read # error messages of pdftops and lpr.
  #   }
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

  # Open3.pipeline starts a list of commands as a pipeline.
  # It waits for the completion of the commands.
  # No pipes are created for stdin of the first command and
  # stdout of the last command.
  #
  #   status_list = Open3.pipeline(cmd1, cmd2, ... [, opts])
  #
  # Each cmd is a string or an array.
  # If it is an array, the elements are passed to Process.spawn.
  #
  #   cmd:
  #     commandline                              command line string which is passed to a shell
  #     [env, commandline, opts]                 command line string which is passed to a shell
  #     [env, cmdname, arg1, ..., opts]          command name and one or more arguments (no shell)
  #     [env, [cmdname, argv0], arg1, ..., opts] command name and arguments including argv[0] (no shell)
  #
  #   Note that env and opts are optional, as Process.spawn.
  #
  # Example:
  #
  #   fname = "/usr/share/man/man1/ruby.1.gz"
  #   p Open3.pipeline(["zcat", fname], "nroff -man", "less")
  #   #=> [#<Process::Status: pid 11817 exit 0>,
  #   #    #<Process::Status: pid 11820 exit 0>,
  #   #    #<Process::Status: pid 11828 exit 0>]
  #
  #   fname = "/usr/share/man/man1/ls.1.gz"
  #   Open3.pipeline(["zcat", fname], "nroff -man", "colcrt")
  #
  #   # convert PDF to PS and send to a printer by lpr
  #   pdf_file = "paper.pdf"
  #   printer = "printer-name"
  #   Open3.pipeline(["pdftops", pdf_file, "-"],
  #                  ["lpr", "-P#{printer}"])
  #
  #   # count lines
  #   Open3.pipeline("sort", "uniq -c", :in=>"names.txt", :out=>"count")
  #
  #   # cyclic pipeline
  #   r,w = IO.pipe
  #   w.print "ibase=14\n10\n"
  #   Open3.pipeline("bc", "tee /dev/tty", :in=>r, :out=>w)
  #   #=> 14
  #   #   18
  #   #   22
  #   #   30
  #   #   42
  #   #   58
  #   #   78
  #   #   106
  #   #   202
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
