require "English"
require "optparse"

require "test/unit/color-scheme"
require "test/unit/priority"
require "test/unit/attribute-matcher"
require "test/unit/testcase"

module Test
  module Unit
    class AutoRunner
      RUNNERS = {}
      COLLECTORS = {}
      ADDITIONAL_OPTIONS = []
      PREPARE_HOOKS = []

      class << self
        def register_runner(id, runner_builder=nil, &block)
          runner_builder ||= Proc.new(&block)
          RUNNERS[id] = runner_builder
          RUNNERS[id.to_s] = runner_builder
        end

        def runner(id)
          RUNNERS[id.to_s]
        end

        @@default_runner = nil
        def default_runner
          runner(@@default_runner)
        end

        def default_runner=(id)
          @@default_runner = id
        end

        def register_collector(id, collector_builder=nil, &block)
          collector_builder ||= Proc.new(&block)
          COLLECTORS[id] = collector_builder
          COLLECTORS[id.to_s] = collector_builder
        end

        def collector(id)
          COLLECTORS[id.to_s]
        end

        def register_color_scheme(id, scheme)
          ColorScheme[id] = scheme
        end

        def setup_option(option_builder=nil, &block)
          option_builder ||= Proc.new(&block)
          ADDITIONAL_OPTIONS << option_builder
        end

        def prepare(hook=nil, &block)
          hook ||= Proc.new(&block)
          PREPARE_HOOKS << hook
        end

        def run(force_standalone=false, default_dir=nil, argv=ARGV, &block)
          r = new(force_standalone || standalone?, &block)
          r.base = default_dir
          r.prepare
          r.process_args(argv)
          r.run
        end

        def standalone?
          return false unless("-e" == $0)
          ObjectSpace.each_object(Class) do |klass|
            return false if(klass < TestCase)
          end
          true
        end

        @@need_auto_run = true
        def need_auto_run?
          @@need_auto_run
        end

        def need_auto_run=(need)
          @@need_auto_run = need
        end
      end

      register_collector(:descendant) do |auto_runner|
        require "test/unit/collector/descendant"
        collector = Collector::Descendant.new
        collector.filter = auto_runner.filters
        collector.collect($0.sub(/\.rb\Z/, ""))
      end

      register_collector(:load) do |auto_runner|
        require "test/unit/collector/load"
        collector = Collector::Load.new
        unless auto_runner.pattern.empty?
          collector.patterns.replace(auto_runner.pattern)
        end
        unless auto_runner.exclude.empty?
          collector.excludes.replace(auto_runner.exclude)
        end
        collector.base = auto_runner.base
        collector.default_test_paths = auto_runner.default_test_paths
        collector.filter = auto_runner.filters
        collector.collect(*auto_runner.to_run)
      end

      # JUST TEST!
      # register_collector(:xml) do |auto_runner|
      #   require "test/unit/collector/xml"
      #   collector = Collector::XML.new
      #   collector.filter = auto_runner.filters
      #   collector.collect(auto_runner.to_run[0])
      # end

      # deprecated
      register_collector(:object_space) do |auto_runner|
        require "test/unit/collector/objectspace"
        c = Collector::ObjectSpace.new
        c.filter = auto_runner.filters
        c.collect($0.sub(/\.rb\Z/, ""))
      end

      # deprecated
      register_collector(:dir) do |auto_runner|
        require "test/unit/collector/dir"
        c = Collector::Dir.new
        c.filter = auto_runner.filters
        unless auto_runner.pattern.empty?
          c.pattern.replace(auto_runner.pattern)
        end
        unless auto_runner.exclude.empty?
          c.exclude.replace(auto_runner.exclude)
        end
        c.base = auto_runner.base
        $:.push(auto_runner.base) if auto_runner.base
        c.collect(*(auto_runner.to_run.empty? ? ["."] : auto_runner.to_run))
      end

      attr_reader :suite, :runner_options
      attr_accessor :filters, :to_run
      attr_accessor :default_test_paths
      attr_accessor :pattern, :exclude, :base, :workdir
      attr_accessor :color_scheme, :listeners
      attr_writer :stop_on_failure
      attr_writer :debug_on_failure
      attr_writer :runner, :collector

      def initialize(standalone)
        @standalone = standalone
        @runner = default_runner
        @collector = default_collector
        @filters = []
        @to_run = []
        @default_test_paths = []
        @color_scheme = ColorScheme.default
        @runner_options = {}
        @default_arguments = []
        @workdir = nil
        @listeners = []
        @stop_on_failure = false
        @debug_on_failure = false
        config_file = "test-unit.yml"
        if File.exist?(config_file)
          load_config(config_file)
        else
          load_global_config
        end
        yield(self) if block_given?
      end

      def stop_on_failure?
        @stop_on_failure
      end

      def debug_on_failure?
        @debug_on_failure
      end

      def prepare
        PREPARE_HOOKS.each do |handler|
          handler.call(self)
        end
      end

      def process_args(args=ARGV)
        begin
          args.unshift(*@default_arguments)
          options.order!(args) {|arg| add_test_path(arg)}
        rescue OptionParser::ParseError => e
          puts e
          puts options
          exit(false)
        end
        not @to_run.empty?
      end

      def options
        @options ||= OptionParser.new do |o|
          o.banner = "Test::Unit automatic runner."
          o.banner += "\nUsage: #{$0} [options] [-- untouched arguments]"

          o.on("-r", "--runner=RUNNER", RUNNERS,
               "Use the given RUNNER.",
               "(" + keyword_display(RUNNERS) + ")") do |r|
            @runner = r
          end

          o.on("--collector=COLLECTOR", COLLECTORS,
               "Use the given COLLECTOR.",
               "(" + keyword_display(COLLECTORS) + ")") do |collector|
            @collector = collector
          end

          if (@standalone)
            o.on("-b", "--basedir=DIR", "Base directory of test suites.") do |b|
              @base = b
            end

            o.on("-w", "--workdir=DIR", "Working directory to run tests.") do |w|
              @workdir = w
            end

            o.on("--default-test-path=PATH",
                 "Add PATH to the default test paths.",
                 "The PATH is used when user doesn't specify any test path.",
                 "You can specify this option multiple times.") do |path|
              @default_test_paths << path
            end

            o.on("-a", "--add=TORUN", Array,
                 "Add TORUN to the list of things to run;",
                 "can be a file or a directory.") do |paths|
              paths.each do |path|
                add_test_path(path)
              end
            end

            @pattern = []
            o.on("-p", "--pattern=PATTERN", Regexp,
                 "Match files to collect against PATTERN.") do |e|
              @pattern << e
            end

            @exclude = []
            o.on("-x", "--exclude=PATTERN", Regexp,
                 "Ignore files to collect against PATTERN.") do |e|
              @exclude << e
            end
          end

          o.on("-n", "--name=NAME", String,
               "Runs tests matching NAME.",
               "Use '/PATTERN/' for NAME to use regular expression.",
               "Regular expression accepts options.",
               "Example: '/taRget/i' matches 'target' and 'TARGET'") do |name|
            name = prepare_name(name)
            @filters << lambda do |test|
              match_test_name(test, name)
            end
          end

          o.on("--ignore-name=NAME", String,
               "Ignores tests matching NAME.",
               "Use '/PATTERN/' for NAME to use regular expression.",
               "Regular expression accepts options.",
               "Example: '/taRget/i' matches 'target' and 'TARGET'") do |name|
            name = prepare_name(name)
            @filters << lambda do |test|
              not match_test_name(test, name)
            end
          end

          o.on("-t", "--testcase=TESTCASE", String,
               "Runs tests in TestCases matching TESTCASE.",
               "Use '/PATTERN/' for TESTCASE to use regular expression.",
               "Regular expression accepts options.",
               "Example: '/taRget/i' matches 'target' and 'TARGET'") do |name|
            name = prepare_name(name)
            @filters << lambda do |test|
              match_test_case_name(test, name)
            end
          end

          o.on("--ignore-testcase=TESTCASE", String,
               "Ignores tests in TestCases matching TESTCASE.",
               "Use '/PATTERN/' for TESTCASE to use regular expression.",
               "Regular expression accepts options.",
               "Example: '/taRget/i' matches 'target' and 'TARGET'") do |name|
            name = prepare_name(name)
            @filters << lambda do |test|
              not match_test_case_name(test, name)
            end
          end

          o.on("--location=LOCATION", String,
               "Runs tests that defined in LOCATION.",
               "LOCATION is one of PATH:LINE, PATH or LINE.") do |location|
            case location
            when /\A(\d+)\z/
              path = nil
              line = $1.to_i
            when /:(\d+)\z/
              path = $PREMATCH
              line = $1.to_i
            else
              path = location
              line = nil
            end
            add_location_filter(path, line)
          end

          o.on("--attribute=EXPRESSION", String,
               "Runs tests that matches EXPRESSION.",
               "EXPRESSION is evaluated as Ruby's expression.",
               "Test attribute name can be used with no receiver in EXPRESSION.",
               "EXPRESSION examples:",
               "  !slow",
               "  tag == 'important' and !slow") do |expression|
            @filters << lambda do |test|
              matcher = AttributeMatcher.new(test)
              matcher.match?(expression)
            end
          end

          priority_filter = Proc.new do |test|
            if @filters == [priority_filter]
              Priority::Checker.new(test).need_to_run?
            else
              nil
            end
          end
          o.on("--[no-]priority-mode",
               "Runs some tests based on their priority.") do |priority_mode|
            if priority_mode
              Priority.enable
              @filters |= [priority_filter]
            else
              Priority.disable
              @filters -= [priority_filter]
            end
          end

          o.on("--default-priority=PRIORITY",
               Priority.available_values,
               "Uses PRIORITY as default priority",
               "(#{keyword_display(Priority.available_values)})") do |priority|
            Priority.default = priority
          end

          o.on("-I", "--load-path=DIR[#{File::PATH_SEPARATOR}DIR...]",
               "Appends directory list to $LOAD_PATH.") do |dirs|
            $LOAD_PATH.concat(dirs.split(File::PATH_SEPARATOR))
          end

          color_schemes = ColorScheme.all
          o.on("--color-scheme=SCHEME", color_schemes,
               "Use SCHEME as color scheme.",
               "(#{keyword_display(color_schemes)})") do |scheme|
            @color_scheme = scheme
          end

          o.on("--config=FILE",
               "Use YAML format FILE content as configuration file.") do |file|
            load_config(file)
          end

          o.on("--order=ORDER", TestCase::AVAILABLE_ORDERS,
               "Run tests in a test case in ORDER order.",
               "(#{keyword_display(TestCase::AVAILABLE_ORDERS)})") do |order|
            TestCase.test_order = order
          end

          assertion_message_class = Test::Unit::Assertions::AssertionMessage
          o.on("--max-diff-target-string-size=SIZE", Integer,
               "Shows diff if both expected result string size and " +
               "actual result string size are " +
               "less than or equal SIZE in bytes.",
               "(#{assertion_message_class.max_diff_target_string_size})") do |size|
            assertion_message_class.max_diff_target_string_size = size
          end

          o.on("--[no-]stop-on-failure",
               "Stops immediately on the first non success test",
               "(#{@stop_on_failure})") do |boolean|
            @stop_on_failure = boolean
          end

          o.on("--[no-]debug-on-failure",
               "Run debugger if available on failure",
               "(#{AssertionFailedError.debug_on_failure?})") do |boolean|
            AssertionFailedError.debug_on_failure = boolean
          end

          ADDITIONAL_OPTIONS.each do |option_builder|
            option_builder.call(self, o)
          end

          o.on("--",
               "Stop processing options so that the",
               "remaining options will be passed to the",
               "test."){o.terminate}

          o.on("-h", "--help", "Display this help."){puts o; exit}

          o.on_tail
          o.on_tail("Deprecated options:")

          o.on_tail("--console", "Console runner (use --runner).") do
            warn("Deprecated option (--console).")
            @runner = self.class.runner(:console)
          end

          if RUNNERS[:fox]
            o.on_tail("--fox", "Fox runner (use --runner).") do
              warn("Deprecated option (--fox).")
              @runner = self.class.runner(:fox)
            end
          end

          o.on_tail
        end
      end

      def keyword_display(keywords)
        keywords = keywords.collect do |keyword, _|
          keyword.to_s
        end.uniq.sort

        i = 0
        keywords.collect do |keyword|
          if (i > 0 and keyword[0] == keywords[i - 1][0]) or
              ((i < keywords.size - 1) and (keyword[0] == keywords[i + 1][0]))
            n = 2
          else
            n = 1
          end
          i += 1
          keyword.sub(/^(.{#{n}})([A-Za-z]+)(?=\w*$)/, '\\1[\\2]')
        end.join(", ")
      end

      def run
        self.class.need_auto_run = false
        suite = @collector[self]
        return false if suite.nil?
        return true if suite.empty?
        runner = @runner[self]
        return false if runner.nil?
        @runner_options[:color_scheme] ||= @color_scheme
        @runner_options[:listeners] ||= []
        @runner_options[:listeners].concat(@listeners)
        if @stop_on_failure
          @runner_options[:listeners] << StopOnFailureListener.new
        end
        change_work_directory do
          runner.run(suite, @runner_options).passed?
        end
      end

      def load_config(file)
        require "yaml"
        config = YAML.load(File.read(file))
        runner_name = config["runner"]
        @runner = self.class.runner(runner_name) || @runner
        @collector = self.class.collector(config["collector"]) || @collector
        (config["color_schemes"] || {}).each do |name, options|
          ColorScheme[name] = options
        end
        runner_options = {}
        (config["#{runner_name}_options"] || {}).each do |key, value|
          key = key.to_sym
          value = ColorScheme[value] if key == :color_scheme
          if key == :arguments
            @default_arguments.concat(value.split)
          else
            runner_options[key] = value
          end
        end
        @runner_options = @runner_options.merge(runner_options)
      end

      private
      def default_runner
        runner = self.class.default_runner
        if ENV["EMACS"] == "t"
          runner ||= self.class.runner(:emacs)
        else
          runner ||= self.class.runner(:console)
        end
        runner
      end

      def default_collector
        self.class.collector(@standalone ? :load : :descendant)
      end

      def global_config_file
        File.expand_path("~/.test-unit.yml")
      rescue ArgumentError
        nil
      end

      def load_global_config
        file = global_config_file
        load_config(file) if file and File.exist?(file)
      end

      def change_work_directory(&block)
        if @workdir
          Dir.chdir(@workdir, &block)
        else
          yield
        end
      end

      def prepare_name(name)
        case name
        when /\A\/(.*)\/([imx]*)\z/
          pattern = $1
          options_raw = $2
          options = 0
          options |= Regexp::IGNORECASE if options_raw.include?("i")
          options |= Regexp::MULTILINE if options_raw.include?("m")
          options |= Regexp::EXTENDED if options_raw.include?("x")
          Regexp.new(pattern, options)
        else
          name
        end
      end

      def match_test_name(test, pattern)
        return true if pattern === test.method_name
        return true if pattern === test.local_name
        if pattern.is_a?(String)
          return true if pattern === "#{test.class}##{test.method_name}"
          return true if pattern === "#{test.class}##{test.local_name}"
        end
        false
      end

      def match_test_case_name(test, pattern)
        test.class.ancestors.each do |test_class|
          break if test_class == TestCase
          return true if pattern === test_class.name
        end
        false
      end

      def add_test_path(path)
        if /:(\d+)\z/ =~ path
          line = $1.to_i
          path = $PREMATCH
          add_location_filter(path, line)
        end
        @to_run << path
      end

      def add_location_filter(path, line)
        @filters << lambda do |test|
          test.class.test_defined?(:path => path,
                                   :line => line,
                                   :method_name => test.method_name)
        end
      end

      class StopOnFailureListener
        def attach_to_mediator(mediator)
          mediator.add_listener(TestResult::FINISHED) do |result|
            result.stop unless result.passed?
          end
        end
      end
    end
  end
end

require "test/unit/runner/console"
require "test/unit/runner/emacs"
require "test/unit/runner/xml"
