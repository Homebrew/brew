# frozen_string_literal: true

if ENV["HOMEBREW_TESTS_COVERAGE"]
  require "simplecov"
  require "simplecov-cobertura"

  formatters = [
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::CoberturaFormatter,
  ]
  SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new(formatters)

  # Needed for outputting coverage reporting only once for parallel_tests.
  # Otherwise, "Coverage report generated" will get spammed for each process.
  if ENV["TEST_ENV_NUMBER"]
    SimpleCov.at_exit do
      result = SimpleCov.result
      # `SimpleCov.result` calls `ParallelTests.wait_for_other_processes_to_finish`
      # internally for you on the last process.
      result.format! if ParallelTests.last_process?
    end
  end
end

require_relative "../standalone"
require_relative "../warnings"

Warnings.ignore :parser_syntax do
  require "rubocop"
end

require "rspec/github"
require "rspec/retry"
require "rspec/sorbet"
require "rubocop/rspec/support"
require "find"
require "timeout"

$LOAD_PATH.unshift(File.expand_path("#{ENV.fetch("HOMEBREW_LIBRARY")}/Homebrew/test/support/lib"))

require_relative "support/extend/cachable"

require_relative "../global"

require "debug" if ENV["HOMEBREW_DEBUG"]

require "test/support/quiet_progress_formatter"
require "test/support/helper/cask"
require "test/support/helper/files"
require "test/support/helper/fixtures"
require "test/support/helper/formula"
require "test/support/helper/mktmpdir"

require "test/support/helper/spec/shared_context/homebrew_cask" if OS.mac?
require "test/support/helper/spec/shared_context/integration_test"
require "test/support/helper/spec/shared_examples/formulae_exist"

TEST_DIRECTORIES = [
  CoreTap.instance.path/"Formula",
  HOMEBREW_CACHE,
  HOMEBREW_CACHE_FORMULA,
  HOMEBREW_CACHE/"api",
  HOMEBREW_CELLAR,
  HOMEBREW_LOCKS,
  HOMEBREW_LOGS,
  HOMEBREW_TEMP,
  HOMEBREW_ALIASES,
].freeze

# Make `instance_double` and `class_double`
# work when type-checking is active.
RSpec::Sorbet.allow_doubles!

RSpec.configure do |config|
  config.order = :random

  config.raise_errors_for_deprecations!
  config.warnings = true
  config.disable_monkey_patching!

  config.filter_run_when_matching :focus

  config.silence_filter_announcements = true if ENV["TEST_ENV_NUMBER"]

  # Improve backtrace formatting
  config.filter_gems_from_backtrace "rspec-retry", "sorbet-runtime"
  config.backtrace_exclusion_patterns << %r{test/spec_helper\.rb}

  config.expect_with :rspec do |c|
    c.max_formatted_output_length = 200
  end

  # Use rspec-retry to handle flaky tests.
  config.default_sleep_interval = 1

  # Don't want the nicer default retry behaviour when using CodeCov to
  # identify flaky tests.
  config.default_retry_count = 2 unless ENV["CODECOV_TOKEN"]

  config.expect_with :rspec do |expectations|
    # This option will default to `true` in RSpec 4. It makes the `description`
    # and `failure_message` of custom matchers include text for helper methods
    # defined using `chain`, e.g.:
    #     be_bigger_than(2).and_smaller_than(4).description
    #     # => "be bigger than 2 and smaller than 4"
    # ...rather than:
    #     # => "be bigger than 2"
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |mocks|
    # Prevents you from mocking or stubbing a method that does not exist on
    # a real object. This is generally recommended and will default to
    # `true` in RSpec 4.
    mocks.verify_partial_doubles = true
  end
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Increase timeouts for integration tests (as we expect them to take longer).
  config.around(:each, :integration_test) do |example|
    example.metadata[:timeout] ||= 120
    example.run
  end

  config.around(:each, :needs_network) do |example|
    example.metadata[:timeout] ||= 120

    # Don't want the nicer default retry behaviour when using CodeCov to
    # identify flaky tests.
    example.metadata[:retry] ||= 4 unless ENV["CODECOV_TOKEN"]

    example.metadata[:retry_wait] ||= 2
    example.metadata[:exponential_backoff] ||= true
    example.run
  end

  # Never truncate output objects.
  RSpec::Support::ObjectFormatter.default_instance.max_formatted_output_length = nil

  config.include(RuboCop::RSpec::ExpectOffense)

  config.include(Test::Helper::Cask)
  config.include(Test::Helper::Fixtures)
  config.include(Test::Helper::Formula)
  config.include(Test::Helper::MkTmpDir)

  config.before(:each, :needs_linux) do
    skip "Not running on Linux." unless OS.linux?
  end

  config.before(:each, :needs_macos) do
    skip "Not running on macOS." unless OS.mac?
  end

  config.before(:each, :needs_ci) do
    skip "Not running on CI." unless ENV["CI"]
  end

  config.before(:each, :needs_java) do
    skip "Java is not installed." unless which("java")
  end

  config.before(:each, :needs_python) do
    skip "Python is not installed." if !which("python3") && !which("python")
  end

  config.before(:each, :needs_network) do
    skip "Requires network connection." unless ENV["HOMEBREW_TEST_ONLINE"]
  end

  config.before(:each, :needs_homebrew_core) do
    core_tap_path = "#{ENV.fetch("HOMEBREW_LIBRARY")}/Taps/homebrew/homebrew-core"
    skip "Requires homebrew/core to be tapped." unless Dir.exist?(core_tap_path)
  end

  config.before(:each, :needs_systemd) do
    skip "No SystemD found." unless which("systemctl")
  end

  config.before(:each, :needs_daemon_manager) do
    skip "No LaunchCTL or SystemD found." if !which("systemctl") && !which("launchctl")
  end

  config.before do |example|
    next if example.metadata.key?(:needs_network)
    next if example.metadata.key?(:needs_utils_curl)

    allow(Utils::Curl).to receive(:curl_executable).and_raise(<<~ERROR)
      Unexpected call to Utils::Curl.curl_executable without setting :needs_network or :needs_utils_curl.
    ERROR
  end

  config.before(:each, :no_api) do
    ENV["HOMEBREW_NO_INSTALL_FROM_API"] = "1"
  end

  config.before(:each, :needs_svn) do
    svn_shim = HOMEBREW_SHIMS_PATH/"shared/svn"
    skip "Subversion is not installed." unless quiet_system svn_shim, "--version"

    svn_shim_path = Pathname(Utils.popen_read(svn_shim, "--homebrew=print-path").chomp.presence)
    svn_paths = PATH.new(ENV.fetch("PATH"))
    svn_paths.prepend(svn_shim_path.dirname)

    if OS.mac?
      xcrun_svn = Utils.popen_read("xcrun", "-f", "svn")
      svn_paths.append(File.dirname(xcrun_svn)) if $CHILD_STATUS.success? && xcrun_svn.present?
    end

    svn = which("svn", svn_paths)
    skip "svn is not installed." unless svn

    svnadmin = which("svnadmin", svn_paths)
    skip "svnadmin is not installed." unless svnadmin

    ENV["PATH"] = PATH.new(ENV.fetch("PATH"))
                      .append(svn.dirname)
                      .append(svnadmin.dirname)
  end

  config.before(:each, :needs_homebrew_curl) do
    ENV["HOMEBREW_CURL"] = HOMEBREW_BREWED_CURL_PATH
    skip "A `curl` with TLS 1.3 support is required." unless Utils::Curl.curl_supports_tls13?
  rescue FormulaUnavailableError
    skip "No `curl` formula is available."
  end

  config.before(:each, :needs_unzip) do
    skip "Unzip is not installed." unless which("unzip")
  end

  config.around do |example|
    Homebrew.raise_deprecation_exceptions = true

    Tap.installed.each(&:clear_cache)
    Cachable::Registry.clear_all_caches
    FormulaInstaller.clear_attempted
    FormulaInstaller.clear_installed
    FormulaInstaller.clear_fetched
    Utils::Curl.clear_path_cache

    TEST_DIRECTORIES.each(&:mkpath)

    @__homebrew_failed = Homebrew.failed?

    @__files_before_test = Test::Helper::Files.find_files

    @__env = ENV.to_hash # dup doesn't work on ENV

    @__stdout = $stdout.clone
    @__stderr = $stderr.clone
    @__stdin = $stdin.clone

    # Link original API cache files to test cache directory.
    Pathname("#{ENV.fetch("HOMEBREW_CACHE")}/api").glob("*.json").each do |path|
      FileUtils.ln_s path, HOMEBREW_CACHE/"api/#{path.basename}"
    end

    begin
      if example.metadata.keys.exclude?(:focus) && !ENV.key?("HOMEBREW_VERBOSE_TESTS")
        $stdout.reopen(File::NULL)
        $stderr.reopen(File::NULL)
        $stdin.reopen(File::NULL)
      else
        # don't retry when focusing
        config.default_retry_count = 0
      end

      begin
        timeout = example.metadata.fetch(:timeout, 60)
        Timeout.timeout(timeout) do
          example.run
        end
      rescue Timeout::Error => e
        example.example.set_exception(e)
      end
    rescue SystemExit => e
      example.example.set_exception(e)
    ensure
      ENV.replace(@__env)
      Context.current = Context::ContextStruct.new

      $stdout.reopen(@__stdout)
      $stderr.reopen(@__stderr)
      $stdin.reopen(@__stdin)
      @__stdout.close
      @__stderr.close
      @__stdin.close

      Tap.all.each(&:clear_cache)
      Cachable::Registry.clear_all_caches

      FileUtils.rm_rf [
        *TEST_DIRECTORIES,
        *Keg.must_exist_subdirectories,
        HOMEBREW_LINKED_KEGS,
        HOMEBREW_PINNED_KEGS,
        HOMEBREW_PREFIX/"Caskroom",
        HOMEBREW_PREFIX/"Frameworks",
        HOMEBREW_LIBRARY/"Taps/homebrew/homebrew-cask",
        HOMEBREW_LIBRARY/"Taps/homebrew/homebrew-bar",
        HOMEBREW_LIBRARY/"Taps/homebrew/homebrew-foo",
        HOMEBREW_LIBRARY/"Taps/homebrew/homebrew-test-bot",
        HOMEBREW_LIBRARY/"Taps/homebrew/homebrew-shallow",
        HOMEBREW_LIBRARY/"PinnedTaps",
        HOMEBREW_REPOSITORY/".git",
        CoreTap.instance.path/".git",
        CoreTap.instance.alias_dir,
        CoreTap.instance.path/"formula_renames.json",
        CoreTap.instance.path/"tap_migrations.json",
        CoreTap.instance.path/"audit_exceptions",
        CoreTap.instance.path/"style_exceptions",
        CoreTap.instance.path/"pypi_formula_mappings.json",
        *Pathname.glob("#{HOMEBREW_CELLAR}/*/"),
        HOMEBREW_LIBRARY_PATH/"test/.vscode",
        HOMEBREW_LIBRARY_PATH/"test/.cursor",
        HOMEBREW_LIBRARY_PATH/"test/Library",
      ]

      files_after_test = Test::Helper::Files.find_files

      diff = Set.new(@__files_before_test) ^ Set.new(files_after_test)
      expect(diff).to be_empty, <<~EOS
        file leak detected:
        #{diff.map { |f| "  #{f}" }.join("\n")}
      EOS

      Homebrew.failed = @__homebrew_failed
    end
  end
end

RSpec::Matchers.define_negated_matcher :not_to_output, :output
RSpec::Matchers.alias_matcher :have_failed, :be_failed

# Match consecutive elements in an array.
RSpec::Matchers.define :array_including_cons do |*cons|
  match do |actual|
    expect(actual.each_cons(cons.size)).to include(cons)
  end
end
