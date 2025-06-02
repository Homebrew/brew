[![Ruby](https://github.com/ruby/debug/actions/workflows/ruby.yml/badge.svg?branch=master)](https://github.com/ruby/debug/actions/workflows/ruby.yml?query=branch%3Amaster) [![Protocol](https://github.com/ruby/debug/actions/workflows/protocol.yml/badge.svg)](https://github.com/ruby/debug/actions/workflows/protocol.yml)

# debug.rb

This library provides debugging functionality to Ruby (MRI) 2.6 and later.

This debug.rb is replacement of traditional lib/debug.rb standard library which is implemented by `set_trace_func`.
New debug.rb has several advantages:

* Fast: No performance penalty on non-stepping mode and non-breakpoints.
* [Remote debugging](#remote-debugging): Support remote debugging natively.
  * UNIX domain socket (UDS)
  * TCP/IP
  * Integration with rich debugger frontends

     Frontend |  [Console](https://github.com/ruby/debug#invoke-as-a-remote-debuggee) | [VSCode](https://github.com/ruby/debug#vscode-integration) | [Chrome DevTool](#chrome-devtool-integration) |
     ---|---|---|---|
     Connection | UDS, TCP/IP | UDS, TCP/IP | TCP/IP |
     Requirement | No | [vscode-rdbg](https://marketplace.visualstudio.com/items?itemName=KoichiSasada.vscode-rdbg) | Chrome |

* Extensible: application can introduce debugging support with several ways:
  * By `rdbg` command
  * By loading libraries with `-r` command line option
  * By calling Ruby's method explicitly
* Misc
  * Support threads (almost done) and ractors (TODO).
  * Support suspending and entering to the console debugging with `Ctrl-C` at most of timing.
  * Show parameters on backtrace command.
  * Support recording & reply debugging.

# Installation

```
$ gem install debug
```

or specify `-Ipath/to/debug/lib` in `RUBYOPT` or each ruby command-line option, especially for debug this gem development.

If you use Bundler, write the following line to your Gemfile.

```
gem "debug", ">= 1.0.0"
```

(The version constraint is important; `debug < 1.0.0` is an older,
abandoned gem that is completely different from this product.)

# HOW TO USE

To use a debugger, roughly you will do the following steps:

1. Set breakpoints.
2. Run a program with the debugger.
3. At the breakpoint, enter the debugger console.
4. Use debug commands.
    * [Evaluate Ruby expressions](#evaluate) (e.g. `p lvar` to see the local variable `lvar`).
    * [Query the program status](#information) (e.g. `info` to see information about the current frame).
    * [Control program flow](#control-flow) (e.g. move to the another line with `step`, to the next line with `next`).
    * [Set another breakpoint](#breakpoint) (e.g. `catch Exception` to set a breakpoint that'll be triggered when `Exception` is raised).
    * [Activate tracing in your program](#trace) (e.g. `trace call` to trace method calls).
    * [Change the configuration](#configuration-1) (e.g. `config set no_color true` to disable coloring).
    * Continue the program (`c` or `continue`) and goto 3.

## Invoke with the debugger

There are several options for (1) and (2). Please choose your favorite way.

### Modify source code with [`binding.break`](#bindingbreak-method) (similar to `binding.pry` or `binding.irb`)

If you can modify the source code, you can use the debugger by adding `require 'debug'` at the top of your program and putting [`binding.break`](#bindingbreak-method) method into lines where you want to stop as breakpoints like `binding.pry` and `binding.irb`.

You can also use its 2 aliases in the same way:

- `binding.b`
- `debugger`

After that, run the program as usual and you will enter the debug console at breakpoints you inserted.

The following example shows the demonstration of [`binding.break`](#bindingbreak-method).

```shell
$ cat target.rb                        # Sample program
require 'debug'

a = 1
b = 2
binding.break                          # Program will stop here
c = 3
d = 4
binding.break                          # Program will stop here
p [a, b, c, d]

$ ruby target.rb                       # Run the program normally.
DEBUGGER: Session start (pid: 7604)
[1, 10] in target.rb
      1| require 'debug'
      2|
      3| a = 1
      4| b = 2
=>    5| binding.break                 # Now you can see it stops at this line
      6| c = 3
      7| d = 4
      8| binding.break
      9| p [a, b, c, d]
     10|
=>#0    <main> at target.rb:5

(rdbg) info locals                     # You can show local variables
=>#0    <main> at target.rb:5
%self => main
a => 1
b => 2
c => nil
d => nil

(rdbg) continue                        # Continue the execution
[3, 11] in target.rb
      3| a = 1
      4| b = 2
      5| binding.break
      6| c = 3
      7| d = 4
=>    8| binding.break                 # Again the program stops here
      9| p [a, b, c, d]
     10|
     11| __END__
=>#0    <main> at target.rb:8

(rdbg) info locals                     # And you can see the updated local variables
=>#0    <main> at target.rb:8
%self => main
a => 1
b => 2
c => 3
d => 4

(rdbg) continue
[1, 2, 3, 4]
```

### Invoke the program from the debugger as a traditional debuggers

If you don't want to modify the source code, you can set breakpoints with a debug command `break` (`b` for short).
Using `rdbg` command (or `bundle exec rdbg`) to launch the program without any modifications, you can run the program with the debugger.

```shell
$ cat target.rb                        # Sample program
a = 1
b = 2
c = 3
d = 4
p [a, b, c, d]

$ rdbg target.rb                       # run like `ruby target.rb`
DEBUGGER: Session start (pid: 7656)
[1, 7] in target.rb
=>    1| a = 1
      2| b = 2
      3| c = 3
      4| d = 4
      5| p [a, b, c, d]
      6|
      7| __END__
=>#0    <main> at target.rb:1

(rdbg)
```

`rdbg` command suspends the program at the beginning of the given script (`target.rb` in this case) and you can use debug commands. `(rdbg)` is prompt. Let's set breakpoints on line 3 and line 5 with `break` command (`b` for short).

```shell
(rdbg) break 3                         # set breakpoint at line 3
#0  BP - Line  /mnt/c/ko1/src/rb/ruby-debug/target.rb:3 (line)

(rdbg) b 5                             # set breakpoint at line 5
#1  BP - Line  /mnt/c/ko1/src/rb/ruby-debug/target.rb:5 (line)

(rdbg) break                           # show all registered breakpoints
#0  BP - Line  /mnt/c/ko1/src/rb/ruby-debug/target.rb:3 (line)
#1  BP - Line  /mnt/c/ko1/src/rb/ruby-debug/target.rb:5 (line)
```

You can see that two breakpoints are registered. Let's continue the program by `continue` command.

```shell
(rdbg) continue
[1, 7] in target.rb
      1| a = 1
      2| b = 2
=>    3| c = 3
      4| d = 4
      5| p [a, b, c, d]
      6|
      7| __END__
=>#0    <main> at target.rb:3

Stop by #0  BP - Line  /mnt/c/ko1/src/rb/ruby-debug/target.rb:3 (line)

(rdbg)
```

You can see that we can stop at line 3.
Let's see the local variables with `info` command, and continue.
You can also confirm that the program will suspend at line 5 and you can use `info` command again.

```shell
(rdbg) info
=>#0    <main> at target.rb:3
%self => main
a => 1
b => 2
c => nil
d => nil

(rdbg) continue
[1, 7] in target.rb
      1| a = 1
      2| b = 2
      3| c = 3
      4| d = 4
=>    5| p [a, b, c, d]
      6|
      7| __END__
=>#0    <main> at target.rb:5

Stop by #1  BP - Line  /mnt/c/ko1/src/rb/ruby-debug/target.rb:5 (line)

(rdbg) info
=>#0    <main> at target.rb:5
%self => main
a => 1
b => 2
c => 3
d => 4

(rdbg) continue
[1, 2, 3, 4]
```

By the way, using `rdbg` command you can suspend your application with `C-c` (SIGINT) and enter the debug console.
It will help that if you want to know what the program is doing.

### Use `rdbg` with commands written in Ruby

If you want to run a command written in Ruby like like `rake`, `rails`, `bundle`, `rspec` and so on, you can use `rdbg -c` option.

* Without `-c` option, `rdbg <name>` means that `<name>` is Ruby script and invoke it like `ruby <name>` with the debugger.
* With `-c` option, `rdbg -c <name>` means that `<name>` is command in `PATH` and simply invoke it with the debugger.

Examples:
* `rdbg -c -- rails server`
* `rdbg -c -- bundle exec ruby foo.rb`
* `rdbg -c -- bundle exec rake test`
* `rdbg -c -- ruby target.rb` is same as `rdbg target.rb`

NOTE: `--` is needed to separate the command line options for `rdbg` and invoking command. For example, `rdbg -c rake -T` is recognized like `rdbg -c -T -- rake`. It should be `rdbg -c -- rake -T`.

NOTE: If you want to use bundler (`bundle` command), you need to write `gem debug` line in your `Gemfile`.

### Using VSCode

Like other languages, you can use this debugger on the VSCode.

1. Install [VSCode rdbg Ruby Debugger - Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=KoichiSasada.vscode-rdbg)
2. Open `.rb` file (e.g. `target.rb`)
3. Register breakpoints with "Toggle breakpoint" in Run menu (or type F9 key)
4. Choose "Start debugging" in "Run" menu (or type F5 key)
5. You will see a dialog "Debug command line" and you can choose your favorite command line your want to run.
6. Chosen command line is invoked with `rdbg -c` and VSCode shows the details at breakpoints.

Please refer [Debugging in Visual Studio Code](https://code.visualstudio.com/docs/editor/debugging) for operations on VSCode.

You can configure the extension in `.vscode/launch.json`.
Please see the extension page for more details.

## Remote debugging

You can use this debugger as a remote debugger. For example, it will help the following situations:

* Your application does not run on TTY and it is hard to use `binding.pry` or `binding.irb`.
  * Your application is running on Docker container and there is no TTY.
  * Your application is running as a daemon.
  * Your application uses pipe for STDIN or STDOUT.
* Your application is running as a daemon and you want to query the running status (checking a backtrace and so on).

You can run your application as a remote debuggee and the remote debugger console can attach to the debuggee anytime.

### Invoke as a remote debuggee

There are multiple ways to run your program as a debuggee:

Stop at program start | [`rdbg` option](https://github.com/ruby/debug#rdbg---open-or-rdbg--o-for-short) | [require](https://github.com/ruby/debug#require-debugopen-in-a-program) | [debugger API](https://github.com/ruby/debug#start-by-method)
---|---|---|---|
Yes | `rdbg --open` | `require "debug/open"` | `DEBUGGER__.open`
No | `rdbg --open --nonstop` | `require "debug/open_nonstop"` | `DEBUGGER__.open(nonstop: true)`

#### `rdbg --open` (or `rdbg -O` for short)

You can run a script with `rdbg --open target.rb` command and run a `target.rb` as a debuggee program. It also opens the network port and suspends at the beginning of `target.rb`.

```shell
$ exe/rdbg --open target.rb
DEBUGGER: Session start (pid: 7773)
DEBUGGER: Debugger can attach via UNIX domain socket (/home/ko1/.ruby-debug-sock/ruby-debug-ko1-7773)
DEBUGGER: wait for debugger connection...
```

By default, `rdbg --open` uses UNIX domain socket and generates path name automatically (`/home/ko1/.ruby-debug-sock/ruby-debug-ko1-7773` in this case).

You can connect to the debuggee with `rdbg --attach` command (`rdbg -A` for short).

```shell
$ rdbg -A
[1, 7] in target.rb
=>    1| a = 1
      2| b = 2
      3| c = 3
      4| d = 4
      5| p [a, b, c, d]
      6|
      7| __END__
=>#0    <main> at target.rb:1

(rdbg:remote)
```

If there is no other opening ports on the default directory, `rdbg --attach` command chooses the only one opening UNIX domain socket and connect to it. If there are more files, you need to specify the file.

When `rdbg --attach` connects to the debuggee, you can use any debug commands (set breakpoints, continue the program and so on) like local debug console. When an debuggee program exits, the remote console will also terminate.

NOTE: If you use `quit` command, only remote console exits and the debuggee program continues to run (and you can connect it again). If you want to exit the debuggee program, use `kill` command.

If you want to use TCP/IP for the remote debugging, you need to specify the port and host with `--port` like `rdbg --open --port 12345` and it binds to `localhost:12345`.

To connect to the debuggee, you need to specify the port.

```shell
$ rdbg --attach 12345
```

If you want to choose the host to bind, you can use `--host` option.
Note that all messages communicated between the debugger and the debuggee are *NOT* encrypted so please use remote debugging carefully.

#### `require 'debug/open'` in a program

If you can modify the program, you can open debugging port by adding `require 'debug/open'` line in the program.

If you don't want to stop the program at the beginning, you can also use `require 'debug/open_nonstop'`.
Using `debug/open_nonstop` is useful if you want to open a backdoor to the application.
However, it is also danger because it can become another vulnerability.
Please use it carefully.

By default, UNIX domain socket is used for the debugging port. To use TCP/IP, you can set the `RUBY_DEBUG_PORT` environment variable.

```shell
$ RUBY_DEBUG_PORT=12345 ruby target.rb
```

### Integration with external debugger frontend

You can attach with external debugger frontend with VSCode and Chrome.

```
$ rdbg --open=[frontend] target.rb
```

will open a debug port and `[frontend]` can attach to the port.

Also `open` command allows opening the debug port.

#### VSCode integration

([vscode-rdbg v0.0.9](https://marketplace.visualstudio.com/items?itemName=KoichiSasada.vscode-rdbg) or later is required)

If you don't run a debuggee Ruby process on VSCode, you can attach with VSCode later with the following steps.

`rdbg --open=vscode` opens the debug port and tries to invoke the VSCode (`code` command).

```
$ rdbg --open=vscode target.rb
DEBUGGER: Debugger can attach via UNIX domain socket (/tmp/ruby-debug-sock-1000/ruby-debug-ko1-27706)
DEBUGGER: wait for debugger connection...
Launching: code /tmp/ruby-debug-vscode-20211014-27706-gd7e85/ /tmp/ruby-debug-vscode-20211014-27706-gd7e85/README.rb
DEBUGGER: Connected.
```

And it tries to invoke the new VSCode window and VSCode starts attaching to the debuggee Ruby program automatically.

You can also use `open vscode` command in REPL.

```
$ rdbg target.rb
[1, 8] in target.rb
     1|
=>   2| p a = 1
     3| p b = 2
     4| p c = 3
     5| p d = 4
     6| p e = 5
     7|
     8| __END__
=>#0    <main> at target.rb:2
(rdbg) open vscode    # command
DEBUGGER: wait for debugger connection...
DEBUGGER: Debugger can attach via UNIX domain socket (/tmp/ruby-debug-sock-1000/ruby-debug-ko1-28337)
Launching: code /tmp/ruby-debug-vscode-20211014-28337-kg9dm/ /tmp/ruby-debug-vscode-20211014-28337-kg9dm/README.rb
DEBUGGER: Connected.
```

If the machine which runs the Ruby process doesn't have a `code` command, the following message will be shown:

```
(rdbg) open vscode
DEBUGGER: wait for debugger connection...
DEBUGGER: Debugger can attach via UNIX domain socket (/tmp/ruby-debug-sock-1000/ruby-debug-ko1-455)
Launching: code /tmp/ruby-debug-vscode-20211014-455-gtjpwi/ /tmp/ruby-debug-vscode-20211014-455-gtjpwi/README.rb
DEBUGGER: Can not invoke the command.
Use the command-line on your terminal (with modification if you need).

  code /tmp/ruby-debug-vscode-20211014-455-gtjpwi/ /tmp/ruby-debug-vscode-20211014-455-gtjpwi/README.rb

If your application is running on a SSH remote host, please try:

  code --remote ssh-remote+[SSH hostname] /tmp/ruby-debug-vscode-20211014-455-gtjpwi/ /tmp/ruby-debug-vscode-20211014-455-gtjpwi/README.rb

```

and try to use proposed commands.

Note that you can attach with `rdbg --attach` and continue REPL debugging.

#### Chrome DevTool integration

With `rdbg --open=chrome` command will show the following message.

```
$ rdbg target.rb --open=chrome
DEBUGGER: Debugger can attach via TCP/IP (127.0.0.1:43633)
DEBUGGER: With Chrome browser, type the following URL in the address-bar:

   devtools://devtools/bundled/inspector.html?v8only=true&panel=sources&ws=127.0.0.1:57231/b32a55cd-2eb5-4c5c-87d8-b3dfc59d80ef

DEBUGGER: wait for debugger connection...
```

Type `devtools://devtools/bundled/inspector.html?v8only=true&panel=sources&ws=127.0.0.1:57231/b32a55cd-2eb5-4c5c-87d8-b3dfc59d80ef` in the address-bar on Chrome browser, and you can continue the debugging with chrome browser.

Also `open chrome` command works like `open vscode`.

For more information about how to use Chrome debugging, you might want to read [here](https://developer.chrome.com/docs/devtools/).

## Configuration

You can configure the debugger's behavior with debug commands and environment variables.
When the debug session is started, initial scripts are loaded so you can put your favorite configurations in the initial scripts.

### Configuration list

You can configure debugger's behavior with environment variables and `config` command. Each configuration has environment variable and the name which can be specified by `config` command.

```
# configuration example
config set log_level INFO
config set no_color true
```



* UI
  * `RUBY_DEBUG_LOG_LEVEL` (`log_level`): Log level same as Logger (default: WARN)
  * `RUBY_DEBUG_SHOW_SRC_LINES` (`show_src_lines`): Show n lines source code on breakpoint (default: 10)
  * `RUBY_DEBUG_SHOW_FRAMES` (`show_frames`): Show n frames on breakpoint (default: 2)
  * `RUBY_DEBUG_USE_SHORT_PATH` (`use_short_path`): Show shorten PATH (like $(Gem)/foo.rb) (default: false)
  * `RUBY_DEBUG_NO_COLOR` (`no_color`): Do not use colorize (default: false)
  * `RUBY_DEBUG_NO_SIGINT_HOOK` (`no_sigint_hook`): Do not suspend on SIGINT (default: false)
  * `RUBY_DEBUG_NO_RELINE` (`no_reline`): Do not use Reline library (default: false)
  * `RUBY_DEBUG_NO_HINT` (`no_hint`): Do not show the hint on the REPL (default: false)

* CONTROL
  * `RUBY_DEBUG_SKIP_PATH` (`skip_path`): Skip showing/entering frames for given paths
  * `RUBY_DEBUG_SKIP_NOSRC` (`skip_nosrc`): Skip on no source code lines (default: false)
  * `RUBY_DEBUG_KEEP_ALLOC_SITE` (`keep_alloc_site`): Keep allocation site and p, pp shows it (default: false)
  * `RUBY_DEBUG_POSTMORTEM` (`postmortem`): Enable postmortem debug (default: false)
  * `RUBY_DEBUG_FORK_MODE` (`fork_mode`): Control which process activates a debugger after fork (both/parent/child) (default: both)
  * `RUBY_DEBUG_SIGDUMP_SIG` (`sigdump_sig`): Sigdump signal (default: false)

* BOOT
  * `RUBY_DEBUG_NONSTOP` (`nonstop`): Nonstop mode (default: false)
  * `RUBY_DEBUG_STOP_AT_LOAD` (`stop_at_load`): Stop at just loading location (default: false)
  * `RUBY_DEBUG_INIT_SCRIPT` (`init_script`): debug command script path loaded at first stop
  * `RUBY_DEBUG_COMMANDS` (`commands`): debug commands invoked at first stop. commands should be separated by ';;'
  * `RUBY_DEBUG_NO_RC` (`no_rc`): ignore loading ~/.rdbgrc(.rb) (default: false)
  * `RUBY_DEBUG_HISTORY_FILE` (`history_file`): history file (default: ~/.rdbg_history)
  * `RUBY_DEBUG_SAVE_HISTORY` (`save_history`): maximum save history lines (default: 10000)

* REMOTE
  * `RUBY_DEBUG_PORT` (`port`): TCP/IP remote debugging: port
  * `RUBY_DEBUG_HOST` (`host`): TCP/IP remote debugging: host (default: 127.0.0.1)
  * `RUBY_DEBUG_SOCK_PATH` (`sock_path`): UNIX Domain Socket remote debugging: socket path
  * `RUBY_DEBUG_SOCK_DIR` (`sock_dir`): UNIX Domain Socket remote debugging: socket directory
  * `RUBY_DEBUG_LOCAL_FS_MAP` (`local_fs_map`): Specify local fs map
  * `RUBY_DEBUG_SKIP_BP` (`skip_bp`): Skip breakpoints if no clients are attached (default: false)
  * `RUBY_DEBUG_COOKIE` (`cookie`): Cookie for negotiation
  * `RUBY_DEBUG_OPEN_FRONTEND` (`open_frontend`): frontend used by open command (vscode, chrome, default: rdbg).
  * `RUBY_DEBUG_CHROME_PATH` (`chrome_path`): Platform dependent path of Chrome (For more information, See [here](https://github.com/ruby/debug/pull/334/files#diff-5fc3d0a901379a95bc111b86cf0090b03f857edfd0b99a0c1537e26735698453R55-R64))

* OBSOLETE
  * `RUBY_DEBUG_PARENT_ON_FORK` (`parent_on_fork`): Keep debugging parent process on fork (default: false)

There are other environment variables:

* `NO_COLOR`: If the value is set, set `RUBY_DEBUG_NO_COLOR` ([NO_COLOR: disabling ANSI color output in various Unix commands](https://no-color.org/)).
* `RUBY_DEBUG_ENABLE`: If the value is `0`, do not enable debug.gem feature.
* `RUBY_DEBUG_ADDED_RUBYOPT`: Remove this value from `RUBYOPT` at first. This feature helps loading debug.gem with `RUBYOPT='-r debug/...'` and you don't want to derive it to child processes. In this case you can set `RUBY_DEBUG_ADDED_RUBYOPT='-r debug/...'` (same value) and this string will be deleted from `RUBYOPT` at first.
* `RUBY_DEBUG_EDITOR` or `EDITOR`: An editor used by `edit` debug command.
* `RUBY_DEBUG_BB`: Define `Kernel#bb` method which is alias of `Kernel#debugger`.

### Initial scripts

If there is `~/.rdbgrc`, the file is loaded as an initial script (which contains debug commands) when the debug session is started.

* `RUBY_DEBUG_INIT_SCRIPT` environment variable can specify the initial script file.
* You can specify the initial script with `rdbg -x initial_script` (like gdb's `-x` option).

Initial scripts are useful to write your favorite configurations.
For example, you can set break points with `break file:123` in `~/.rdbgrc`.

If there are `~/.rdbgrc.rb` is available, it is also loaded as a ruby script at same timing.

## Debug command on the debug console

On the debug console, you can use the following debug commands.

There are additional features:

* `<expr>` without debug command is almost same as `pp <expr>`.
  * If the input line `<expr>` does *NOT* start with any debug command, the line `<expr>` will be evaluated as a Ruby expression and the result will be printed with `pp` method. So that the input `foo.bar` is same as `pp foo.bar`.
  * If `<expr>` is recognized as a debug command, of course it is not evaluated as a Ruby expression, but is executed as debug command. For example, you can not evaluate such single letter local variables `i`, `b`, `n`, `c` because they are single letter debug commands. Use `p i` instead.
* `Enter` without any input repeats the last command (useful when repeating `step`s).
* `Ctrl-D` is equal to `quit` command.
* [debug command compare sheet - Google Sheets](https://docs.google.com/spreadsheets/d/1TlmmUDsvwK4sSIyoMv-io52BUUz__R5wpu-ComXlsw0/edit?usp=sharing)

You can use the following debug commands. Each command should be written in 1 line.
The `[...]` notation means this part can be eliminate. For example, `s[tep]` means `s` or `step` are valid command. `ste` is not valid.
The `<...>` notation means the argument.

### Control flow

* `s[tep]`
  * Step in. Resume the program until next breakable point.
* `s[tep] <n>`
  * Step in, resume the program at `<n>`th breakable point.
* `n[ext]`
  * Step over. Resume the program until next line.
* `n[ext] <n>`
  * Step over, same as `step <n>`.
* `fin[ish]`
  * Finish this frame. Resume the program until the current frame is finished.
* `fin[ish] <n>`
  * Finish `<n>`th frames.
* `c[ontinue]`
  * Resume the program.
* `q[uit]` or `Ctrl-D`
  * Finish debugger (with the debuggee process on non-remote debugging).
* `q[uit]!`
  * Same as q[uit] but without the confirmation prompt.
* `kill`
  * Stop the debuggee process with `Kernel#exit!`.
* `kill!`
  * Same as kill but without the confirmation prompt.
* `sigint`
  * Execute SIGINT handler registered by the debuggee.
  * Note that this command should be used just after stop by `SIGINT`.

### Breakpoint

* `b[reak]`
  * Show all breakpoints.
* `b[reak] <line>`
  * Set breakpoint on `<line>` at the current frame's file.
* `b[reak] <file>:<line>` or `<file> <line>`
  * Set breakpoint on `<file>:<line>`.
* `b[reak] <class>#<name>`
   * Set breakpoint on the method `<class>#<name>`.
* `b[reak] <expr>.<name>`
   * Set breakpoint on the method `<expr>.<name>`.
* `b[reak] ... if: <expr>`
  * break if `<expr>` is true at specified location.
* `b[reak] ... pre: <command>`
  * break and run `<command>` before stopping.
* `b[reak] ... do: <command>`
  * break and run `<command>`, and continue.
* `b[reak] ... path: <path>`
  * break if the path matches to `<path>`. `<path>` can be a regexp with `/regexp/`.
* `b[reak] if: <expr>`
  * break if: `<expr>` is true at any lines.
  * Note that this feature is super slow.
* `catch <Error>`
  * Set breakpoint on raising `<Error>`.
* `catch ... if: <expr>`
  * stops only if `<expr>` is true as well.
* `catch ... pre: <command>`
  * runs `<command>` before stopping.
* `catch ... do: <command>`
  * stops and run `<command>`, and continue.
* `catch ... path: <path>`
  * stops if the exception is raised from a `<path>`. `<path>` can be a regexp with `/regexp/`.
* `watch @ivar`
  * Stop the execution when the result of current scope's `@ivar` is changed.
  * Note that this feature is super slow.
* `watch ... if: <expr>`
  * stops only if `<expr>` is true as well.
* `watch ... pre: <command>`
  * runs `<command>` before stopping.
* `watch ... do: <command>`
  * stops and run `<command>`, and continue.
* `watch ... path: <path>`
  * stops if the path matches `<path>`. `<path>` can be a regexp with `/regexp/`.
* `del[ete]`
  * delete all breakpoints.
* `del[ete] <bpnum>`
  * delete specified breakpoint.

### Information

* `bt` or `backtrace`
  * Show backtrace (frame) information.
* `bt <num>` or `backtrace <num>`
  * Only shows first `<num>` frames.
* `bt /regexp/` or `backtrace /regexp/`
  * Only shows frames with method name or location info that matches `/regexp/`.
* `bt <num> /regexp/` or `backtrace <num> /regexp/`
  * Only shows first `<num>` frames with method name or location info that matches `/regexp/`.
* `l[ist]`
  * Show current frame's source code.
  * Next `list` command shows the successor lines.
* `l[ist] -`
  * Show predecessor lines as opposed to the `list` command.
* `l[ist] <start>` or `l[ist] <start>-<end>`
  * Show current frame's source code from the line <start> to <end> if given.
* `edit`
  * Open the current file on the editor (use `EDITOR` environment variable).
  * Note that edited file will not be reloaded.
* `edit <file>`
  * Open <file> on the editor.
* `i[nfo]`
   * Show information about current frame (local/instance variables and defined constants).
* `i[nfo] l[ocal[s]]`
  * Show information about the current frame (local variables)
  * It includes `self` as `%self` and a return value as `%return`.
* `i[nfo] i[var[s]]` or `i[nfo] instance`
  * Show information about instance variables about `self`.
* `i[nfo] c[onst[s]]` or `i[nfo] constant[s]`
  * Show information about accessible constants except toplevel constants.
* `i[nfo] g[lobal[s]]`
  * Show information about global variables
* `i[nfo] ... /regexp/`
  * Filter the output with `/regexp/`.
* `i[nfo] th[read[s]]`
  * Show all threads (same as `th[read]`).
* `o[utline]` or `ls`
  * Show you available methods, constants, local variables, and instance variables in the current scope.
* `o[utline] <expr>` or `ls <expr>`
  * Show you available methods and instance variables of the given object.
  * If the object is a class/module, it also lists its constants.
* `display`
  * Show display setting.
* `display <expr>`
  * Show the result of `<expr>` at every suspended timing.
* `undisplay`
  * Remove all display settings.
* `undisplay <displaynum>`
  * Remove a specified display setting.

### Frame control

* `f[rame]`
  * Show the current frame.
* `f[rame] <framenum>`
  * Specify a current frame. Evaluation are run on specified frame.
* `up`
  * Specify the upper frame.
* `down`
  * Specify the lower frame.

### Evaluate

* `p <expr>`
  * Evaluate like `p <expr>` on the current frame.
* `pp <expr>`
  * Evaluate like `pp <expr>` on the current frame.
* `eval <expr>`
  * Evaluate `<expr>` on the current frame.
* `irb`
  * Invoke `irb` on the current frame.

### Trace

* `trace`
  * Show available tracers list.
* `trace line`
  * Add a line tracer. It indicates line events.
* `trace call`
  * Add a call tracer. It indicate call/return events.
* `trace exception`
  * Add an exception tracer. It indicates raising exceptions.
* `trace object <expr>`
  * Add an object tracer. It indicates that an object by `<expr>` is passed as a parameter or a receiver on method call.
* `trace ... /regexp/`
  * Indicates only matched events to `/regexp/`.
* `trace ... into: <file>`
  * Save trace information into: `<file>`.
* `trace off <num>`
  * Disable tracer specified by `<num>` (use `trace` command to check the numbers).
* `trace off [line|call|pass]`
  * Disable all tracers. If `<type>` is provided, disable specified type tracers.
* `record`
  * Show recording status.
* `record [on|off]`
  * Start/Stop recording.
* `step back`
  * Start replay. Step back with the last execution log.
  * `s[tep]` does stepping forward with the last log.
* `step reset`
  * Stop replay .

### Thread control

* `th[read]`
  * Show all threads.
* `th[read] <thnum>`
  * Switch thread specified by `<thnum>`.

### Configuration

* `config`
  * Show all configuration with description.
* `config <name>`
  * Show current configuration of <name>.
* `config set <name> <val>` or `config <name> = <val>`
  * Set <name> to <val>.
* `config append <name> <val>` or `config <name> << <val>`
  * Append `<val>` to `<name>` if it is an array.
* `config unset <name>`
  * Set <name> to default.
* `source <file>`
  * Evaluate lines in `<file>` as debug commands.
* `open`
  * open debuggee port on UNIX domain socket and wait for attaching.
  * Note that `open` command is EXPERIMENTAL.
* `open [<host>:]<port>`
  * open debuggee port on TCP/IP with given `[<host>:]<port>` and wait for attaching.
* `open vscode`
  * open debuggee port for VSCode and launch VSCode if available.
* `open chrome`
  * open debuggee port for Chrome and wait for attaching.

### Help

* `h[elp]`
  * Show help for all commands.
* `h[elp] <command>`
  * Show help for the given command.


## Debugger API

### Start debugging

#### Start by requiring a library

You can start debugging without `rdbg` command by requiring the following libraries:

* `require 'debug'`: Same as `rdbg --nonstop --no-sigint-hook`.
* `require 'debug/start'`: Same as `rdbg`.
* `require 'debug/open'`: Same as `rdbg --open`.
* `require 'debug/open_nonstop'`: Same as `rdbg --open --nonstop`.

You need to require one of them at the very beginning of the application.
Using `ruby -r` (for example `ruby -r debug/start target.rb`) is another way to invoke with debugger.

NOTE: Until Ruby 3.0, there is old `lib/debug.rb` standard library. So that if this gem is not installed, or if `Gemfile` missed to list this gem and `bundle exec` is used, you will see the following output:

```shell
$ ruby -r debug -e0
.../2.7.3/lib/ruby/2.7.0/x86_64-linux/continuation.so: warning: callcc is obsolete; use Fiber instead
Debug.rb
Emacs support available.

.../2.7.3/lib/ruby/2.7.0/rubygems/core_ext/kernel_require.rb:162:    if RUBYGEMS_ACTIVATION_MONITOR.respond_to?(:mon_owned?)
(rdb:1)
```

`lib/debug.rb` was not maintained well in recent years, and the purpose of this library is to rewrite old `lib/debug.rb` with recent techniques.

#### Start by method

After loading `debug/session`, you can start debug session with the following methods. They are convenient if you want to specify debug configurations in your program.

* `DEBUGGER__.start(**kw)`: start debug session with local console.
* `DEBUGGER__.open(**kw)`: open debug port with configuration (without configurations open with UNIX domain socket)
* `DEBUGGER__.open_unix(**kw)`: open debug port with UNIX domain socket
* `DEBUGGER__.open_tcp(**kw)`: open debug port with TCP/IP

For example:

```ruby
require 'debug/session'
DEBUGGER__.start(no_color: true,    # disable colorize
                 log_level: 'INFO') # Change log_level to INFO

... # your application code
```

### `binding.break` method

`binding.break` (or `binding.b`) set breakpoints at written line. It also has several keywords.

If `do: 'command'` is specified, the debugger suspends the program and run the `command` as a debug command and continue the program.
It is useful if you only want to call a debug command and don't want to stop there.

```
def initialize
  @a = 1
  binding.b do: 'watch @a'
end
```

On this case, register a watch breakpoint for `@a` and continue to run.

If `pre: 'command'` is specified, the debugger suspends the program and run the `command` as a debug command, and keep suspend.
It is useful if you have operations before suspend.

```
def foo
  binding.b pre: 'p bar()'
  ...
end
```

On this case, you can see the result of `bar()` every time you stop there.

## rdbg command help

```
exe/rdbg [options] -- [debuggee options]

Debug console mode:
    -n, --nonstop                    Do not stop at the beginning of the script.
    -e DEBUG_COMMAND                 Execute debug command at the beginning of the script.
    -x, --init-script=FILE           Execute debug command in the FILE.
        --no-rc                      Ignore ~/.rdbgrc
        --no-color                   Disable colorize
        --no-sigint-hook             Disable to trap SIGINT
    -c, --command                    Enable command mode.
                                     The first argument should be a command name in $PATH.
                                     Example: 'rdbg -c bundle exec rake test'

    -O, --open=[FRONTEND]            Start remote debugging with opening the network port.
                                     If TCP/IP options are not given, a UNIX domain socket will be used.
                                     If FRONTEND is given, prepare for the FRONTEND.
                                     Now rdbg, vscode and chrome is supported.
        --sock-path=SOCK_PATH        UNIX Domain socket path
        --port=PORT                  Listening TCP/IP port
        --host=HOST                  Listening TCP/IP host
        --cookie=COOKIE              Set a cookie for connection

  Debug console mode runs Ruby program with the debug console.

  'rdbg target.rb foo bar'                starts like 'ruby target.rb foo bar'.
  'rdbg -- -r foo -e bar'                 starts like 'ruby -r foo -e bar'.
  'rdbg -c rake test'                     starts like 'rake test'.
  'rdbg -c -- rake test -t'               starts like 'rake test -t'.
  'rdbg -c bundle exec rake test'         starts like 'bundle exec rake test'.
  'rdbg -O target.rb foo bar'             starts and accepts attaching with UNIX domain socket.
  'rdbg -O --port 1234 target.rb foo bar' starts accepts attaching with TCP/IP localhost:1234.
  'rdbg -O --port 1234 -- -r foo -e bar'  starts accepts attaching with TCP/IP localhost:1234.
  'rdbg target.rb -O chrome --port 1234'  starts and accepts connecting from Chrome Devtools with localhost:1234.

Attach mode:
    -A, --attach                     Attach to debuggee process.

  Attach mode attaches the remote debug console to the debuggee process.

  'rdbg -A'           tries to connect via UNIX domain socket.
                      If there are multiple processes are waiting for the
                      debugger connection, list possible debuggee names.
  'rdbg -A path'      tries to connect via UNIX domain socket with given path name.
  'rdbg -A port'      tries to connect to localhost:port via TCP/IP.
  'rdbg -A host port' tries to connect to host:port via TCP/IP.

Other options:
    -h, --help                       Print help
        --util=NAME                  Utility mode (used by tools)
        --stop-at-load               Stop immediately when the debugging feature is loaded.

NOTE
  All messages communicated between a debugger and a debuggee are *NOT* encrypted.
  Please use the remote debugging feature carefully.

```

# Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ruby/debug.
This debugger is not mature so your feedback will help us.

Please also check the [contributing guideline](/CONTRIBUTING.md).

# Acknowledgement

* Some tests are based on [deivid-rodriguez/byebug: Debugging in Ruby 2](https://github.com/deivid-rodriguez/byebug)
* Several codes in `server_cdp.rb` are based on [geoffreylitt/ladybug: Visual Debugger](https://github.com/geoffreylitt/ladybug)
