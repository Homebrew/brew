#--
#
# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

module Test
  module Unit
    module UI

      # Provides some utilities common to most, if not all,
      # TestRunners.
      #
      #--
      #
      # Perhaps there ought to be a TestRunner superclass? There
      # seems to be a decent amount of shared code between test
      # runners.

      module TestRunnerUtilities

        # Creates a new TestRunner and runs the suite.
        def run(suite, options={})
          return new(suite, options).start
        end

        # Takes care of the ARGV parsing and suite
        # determination necessary for running one of the
        # TestRunners from the command line.
        def start_command_line_test
          if ARGV.empty?
            puts "You should supply the name of a test suite file to the runner"
            exit
          end
          require ARGV[0].gsub(/.+::/, '')
          new(eval(ARGV[0])).start
        end
      end
    end
  end
end
