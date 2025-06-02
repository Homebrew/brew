## Set Up a Development Environment

1. `$ git clone git@github.com:ruby/debug.git`
2. `$ bundle install`
3. `$ rake` - this will
    - Compile the C extension locally (which can also be done solely with `rake compile`).
    - Run tests.
    - Re-generate `README.md`.

If you spot any problem, please open an issue.

## Run Tests

### Run all tests

```bash
$ rake test_all
```

### Run all console tests

```bash
$ rake test_console
```

### Run all protocol (DAP & CDP) tests

```bash
$ rake test_protocol
```

### Run specific test(s)


```bash
$ ruby test/console/break_test.rb # run all tests in the specified file
$ ruby test/console/break_test.rb -h # to see all the test options
```

## Generate Tests

There is a test generator in `debug.rb` project to make it easier to write tests.

### Quickstart

This section shows you how to create test file by test generator. For more advanced information on creating tests, please take a look at [gentest options](#gentest-options). (You can also check by `$bin/gentest -h`)

#### 1. Create a target file for debuggee.

Let's say, we created `target.rb` which is located in top level directory of debugger.

```ruby
module Foo
  class Bar
    def self.a
      "hello"
    end
  end
  Bar.a
  bar = Bar.new
end
```

#### 2. Run `gentest` as shown in the example below.

```shell
$ bin/gentest target.rb
```

#### 3. Debugger will be executed. You can type any debug commands.

```shell
$ bin/gentest target.rb
DEBUGGER: Session start (pid: 11139)
[1, 9] in ~/workspace/debug/target.rb
=>   1| module Foo
     2|   class Bar
     3|     def self.a
     4|       "hello"
     5|     end
     6|   end
     7|   Bar.a
     8|   bar = Bar.new
     9| end
=>#0	<main> at ~/workspace/debug/target.rb:1
INTERNAL_INFO: {"location":"~/workspace/debug/target.rb:1","line":1}
(rdbg)s
 s
[1, 9] in ~/workspace/debug/target.rb
     1| module Foo
=>   2|   class Bar
     3|     def self.a
     4|       "hello"
     5|     end
     6|   end
     7|   Bar.a
     8|   bar = Bar.new
     9| end
=>#0	<module:Foo> at ~/workspace/debug/target.rb:2
  #1	<main> at ~/workspace/debug/target.rb:1
INTERNAL_INFO: {"location":"~/workspace/debug/target.rb:2","line":2}
(rdbg)n
 n
[1, 9] in ~/workspace/debug/target.rb
     1| module Foo
     2|   class Bar
=>   3|     def self.a
     4|       "hello"
     5|     end
     6|   end
     7|   Bar.a
     8|   bar = Bar.new
     9| end
=>#0	<class:Bar> at ~/workspace/debug/target.rb:3
  #1	<module:Foo> at ~/workspace/debug/target.rb:2
  # and 1 frames (use `bt' command for all frames)
INTERNAL_INFO: {"location":"~/workspace/debug/target.rb:3","line":3}
(rdbg)b 7
 b 7
#0  BP - Line  /Users/naotto/workspace/debug/target.rb:7 (line)
INTERNAL_INFO: {"location":"~/workspace/debug/target.rb:3","line":3}
(rdbg)c
 c
[2, 9] in ~/workspace/debug/target.rb
     2|   class Bar
     3|     def self.a
     4|       "hello"
     5|     end
     6|   end
=>   7|   Bar.a
     8|   bar = Bar.new
     9| end
=>#0	<module:Foo> at ~/workspace/debug/target.rb:7
  #1	<main> at ~/workspace/debug/target.rb:1

Stop by #0  BP - Line  /Users/naotto/workspace/debug/target.rb:7 (line)
INTERNAL_INFO: {"location":"~/workspace/debug/target.rb:7","line":7}
(rdbg)q!
 q!
created: /Users/naotto/workspace/debug/test/tool/../debug/foo_test.rb
    class: FooTest
    method: test_1629720194
```

#### 4. The test file will be created as `test/debug/foo_test.rb`.

If the file already exists, **only method** will be added to it.

```ruby
# frozen_string_literal: true

require_relative '../support/test_case'

module DEBUGGER__
  class FooTest < TestCase
    def program
      <<~RUBY
        1| module Foo
        2|   class Bar
        3|     def self.a
        4|       "hello"
        5|     end
        6|   end
        7|   Bar.a
        8|   bar = Bar.new
        9| end
      RUBY
    end
    
    def test_1629720194
      debug_code(program) do
        type 's'
        assert_line_num 2
        assert_line_text([
          /\[1, 9\] in .*/,
          /     1\| module Foo/,
          /=>   2\|   class Bar/,
          /     3\|     def self\.a/,
          /     4\|       "hello"/,
          /     5\|     end/,
          /     6\|   end/,
          /     7\|   Bar\.a/,
          /     8\|   bar = Bar\.new/,
          /     9\| end/,
          /=>\#0\t<module:Foo> at .*/,
          /  \#1\t<main> at .*/
        ])
        type 'n'
        assert_line_num 3
        assert_line_text([
          /\[1, 9\] in .*/,
          /     1\| module Foo/,
          /     2\|   class Bar/,
          /=>   3\|     def self\.a/,
          /     4\|       "hello"/,
          /     5\|     end/,
          /     6\|   end/,
          /     7\|   Bar\.a/,
          /     8\|   bar = Bar\.new/,
          /     9\| end/,
          /=>\#0\t<class:Bar> at .*/,
          /  \#1\t<module:Foo> at .*/,
          /  \# and 1 frames \(use `bt' command for all frames\)/
        ])
        type 'b 7'
        assert_line_text(/\#0  BP \- Line  .*/)
        type 'c'
        assert_line_num 7
        assert_line_text([
          /\[2, 9\] in .*/,
          /     2\|   class Bar/,
          /     3\|     def self\.a/,
          /     4\|       "hello"/,
          /     5\|     end/,
          /     6\|   end/,
          /=>   7\|   Bar\.a/,
          /     8\|   bar = Bar\.new/,
          /     9\| end/,
          /=>\#0\t<module:Foo> at .*/,
          /  \#1\t<main> at .*/,
          //,
          /Stop by \#0  BP \- Line  .*/
        ])
        type 'q!'
      end
    end
  end
end
```

#### gentest options

You can get more information about `gentest` here.

The default method name is `test_#{some integer numbers}`, the class name is `FooTest#{some integer numbers}`, and the file name will be `foo_test.rb`.
The following table shows examples of the gentest options.

| Command | Description | File | Class | Method |
| --- | --- | --- | --- | --- |
| `$ bin/gentest target.rb` | Run without any options | `foo_test.rb` | `FooTest...` | `test_...` |
| `$ bin/gentest target.rb --open=vscode` | Run the debugger with VScode | `foo_test.rb` | `FooTest...` | `test_...` |
| `$ bin/gentest target.rb -c step` | Specify the class name | `step_test.rb` | `StepTest...` | `test_...` |
| `$ bin/gentest target.rb -m test_step` | Specify the method name | `foo_test.rb` | `FooTest...` | `test_step` |
| `$ bin/gentest target.rb -c step -m test_step` | Specify the class name and the method name | `step_test.rb` | `StepTest...` | `test_step` |

### Assertions

- assert_line_num(expected)

Passes if `expected` is equal to the location where debugger stops.

- assert_line_text(text)

Passes if `text` is included in the last debugger log.

- assert_no_line_text(text)

Passes if `text` is not included in the last debugger log.

- assert_debuggee_line_text(text)

Passes if `text` is included in the debuggee log.

### Tests for DAP and CDP

Currently, there are 2 kinds of test frameworks for DAP and CDP.

1. Protocol-based tests

If you want to write protocol-based tests, you should use the test generator.
To run the test generator, you can enter `$ bin/gentest target.rb --open=vscode` in the terminal, VSCode will be executed.
Also, if you enter `$ bin/gentest target.rb --open=chrome` there, Chrome will be executed.
If you need to modify existing tests, it is basically a good idea to regenerate them by the test generator instead of rewriting them directly.
Please refer to [the Microsoft "Debug Adapter Protocol" article](https://microsoft.github.io/debug-adapter-protocol/specification) to learn more about DAP formats.
Please refer to [Procol viewer for "Chrome DevTools Protocol"](https://chromedevtools.github.io/devtools-protocol/) to learn more about CDP formats.

2. High-level tests

High-level tests are designed to test both DAP and CDP for a single method.
You can write tests as follows:
**NOTE:** Use `req_terminate_debuggee` to finish debugging. You can't use any methods such as `req_continue`, `req_next` and so on.

```ruby
require_relative '../support/test_case'
module DEBUGGER__
  class BreakTest < TestCase
    # PROGRAM is the target script.
    PROGRAM = <<~RUBY
      1| module Foo
      2|   class Bar
      3|     def self.a
      4|       "hello"
      5|     end
      6|   end
      7|   Bar.a
      8|   bar = Bar.new
      9| end
    RUBY

    def test_break1
      run_protocol_scenario PROGRAM do # Start debugging with DAP and CDP
        req_add_breakpoint 5 # Set a breakpoint on line 5.
        req_add_breakpoint 8 # Set a breakpoint on line 8.
        req_continue # Resume the program.
        assert_line_num 5 # Check if debugger stops at line 5.
        req_continue # Resume the program.
        assert_line_num 8 # Check if debugger stops at line 8.
        req_terminate_debuggee # Terminate debugging.
      end
    end
  end
end
```

#### API

- run_protocol_scenario program, dap: true, cdp: true, &scenario

Execute debugging `program` with `&scenario`. If you want to test it only for DAP, you can write as follows:

`run_protocol_scenario program, cdp: false ...`

- req_add_breakpoint(lineno, path: temp_file_path, cond: nil)

Sends request to rdbg to add a breakpoint.

- req_delete_breakpoint bpnum

Sends request to rdbg to delete a breakpoint.

- req_set_exception_breakpoints(breakpoints)

Sends request to rdbg to set exception breakpoints. e.g.

```rb
req_set_exception_breakpoints([{ name: "RuntimeError", condition: "a == 1" }])
```

Please note that `setExceptionBreakpoints` resets all exception breakpoints in every request. 

So the following code will only set breakpoint for `Exception`.

```rb
req_set_exception_breakpoints([{ name: "RuntimeError" }])
req_set_exception_breakpoints([{ name: "Exception" }])
```

This means you can also use

```rb
req_set_exception_breakpoints([])
```

to clear all exception breakpoints.

- req_continue

Sends request to rdbg to resume the program.

- req_step

Sends request to rdbg to step into next method.

- req_next

Sends request to rdbg to step over next method.

- req_finish

Sends request to rdbg to step out of current method.

- req_step_back

Sends request to rdbg to step back from current method.

- req_terminate_debuggee

Sends request to rdbg to terminate the debuggee.

- assert_reattach

Passes if reattaching to rdbg is successful.

- assert_hover_result(expected, expression)

Passes if result of `expression` matches `expected`.

`expected` need to be a Hash object as follows:

`assert_hover_result({value: '2', type: 'Integer'}, 'a')`

NOTE: `value` and `type` need to be strings.

- assert_repl_result(expected, expression)

Passes if result of `expression` matches `expected`.

`expected` need to be a Hash object as follows:

`assert_repl_result({value: '2', type: 'Integer'}, 'a')`

NOTE: `value` and `type` need to be strings.

- assert_watch_result(expected, expression)

Passes if result of `expression` matches `expected`.

`expected` need to be a Hash object as follows:

`assert_watch_result({value: '2', type: 'Integer'}, 'a')`

NOTE: `value` and `type` need to be strings.

- assert_line_num(expected)

Passes if `expected` is equal to the location where debugger stops.

- assert_locals_result(expected)

Passes if all of `expected` local variable entries match the ones returned by debugger.

An variable entry looks like this: `{ name: "bar", value: "nil", type: "NilClass" }`.

Please note that both `value` and `type` need to be strings.

- assert_threads_result(expected)

Passes if both conditions are true:

1. The number of expected patterns matches the number of threads.
2. Every pattern matches a thread name. Notice that the order of threads info is not guaranteed.

Example:

```
assert_threads_result(
  [
    /\.rb:\d:in `<main>'/,
    /\.rb:\d:in `block in foo'/
  ]
)
```

## To Update README

This project generates `README.md` from the template `misc/README.md.erb`

So **do not** directly update `README.md`. Instead, you should update the template's source and run

```bash
$ rake
```

to reflect the changes on `README.md`.


### When to re-generate `README.md`

- After updating `misc/README.md.erb`.
- After updating `rdbg` executable's options.
- After updating comments of debugger's commands.

## Manually Test Your Changes

You can manually test your changes with a simple Ruby script + a line of command. The following example will help you check:

- Breakpoint insertion.
- Resume from the breakpoint.
- Backtrace display.
- Information (local variables, ivars..etc.) display.
- Debugger exit.


### Script

```ruby
# target.rb
class Foo
  def first_call
    second_call(20)
  end

  def second_call(num)
    third_call_with_block do |ten|
      forth_call(num, ten)
    end
  end

  def third_call_with_block(&block)
    @ivar1 = 10; @ivar2 = 20

    yield(10)
  end

  def forth_call(num1, num2)
    num1 + num2
  end
end

Foo.new.first_call
```

### Command

```
$ exe/rdbg -e 'b 20;; c ;; bt ;; info ;; q!' -e c target.rb
```

### Expect Result

```
❯ exe/rdbg -e 'b 20;; c ;; bt ;; info ;; q!' -e c target.rb
DEBUGGER: Session start (pid: 9815)
[1, 10] in target.rb
=>    1| class Foo
      2|   def first_call
      3|     second_call(20)
      4|   end
      5|
      6|   def second_call(num)
      7|     third_call_with_block do |ten|
      8|       forth_call(num, ten)
      9|     end
     10|   end
=>#0    <main> at target.rb:1
(rdbg:commands) b 20
#0  BP - Line  /PATH_TO_PROJECT/target.rb:20 (return)
(rdbg:commands) c
[15, 24] in target.rb
     15|     yield(10)
     16|   end
     17|
     18|   def forth_call(num1, num2)
     19|     num1 + num2
=>   20|   end
     21| end
     22|
     23| Foo.new.first_call
     24|
=>#0    Foo#forth_call(num1=20, num2=10) at target.rb:20 #=> 30
  #1    block {|ten=10|} in second_call at target.rb:8
  # and 4 frames (use `bt' command for all frames)

Stop by #0  BP - Line  /PATH_TO_PROJECT/target.rb:20 (return)
(rdbg:commands) bt
=>#0    Foo#forth_call(num1=20, num2=10) at target.rb:20 #=> 30
  #1    block {|ten=10|} in second_call at target.rb:8
  #2    Foo#third_call_with_block(block=#<Proc:0x00007f9283101568 target.rb:7>) at target.rb:15
  #3    Foo#second_call(num=20) at target.rb:7
  #4    Foo#first_call at target.rb:3
  #5    <main> at target.rb:23
(rdbg:commands) info
=>#0    Foo#forth_call(num1=20, num2=10) at target.rb:20 #=> 30
%self => #<Foo:0x00007f92831016d0 @ivar1=10, @ivar2=20>
%return => 30
num1 => 20
num2 => 10
@ivar1 => 10
@ivar2 => 20
(rdbg:commands) q!
```
