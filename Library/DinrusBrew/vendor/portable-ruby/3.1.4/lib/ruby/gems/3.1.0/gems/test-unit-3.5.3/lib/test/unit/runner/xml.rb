module Test
  module Unit
    AutoRunner.register_runner(:xml) do |auto_runner|
      require 'test/unit/ui/xml/testrunner'
      Test::Unit::UI::XML::TestRunner
    end

    AutoRunner.setup_option do |auto_runner, opts|
      opts.on("--output-file-descriptor=FD", Integer,
              "Outputs to file descriptor FD") do |fd|
        auto_runner.runner_options[:output_file_descriptor] = fd
      end
    end
  end
end
