require "test/unit/warning"

require 'test/unit/testcase'
require 'test/unit/autorunner'

module Test # :nodoc:
  #
  # # Test::Unit - Ruby Unit Testing Framework
  #
  # ## Introduction
  #
  # Unit testing is making waves all over the place, largely due to the
  # fact that it is a core practice of XP. While XP is great, unit testing
  # has been around for a long time and has always been a good idea. One
  # of the keys to good unit testing, though, is not just writing tests,
  # but having tests. What's the difference? Well, if you just _write_ a
  # test and throw it away, you have no guarantee that something won't
  # change later which breaks your code. If, on the other hand, you _have_
  # tests (obviously you have to write them first), and run them as often
  # as possible, you slowly build up a wall of things that cannot break
  # without you immediately knowing about it. This is when unit testing
  # hits its peak usefulness.
  #
  # Enter Test::Unit, a framework for unit testing in Ruby, helping you to
  # design, debug and evaluate your code by making it easy to write and
  # have tests for it.
  #
  #
  # ## Notes
  #
  # Test::Unit has grown out of and superceded Lapidary.
  #
  #
  # ## Feedback
  #
  # I like (and do my best to practice) XP, so I value early releases,
  # user feedback, and clean, simple, expressive code. There is always
  # room for improvement in everything I do, and Test::Unit is no
  # exception. Please, let me know what you think of Test::Unit as it
  # stands, and what you'd like to see expanded/changed/improved/etc. If
  # you find a bug, let me know ASAP; one good way to let me know what the
  # bug is is to submit a new test that catches it :-) Also, I'd love to
  # hear about any successes you have with Test::Unit, and any
  # documentation you might add will be greatly appreciated. My contact
  # info is below.
  #
  #
  # ## Contact Information
  #
  #   * [GitHub issues on
  #     test-unit/test-unit](https://github.com/test-unit/test-unit/issues):
  #     If you have any issues, please report them to here.
  #
  #   * [GitHub pull requests on
  #     test-unit/test-unit](https://github.com/test-unit/test-unit/pulls):
  #     If you have any patches, please report them to here.
  #
  #   * [ruby-talk mailing
  #     list](https://www.ruby-lang.org/en/community/mailing-lists/):
  #     If you have any questions, you can ask them here.
  #
  #
  # ## Credits
  #
  # I'd like to thank...
  #
  # Matz, for a great language!
  #
  # Masaki Suketa, for his work on RubyUnit, which filled a vital need in
  # the Ruby world for a very long time. I'm also grateful for his help in
  # polishing Test::Unit and getting the RubyUnit compatibility layer
  # right. His graciousness in allowing Test::Unit to supercede RubyUnit
  # continues to be a challenge to me to be more willing to defer my own
  # rights.
  #
  # Ken McKinlay, for his interest and work on unit testing, and for his
  # willingness to dialog about it. He was also a great help in pointing
  # out some of the holes in the RubyUnit compatibility layer.
  #
  # Dave Thomas, for the original idea that led to the extremely simple
  # "require 'test/unit'", plus his code to improve it even more by
  # allowing the selection of tests from the command-line. Also, without
  # RDoc, the documentation for Test::Unit would stink a lot more than it
  # does now.
  #
  # Everyone who's helped out with bug reports, feature ideas,
  # encouragement to continue, etc. It's a real privilege to be a part of
  # the Ruby community.
  #
  # The guys at RoleModel Software, for putting up with me repeating, "But
  # this would be so much easier in Ruby!" whenever we're coding in Java.
  #
  # My Creator, for giving me life, and giving it more abundantly.
  #
  #
  # ## License
  #
  # Test::Unit is copyright (c) 2000-2003 Nathaniel Talbott. It is free
  # software, and is distributed under the Ruby license. See the COPYING
  # file.
  #
  # Exception: lib/test/unit/diff.rb is copyright (c)
  # 2008-2010 Kouhei Sutou and 2001-2008 Python Software
  # Foundation. It is free software, and is distributed
  # under the Ruby license and/or the PSF license. See the
  # COPYING file and PSFL file.
  #
  # ## Warranty
  #
  # This software is provided "as is" and without any express or
  # implied warranties, including, without limitation, the implied
  # warranties of merchantibility and fitness for a particular
  # purpose.
  #
  #
  # ## Author
  #
  # Nathaniel Talbott.
  # Copyright (c) 2000-2003, Nathaniel Talbott
  #
  # ----
  #
  # # Usage
  #
  # The general idea behind unit testing is that you write a _test_
  # _method_ that makes certain _assertions_ about your code, working
  # against a _test_ _fixture_. A bunch of these _test_ _methods_ are
  # bundled up into a _test_ _suite_ and can be run any time the
  # developer wants. The results of a run are gathered in a _test_
  # _result_ and displayed to the user through some UI. So, lets break
  # this down and see how Test::Unit provides each of these necessary
  # pieces.
  #
  #
  # ## Assertions
  #
  # These are the heart of the framework. Think of an assertion as a
  # statement of expected outcome, i.e. "I assert that x should be equal
  # to y". If, when the assertion is executed, it turns out to be
  # correct, nothing happens, and life is good. If, on the other hand,
  # your assertion turns out to be false, an error is propagated with
  # pertinent information so that you can go back and make your
  # assertion succeed, and, once again, life is good. For an explanation
  # of the current assertions, see Test::Unit::Assertions.
  #
  #
  # ## Test Method & Test Fixture
  #
  # Obviously, these assertions have to be called within a context that
  # knows about them and can do something meaningful with their
  # pass/fail value. Also, it's handy to collect a bunch of related
  # tests, each test represented by a method, into a common test class
  # that knows how to run them. The tests will be in a separate class
  # from the code they're testing for a couple of reasons. First of all,
  # it allows your code to stay uncluttered with test code, making it
  # easier to maintain. Second, it allows the tests to be stripped out
  # for deployment, since they're really there for you, the developer,
  # and your users don't need them. Third, and most importantly, it
  # allows you to set up a common test fixture for your tests to run
  # against.
  #
  # What's a test fixture? Well, tests do not live in a vacuum; rather,
  # they're run against the code they are testing. Often, a collection
  # of tests will run against a common set of data, also called a
  # fixture. If they're all bundled into the same test class, they can
  # all share the setting up and tearing down of that data, eliminating
  # unnecessary duplication and making it much easier to add related
  # tests.
  #
  # Test::Unit::TestCase wraps up a collection of test methods together
  # and allows you to easily set up and tear down the same test fixture
  # for each test. This is done by overriding #setup and/or #teardown,
  # which will be called before and after each test method that is
  # run. The TestCase also knows how to collect the results of your
  # assertions into a Test::Unit::TestResult, which can then be reported
  # back to you... but I'm getting ahead of myself. To write a test,
  # follow these steps:
  #
  # * Make sure Test::Unit is in your library path.
  # * require 'test/unit' in your test script.
  # * Create a class that subclasses Test::Unit::TestCase.
  # * Add a method that begins with "test" to your class.
  # * Make assertions in your test method.
  # * Optionally define #setup and/or #teardown to set up and/or tear
  #   down your common test fixture.
  # * You can now run your test as you would any other Ruby
  #   script... try it and see!
  #
  # A really simple test might look like this (#setup and #teardown are
  # commented out to indicate that they are completely optional):
  #
  #     require 'test/unit'
  #     
  #     class MyTest < Test::Unit::TestCase
  #       # def setup
  #       # end
  #     
  #       # def teardown
  #       # end
  #     
  #       def test_fail
  #         assert(false, 'Assertion was false.')
  #       end
  #     end
  #
  #
  # ## Test Runners
  #
  # So, now you have this great test class, but you still
  # need a way to run it and view any failures that occur
  # during the run. There are some test runner; console test
  # runner, GTK+ test runner and so on. The console test
  # runner is automatically invoked for you if you require
  # 'test/unit' and simply run the file. To use another
  # runner simply set default test runner ID to
  # Test::Unit::AutoRunner:
  #
  #     require 'test/unit'
  #     Test::Unit::AutoRunner.default_runner = "gtk2"
  #
  # ## Test Suite
  #
  # As more and more unit tests accumulate for a given project, it
  # becomes a real drag running them one at a time, and it also
  # introduces the potential to overlook a failing test because you
  # forget to run it. Suddenly it becomes very handy that the
  # TestRunners can take any object that returns a Test::Unit::TestSuite
  # in response to a suite method. The TestSuite can, in turn, contain
  # other TestSuites or individual tests (typically created by a
  # TestCase). In other words, you can easily wrap up a group of
  # TestCases and TestSuites.
  #
  # Test::Unit does a little bit more for you, by wrapping
  # these up automatically when you require
  # 'test/unit'. What does this mean? It means you could
  # write the above test case like this instead:
  #
  #     require 'test/unit'
  #     require 'test_myfirsttests'
  #     require 'test_moretestsbyme'
  #     require 'test_anothersetoftests'
  #
  # Test::Unit is smart enough to find all the test cases existing in
  # the ObjectSpace and wrap them up into a suite for you. It then runs
  # the dynamic suite using the console TestRunner.
  #
  #
  # ## Configuration file
  #
  # Test::Unit reads 'test-unit.yml' in the current working
  # directory as Test::Unit's configuration file. It can
  # contain the following configurations:
  #
  # * color scheme definitions
  # * test runner to be used
  # * test runner options
  # * test collector to be used
  #
  # Except color scheme definitions, all of them are
  # specified by command line option.
  #
  # Here are sample color scheme definitions:
  #
  #     color_schemes:
  #       inverted:
  #         success:
  #           name: red
  #           bold: true
  #         failure:
  #           name: green
  #           bold: true
  #       other_scheme:
  #         ...
  #
  # Here are the syntax of color scheme definitions:
  #
  #     color_schemes:
  #       SCHEME_NAME:
  #         EVENT_NAME:
  #           name: COLOR_NAME
  #           intensity: BOOLEAN
  #           bold: BOOLEAN
  #           italic: BOOLEAN
  #           underline: BOOLEAN
  #         ...
  #       ...
  #
  # SCHEME_NAME
  # : the name of the color scheme
  #
  # EVENT_NAME
  # : one of [success, failure, pending, omission, notification, error]
  #
  # COLOR_NAME
  # : one of [black, red, green, yellow, blue, magenta, cyan, white]
  #
  # BOOLEAN
  # : true or false
  #
  # You can use the above 'inverted' color scheme with the
  # following configuration:
  #
  #     runner: console
  #     console_options:
  #       color_scheme: inverted
  #     color_schemes:
  #       inverted:
  #         success:
  #           name: red
  #           bold: true
  #         failure:
  #           name: green
  #           bold: true
  #
  # ## Questions?
  #
  # I'd really like to get feedback from all levels of Ruby
  # practitioners about typos, grammatical errors, unclear statements,
  # missing points, etc., in this document (or any other).
  #

  module Unit
    class << self
      # Set true when Test::Unit has run.  If set to true Test::Unit
      # will not automatically run at exit.
      #
      # @deprecated Use {Test::Unit::AutoRunner.need_auto_run=} instead.
      def run=(have_run)
        AutoRunner.need_auto_run = (not have_run)
      end

      # Already tests have run?
      #
      # @deprecated Use {Test::Unit::AutoRunner.need_auto_run?} instead.
      def run?
        not AutoRunner.need_auto_run?
      end

      # @api private
      @@at_start_hooks = []

      # Register a hook that is run before running tests.
      # To register multiple hooks, call this method multiple times.
      #
      # Here is an example test case:
      #
      #     Test::Unit.at_start do
      #       # ...
      #     end
      #
      #     class TestMyClass1 < Test::Unit::TestCase
      #       class << self
      #         def startup
      #           # ...
      #         end
      #       end
      #
      #       def setup
      #         # ...
      #       end
      #
      #       def test_my_class1
      #         # ...
      #       end
      #
      #       def test_my_class2
      #         # ...
      #       end
      #     end
      #
      #     class TestMyClass2 < Test::Unit::TestCase
      #       class << self
      #         def startup
      #           # ...
      #         end
      #       end
      #
      #       def setup
      #         # ...
      #       end
      #
      #       def test_my_class1
      #         # ...
      #       end
      #
      #       def test_my_class2
      #         # ...
      #       end
      #     end
      #
      # Here is a call order:
      #
      # * at_start
      # * TestMyClass1.startup
      # * TestMyClass1#setup
      # * TestMyClass1#test_my_class1
      # * TestMyClass1#setup
      # * TestMyClass1#test_my_class2
      # * TestMyClass2#setup
      # * TestMyClass2#test_my_class1
      # * TestMyClass2#setup
      # * TestMyClass2#test_my_class2
      #
      # @example
      #   Test::Unit.at_start do
      #     puts "Start!"
      #   end
      #
      # @yield A block that is run before running tests.
      # @yieldreturn [void]
      # @return [void]
      #
      # @since 2.5.2
      def at_start(&hook)
        @@at_start_hooks << hook
      end

      # @api private
      def run_at_start_hooks
        @@at_start_hooks.each do |hook|
          hook.call
        end
      end

      # @api private
      @@at_exit_hooks = []

      # Register a hook that is run after running tests.
      # To register multiple hooks, call this method multiple times.
      #
      # Here is an example test case:
      #
      #     Test::Unit.at_exit do
      #       # ...
      #     end
      #
      #     class TestMyClass1 < Test::Unit::TestCase
      #       class << self
      #         def shutdown
      #           # ...
      #         end
      #       end
      #
      #       def teardown
      #         # ...
      #       end
      #
      #       def test_my_class1
      #         # ...
      #       end
      #
      #       def test_my_class2
      #         # ...
      #       end
      #     end
      #
      #     class TestMyClass2 < Test::Unit::TestCase
      #       class << self
      #         def shutdown
      #           # ...
      #         end
      #       end
      #
      #       def teardown
      #         # ...
      #       end
      #
      #       def test_my_class1
      #         # ...
      #       end
      #
      #       def test_my_class2
      #         # ...
      #       end
      #     end
      #
      # Here is a call order:
      #
      # * TestMyClass1#test_my_class1
      # * TestMyClass1#teardown
      # * TestMyClass1#test_my_class2
      # * TestMyClass1#teardown
      # * TestMyClass1.shutdown
      # * TestMyClass2#test_my_class1
      # * TestMyClass2#teardown
      # * TestMyClass2#test_my_class2
      # * TestMyClass2#teardown
      # * TestMyClass2.shutdown
      # * at_exit
      #
      # @example
      #   Test::Unit.at_exit do
      #     puts "Exit!"
      #   end
      #
      # @yield A block that is run after running tests.
      # @yieldreturn [void]
      # @return [void]
      #
      # @since 2.5.2
      def at_exit(&hook)
        @@at_exit_hooks << hook
      end

      # @api private
      def run_at_exit_hooks
        @@at_exit_hooks.each do |hook|
          hook.call
        end
      end
    end
  end
end

Module.new do
  at_exit do
    if $!.nil? and Test::Unit::AutoRunner.need_auto_run?
      exit Test::Unit::AutoRunner.run
    end
  end
end
