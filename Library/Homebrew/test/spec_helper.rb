# frozen_string_literal: true

if ENV["HOMEBREW_TESTS_COVERAGE"]
  require "simplecov"
  require "simplecov-cobertura"

  formatters = [
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::CoberturaFormatter,
  ]
  SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new(formatters)

  if RUBY_PLATFORM[/darwin/] && ENV["TEST_ENV_NUMBER"]
    SimpleCov.at_exit do
      result = SimpleCov.result
      result.format! if ParallelTests.number_of_running_processes <= 1
    end
  end
end

require_relative "../warnings"

Warnings.ignore :parser_syntax do
  require "rubocop"
end

require "rspec/its"
require "rspec/github"
require "rspec/retry"
require "rspec/sorbet"
require "rubocop/rspec/support"
require "find"
require "byebug"
require "timeout"

$LOAD_PATH.push(File.expand_path("#{ENV.fetch("HOMEBREW_LIBRARY")}/Homebrew/test/support/lib"))

require_relative "../global"

require "test/support/quiet_progress_formatter"
require "test/support/helper/cask"
require "test/support/helper/fixtures"
require "test/support/helper/formula"
require "test/support/helper/mktmpdir"
require "test/support/helper/output_as_tty"

require "test/support/helper/spec/shared_context/homebrew_cask" if OS.mac?
require "test/support/helper/spec/shared_context/integration_test"
require "test/support/helper/spec/shared_examples/formulae_exist"

TEST_DIRECTORIES = [
  CoreTap.instance.path/"Formula",
  HOMEBREW_CACHE,
  HOMEBREW_CACHE_FORMULA,
  HOMEBREW_CELLAR,
  HOMEBREW_LOCKS,
  HOMEBREW_LOGS,
  HOMEBREW_TEMP,
].freeze

# Make `instance_double` and `class_double`
# work when type-checking is active.
RSpec::Sorbet.allow_doubles!

RSpec.configure do |config|
  config.order = :random

  config.raise_errors_for_deprecations!

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

  # Don't want the nicer default retry behaviour when using BuildPulse to
  # identify flaky tests.
  config.default_retry_count = 2 unless ENV["BUILDPULSE"]

  # Increase timeouts for integration tests (as we expect them to take longer).
  config.around(:each, :integration_test) do |example|
    example.metadata[:timeout] ||= 120
    example.run
  end

  config.around(:each, :needs_network) do |example|
    example.metadata[:timeout] ||= 120

    # Don't want the nicer default retry behaviour when using BuildPulse to
    # identify flaky tests.
    example.metadata[:retry] ||= 4 unless ENV["BUILDPULSE"]

    example.metadata[:retry_wait] ||= 2
    example.metadata[:exponential_backoff] ||= true
    example.run
  end

  # Never truncate output objects.
  RSpec::Support::ObjectFormatter.default_instance.max_formatted_output_length = nil

  config.include(FileUtils)

  config.include(Context)

  config.include(RuboCop::RSpec::ExpectOffense)

  config.include(Test::Helper::Cask)
  config.include(Test::Helper::Fixtures)
  config.include(Test::Helper::Formula)
  config.include(Test::Helper::MkTmpDir)
  config.include(Test::Helper::OutputAsTTY)

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
    def find_files
      return [] unless File.exist?(TEST_TMPDIR)

      Find.find(TEST_TMPDIR)
          .reject { |f| File.basename(f) == ".DS_Store" }
          .reject { |f| TEST_DIRECTORIES.include?(Pathname(f)) }
          .map { |f| f.sub(TEST_TMPDIR, "") }
    end

    Homebrew.raise_deprecation_exceptions = true

    Formulary.clear_cache
    Tap.clear_cache
    DependencyCollector.clear_cache
    Formula.clear_cache
    Keg.clear_cache
    Tab.clear_cache
    Dependency.clear_cache
    Requirement.clear_cache
    Readall.clear_cache if defined?(Readall)
    FormulaInstaller.clear_attempted
    FormulaInstaller.clear_installed
    FormulaInstaller.clear_fetched
    Utils::Curl.clear_path_cache

    TEST_DIRECTORIES.each(&:mkpath)

    @__homebrew_failed = Homebrew.failed?

    @__files_before_test = find_files

    @__env = ENV.to_hash # dup doesn't work on ENV

    @__stdout = $stdout.clone
    @__stderr = $stderr.clone
    @__stdin = $stdin.clone

    begin
      if (example.metadata.keys & [:focus, :byebug]).empty? && !ENV.key?("HOMEBREW_VERBOSE_TESTS")
        $stdout.reopen(File::NULL)
        $stderr.reopen(File::NULL)
      else
        # don't retry when focusing/debugging
        config.default_retry_count = 0
      end
      $stdin.reopen(File::NULL)

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

      Formulary.clear_cache
      Tap.clear_cache
      DependencyCollector.clear_cache
      Formula.clear_cache
      Keg.clear_cache
      Tab.clear_cache
      Dependency.clear_cache
      Requirement.clear_cache
      Readall.clear_cache if defined?(Readall)

      FileUtils.rm_rf [
        *TEST_DIRECTORIES,
        *Keg::MUST_EXIST_SUBDIRECTORIES,
        HOMEBREW_LINKED_KEGS,
        HOMEBREW_PINNED_KEGS,
        HOMEBREW_PREFIX/"var",
        HOMEBREW_PREFIX/"Caskroom",
        HOMEBREW_PREFIX/"Frameworks",
        HOMEBREW_LIBRARY/"Taps/homebrew/homebrew-cask",
        HOMEBREW_LIBRARY/"Taps/homebrew/homebrew-bar",
        HOMEBREW_LIBRARY/"Taps/homebrew/homebrew-bundle",
        HOMEBREW_LIBRARY/"Taps/homebrew/homebrew-foo",
        HOMEBREW_LIBRARY/"Taps/homebrew/homebrew-services",
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
      ]

      files_after_test = find_files

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
RSpec::Matchers.define_negated_matcher :not_raise_error, :raise_error
RSpec::Matchers.alias_matcher :have_failed, :be_failed
RSpec::Matchers.alias_matcher :a_string_containing, :include

RSpec::Matchers.define :a_json_string do
  match do |actual|
    JSON.parse(actual)
    true
  rescue JSON::ParserError
    false
  end
end

# Match consecutive elements in an array.
RSpec::Matchers.define :array_including_cons do |*cons|
  match do |actual|
    expect(actual.each_cons(cons.size)).to include(cons)
  end
end
