module Test
  module Unit
    module Util
      module Output
        ##
        # Returns output for standard output and standard
        # error as string.
        #
        # Example:
        #
        #     capture_output do
        #       puts("stdout")
        #       warn("stderr")
        #     end # -> ["stdout\n", "stderr\n"]
        def capture_output
          require 'stringio'

          output = StringIO.new
          error = StringIO.new
          stdout_save, stderr_save = $stdout, $stderr
          $stdout, $stderr = output, error
          begin
            yield
            [output.string, error.string]
          ensure
            $stdout, $stderr = stdout_save, stderr_save
          end
        end
      end
    end
  end
end
