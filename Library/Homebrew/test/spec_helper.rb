# typed: false
# frozen_string_literal: true

if ENV["HOMEBREW_TESTS_COVERAGE"]
  require "simplecov"
  require "simplecov-cobertura"
  SimpleCov.start
  require_relative "support/helper/integration_coverage"
  Homebrew::TestIntegrationCoverage.prepare!

  formatters = [
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::CoberturaFormatter,
  ]
  SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new(formatters)
end

require_relative "../standalone"
require_relative "../warnings"

Warnings.fail_on(/circular require considered harmful/)
Warnings.ignore(/CGI library is removed from Ruby 4\.0\./) { require "cgi" }

require "test-prof"

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

require_relative "support/extend/cacheable"

require_relative "../global"

require "system_command"
require "sandbox"

require "debug" if ENV["HOMEBREW_DEBUG"]

require "test/support/quiet_progress_formatter"
require "test/support/helper/api_hashable"
require "test/support/helper/cask"
require "test/support/helper/files"
require "test/support/helper/fixtures"
require "test/support/helper/formula"
require "test/support/helper/mktmpdir"
require "test/support/helper/subcommand"
require "test/support/helper/test_each"

require "test/support/helper/spec/shared_context/homebrew_cask" if OS.mac?
require "test/support/helper/spec/shared_context/integration_test"
require "test/support/helper/spec/shared_context/trust_store"
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
  HOMEBREW_TEMP_CELLAR,
  HOMEBREW_ALIASES,
].freeze

module Test
  module Helper
    module Dependencies
      extend T::Helpers

      requires_ancestor { RSpec::Core::Pending }

      # Skip missing tools locally, but fail on CI so runner dependency
      # regressions cannot silently reduce coverage. `brew test-bot`'s
      # portable-ruby validation runs this suite in homebrew-core build
      # containers that intentionally lack some tools, so skip there too.
      def ensure_test_dependency!(available, message)
        return if available

        raise message if ENV["CI"] && !ENV["HOMEBREW_TEST_BOT"]

        skip message
      end
    end
  end
end

# Make `instance_double` and `class_double`
# work when type-checking is active.
RSpec::Sorbet.allow_doubles!

RSpec.configure do |config|
  config.order = :random

  config.raise_errors_for_deprecations!
  config.warnings = true
  config.raise_on_warning = true
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
  config.include(Test::Helper::Subcommand)
  config.include(Test::Helper::Dependencies)

  config.extend(Test::Helper::TestEach)

  # Enable aggregate failures by default
  config.define_derived_metadata do |metadata|
    metadata[:aggregate_failures] = true unless metadata.key?(:aggregate_failures)
  end

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
    ensure_test_dependency!(which("java"), "Java is not installed.")
  end

  config.before(:each, :needs_jq) do
    ensure_test_dependency!(which("jq"), "jq is not installed.")
  end

  config.before(:each, :needs_python) do
    ensure_test_dependency!(which("python3") || which("python"), "Python is not installed.")
  end

  config.before(:each, :needs_network) do
    skip "Requires network connection." unless ENV["HOMEBREW_TEST_ONLINE"]
  end

  config.before(:each, :needs_homebrew_core) do
    core_tap_path = "#{ENV.fetch("HOMEBREW_LIBRARY")}/Taps/homebrew/homebrew-core"
    ensure_test_dependency!(Dir.exist?(core_tap_path), "Requires homebrew/core to be tapped.")
  end

  config.before(:each, :needs_systemd) do
    ensure_test_dependency!(which("systemctl"), "No SystemD found.")
  end

  config.before(:each, :needs_daemon_manager) do
    ensure_test_dependency!(which("systemctl") || which("launchctl"), "No LaunchCTL or SystemD found.")
  end

  config.before do |example|
    next if example.metadata.key?(:needs_network)
    next if example.metadata.key?(:needs_utils_curl)

    allow(Utils::Curl).to receive(:curl_executable).and_raise(<<~ERROR)
      Unexpected call to Utils::Curl.curl_executable without setting :needs_network or :needs_utils_curl.
    ERROR
  end

  config.before do
    allow(Utils).to receive(:sleep)
    allow(DevelopmentTools).to receive_messages(needs_build_formulae?: false, needs_libc_formula?: false)
    # Worker boundaries are exercised separately in sandbox_operation_spec.rb.
    allow(Sandbox).to receive(:isolate_operation?).and_return(false)

    Utils::Output.clear_printed_deprecations
  end

  config.before(:each, :no_api) do
    ENV["HOMEBREW_NO_INSTALL_FROM_API"] = "1"
  end

  svn_path_dirs = nil
  svn_skip_reason = nil
  svn_client_path_dirs = nil
  svn_client_skip_reason = nil

  config.define_derived_metadata(:needs_svnadmin) do |metadata|
    metadata[:needs_svn] = true
  end

  config.before(:each, :needs_svn) do
    ensure_test_dependency!(false, svn_client_skip_reason) if svn_client_skip_reason
    if svn_client_path_dirs
      ENV["PATH"] = PATH.new(ENV.fetch("PATH")).append(svn_client_path_dirs)
      next
    end

    svn_paths = PATH.new(ENV.fetch("PATH"))

    svn_shim = HOMEBREW_SHIMS_PATH/"shared/svn"
    unless SystemCommand.quiet_system svn_shim, "--version"
      svn_client_skip_reason = "Subversion is not installed."
      ensure_test_dependency!(false, svn_client_skip_reason)
    end

    svn_shim_path = Pathname(Utils.popen_read(svn_shim, "--homebrew=print-path").chomp.presence)
    svn_paths.prepend(svn_shim_path.dirname)

    svn = which("svn", svn_paths)
    unless svn
      svn_client_skip_reason = "svn is not installed."
      ensure_test_dependency!(false, svn_client_skip_reason)
    end

    svn_client_path_dirs = [svn.dirname]
    ENV["PATH"] = PATH.new(ENV.fetch("PATH")).append(svn_client_path_dirs)
  end

  config.before(:each, :needs_svnadmin) do
    ensure_test_dependency!(false, svn_skip_reason) if svn_skip_reason
    if svn_path_dirs
      ENV["PATH"] = PATH.new(ENV.fetch("PATH")).append(svn_path_dirs)
      next
    end

    svnadmin = which("svnadmin")
    unless svnadmin
      svn_skip_reason = "svnadmin is not installed."
      ensure_test_dependency!(false, svn_skip_reason)
    end

    svn_path_dirs = [svnadmin.dirname]
    ENV["PATH"] = PATH.new(ENV.fetch("PATH")).append(svn_path_dirs)
  end

  config.before(:each, :needs_homebrew_curl) do
    ENV["HOMEBREW_CURL"] = HOMEBREW_BREWED_CURL_PATH
    ensure_test_dependency!(Utils::Curl.curl_supports_tls13?, "A `curl` with TLS 1.3 support is required.")
  rescue FormulaUnavailableError
    ensure_test_dependency!(false, "No `curl` formula is available.")
  end

  config.before(:each, :needs_unzip) do
    ensure_test_dependency!(which("unzip"), "Unzip is not installed.")
  end

  config.around do |example|
    Homebrew.raise_deprecation_exceptions = true

    Tap.installed.each(&:clear_cache)
    Cacheable::Registry.clear_all_caches
    FormulaInstaller.attempted.clear
    FormulaInstaller.installed.clear
    FormulaInstaller.fetched.clear
    Utils::Curl.clear_path_cache

    TEST_DIRECTORIES.each(&:mkpath)

    @__homebrew_failed = Homebrew.failed?

    @__files_before_test = Test::Helper::Files.find_files

    @__env = ENV.to_hash # dup doesn't work on ENV

    @__stdout = $stdout.clone
    @__stderr = $stderr.clone
    @__stdin = $stdin.clone

    # Link original API cache files to test cache directory.
    source_api_cache = Pathname("#{ENV.fetch("HOMEBREW_CACHE")}/api")

    source_api_cache.glob("*.json").each do |path|
      target = HOMEBREW_CACHE/"api/#{path.basename}"
      FileUtils.ln_s path, target unless target.exist?
    end
    source_api_cache.glob("*.txt").each do |path|
      target = HOMEBREW_CACHE/"api/#{path.basename}"
      FileUtils.cp path, target unless target.exist?
    end

    source_api_internal_cache = source_api_cache/"internal"
    target_api_internal_cache = HOMEBREW_CACHE/"api/internal"
    target_api_internal_cache.mkpath

    # The real cache can hold package API files for multiple OS tags. Fan out
    # from one source so generated test-cache aliases do not collide.
    package_paths = source_api_internal_cache.glob("packages.*.jws.json")
    package_path = package_paths.find do |path|
      path.basename.to_s == "packages.#{Homebrew::SimulateSystem.current_tag}.jws.json"
    end || package_paths.first

    source_api_internal_cache.glob("*.{json,txt}").each do |path|
      next if path.basename.to_s.start_with?("packages.")

      target = target_api_internal_cache/path.basename
      next if target.exist?

      (path.extname == ".txt") ? FileUtils.cp(path, target) : FileUtils.ln(path, target)
    end

    if package_path
      [:generic, :linux, :macos, *MacOSVersion::SYMBOLS.keys].product([:arm, :intel]).each do |system, arch|
        tag = Utils::Bottles::Tag.new(system:, arch:)
        target = target_api_internal_cache/"packages.#{tag}.jws.json"
        FileUtils.ln package_path, target unless target.exist?
      end
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
      Homebrew::SimulateSystem.clear
      Context.current = Context::ContextStruct.new
      # Shut down and drop any memoized download queue so an example that
      # stubbed `DownloadQueue.new` cannot leak a double into later examples
      # or the `at_exit` shutdown hook.
      Homebrew::DownloadQueue.reset_default if defined?(Homebrew::DownloadQueue)

      $stdout.reopen(@__stdout)
      $stderr.reopen(@__stderr)
      $stdin.reopen(@__stdin)
      @__stdout.close
      @__stderr.close
      @__stdin.close

      Tap.all.each(&:clear_cache)
      Cacheable::Registry.clear_all_caches

      # Refuse to clean a config home outside the sandboxed `HOME`, else this deletes the user's
      # real `~/.homebrew/trust.json`; canonicalise first so `..`/symlinks can't slip past.
      home = Pathname(Dir.home).realpath
      user_config_home = Pathname(ENV.fetch("HOMEBREW_USER_CONFIG_HOME")).expand_path
      resolved_ancestor = user_config_home.ascend.find(&:exist?)&.realpath
      unless resolved_ancestor&.ascend&.include?(home)
        raise "HOMEBREW_USER_CONFIG_HOME (#{user_config_home}) is not sandboxed under HOME (#{Dir.home})"
      end

      FileUtils.rm_rf [
        *TEST_DIRECTORIES,
        *Keg.must_exist_subdirectories,
        HOMEBREW_LINKED_KEGS,
        HOMEBREW_PINNED_KEGS,
        HOMEBREW_PINNED_CASKS,
        user_config_home/"trust.json",
        HOMEBREW_PREFIX/"Caskroom",
        HOMEBREW_PREFIX/"var/homebrew/sandbox",
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
