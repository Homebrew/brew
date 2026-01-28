# frozen_string_literal: true

require "open3"

require "formula_installer"
require "uninstall"

RSpec::Matchers.define_negated_matcher :be_a_failure, :be_a_success

# These shared contexts starting with `when` don't make sense.
RSpec.shared_context "integration test" do # rubocop:disable RSpec/ContextWording
  extend RSpec::Matchers::DSL

  matcher :be_a_success do
    match do |actual|
      status = actual.is_a?(Proc) ? actual.call : actual
      expect(status).to respond_to(:success?)
      status.success?
    end

    def supports_block_expectations?
      true
    end

    # It needs to be nested like this:
    #
    #   expect {
    #     expect {
    #       # command
    #     }.to be_a_success
    #   }.to output(something).to_stdout
    #
    # rather than this:
    #
    #   expect {
    #     expect {
    #       # command
    #     }.to output(something).to_stdout
    #   }.to be_a_success
    #
    def expects_call_stack_jump?
      true
    end
  end

  around do |example|
    ENV["HOMEBREW_INTEGRATION_TEST"] = "1"
    (HOMEBREW_PREFIX/"bin").mkpath
    FileUtils.touch HOMEBREW_PREFIX/"bin/brew"

    example.run
  ensure
    FileUtils.rm_rf HOMEBREW_PREFIX/"bin"
    ENV.delete("HOMEBREW_INTEGRATION_TEST")
  end

  # Generate unique ID to be able to
  # properly merge coverage results.
  def command_id
    Thread.current[:brew_integration_test_number] ||= 0
    "#{ENV.fetch("TEST_ENV_NUMBER", "")}:#{Thread.current[:brew_integration_test_number] += 1}"
  end

  # Runs a `brew` command with the test configuration
  # and with coverage reporting enabled.
  def brew(*args)
    env = args.last.is_a?(Hash) ? args.pop : {}

    # Avoid warnings when HOMEBREW_PREFIX/bin is not in PATH.
    # Also include our extra commands directory.
    path = [
      env["PATH"],
      (HOMEBREW_LIBRARY_PATH/"test/support/helper/cmd").realpath.to_s,
      (HOMEBREW_PREFIX/"bin").realpath.to_s,
      ENV.fetch("PATH"),
    ].compact.join(File::PATH_SEPARATOR)

    env.merge!(
      "PATH"                         => path,
      "HOMEBREW_PATH"                => path,
      "HOMEBREW_BREW_FILE"           => HOMEBREW_PREFIX/"bin/brew",
      "HOMEBREW_INTEGRATION_TEST"    => command_id,
      "HOMEBREW_TEST_TMPDIR"         => TEST_TMPDIR,
      "HOMEBREW_DEV_CMD_RUN"         => "true",
      "HOMEBREW_USE_RUBY_FROM_PATH"  => ENV.fetch("HOMEBREW_USE_RUBY_FROM_PATH", nil),
      "HOMEBREW_NO_INSTALL_FROM_API" => ENV.fetch("HOMEBREW_NO_INSTALL_FROM_API", nil),
      "GEM_HOME"                     => nil,
    )

    @ruby_args ||= begin
      ruby_args = HOMEBREW_RUBY_EXEC_ARGS.dup
      if ENV["HOMEBREW_TESTS_COVERAGE"]
        simplecov_spec = Gem.loaded_specs["simplecov"]
        parallel_tests_spec = Gem.loaded_specs["parallel_tests"]
        specs = []
        [simplecov_spec, parallel_tests_spec].each do |spec|
          specs << spec
          spec.runtime_dependencies.each do |dep|
            specs += dep.to_specs
          rescue Gem::LoadError => e
            onoe e
          end
        end
        specs.flat_map(&:full_require_paths).each { |lib| ruby_args << "-I" << lib }
        ruby_args << "-rsimplecov"
      end
      ruby_args << "-r#{HOMEBREW_LIBRARY_PATH}/test/support/helper/integration_mocks"
      ruby_args << "-e" << "$0 = ARGV.shift; load($0)"
      ruby_args << (HOMEBREW_LIBRARY_PATH/"brew.rb").resolved_path.to_s
    end

    Bundler.with_unbundled_env do
      # Allow instance variable here to improve performance through memoization.
      # rubocop:disable RSpec/InstanceVariable
      stdout, stderr, status = Open3.capture3(env, *@ruby_args, *args)
      # rubocop:enable RSpec/InstanceVariable
      $stdout.print stdout
      $stderr.print stderr
      status
    end
  end

  def brew_sh(*args)
    env = {
      "HOMEBREW_USE_RUBY_FROM_PATH" => ENV.fetch("HOMEBREW_USE_RUBY_FROM_PATH", nil),
      "HOMEBREW_CACHE"              => HOMEBREW_CACHE.to_s,
    }
    Bundler.with_unbundled_env do
      stdout, stderr, status = Open3.capture3(env, "#{ENV.fetch("HOMEBREW_PREFIX")}/bin/brew", *args)
      $stdout.print stdout
      $stderr.print stderr
      status
    end
  end

  def setup_test_formula(name, content = nil, tap: CoreTap.instance,
                         bottle_block: nil, tab_attributes: nil)
    case name
    when /^testball/
      # Use a different tarball for testball2 to avoid lock errors when writing concurrency tests
      prefix = (name == "testball2") ? "testball2" : "testball"
      tarball = if OS.linux?
        TEST_FIXTURE_DIR/"tarballs/#{prefix}-0.1-linux.tbz"
      else
        TEST_FIXTURE_DIR/"tarballs/#{prefix}-0.1.tbz"
      end
      bottle_block ||= <<~RUBY if name == "testball_bottle"
        bottle do
          root_url "file://#{TEST_FIXTURE_DIR}/bottles"
          sha256 cellar: :any_skip_relocation, all: "d7b9f4e8bf83608b71fe958a99f19f2e5e68bb2582965d32e41759c24f1aef97"
        end
      RUBY
      content = <<~RUBY
        desc "Some test"
        homepage "https://brew.sh/#{name}"
        url "file://#{tarball}"
        sha256 "#{tarball.sha256}"

        option "with-foo", "Build with foo"
        #{bottle_block}
        def install
          (prefix/"foo"/"test").write("test") if build.with? "foo"
          prefix.install Dir["*"]
          (buildpath/"test.c").write \
            "#include <stdio.h>\\nint main(){printf(\\"test\\");return 0;}"
          bin.mkpath
          system ENV.cc, "test.c", "-o", bin/"test"
        end

        #{content}

        # something here
      RUBY
    when "bar"
      content = <<~RUBY
        url "https://brew.sh/#{name}-1.0"
        depends_on "foo"
      RUBY
    when "package_license"
      content = <<~RUBY
        url "https://brew.sh/#patchelf-1.0"
        license "0BSD"
      RUBY
    else
      content ||= <<~RUBY
        url "https://brew.sh/#{name}-1.0"
      RUBY
    end

    formula_path = Formulary.find_formula_in_tap(name.downcase, tap).tap do |path|
      path.dirname.mkpath
      path.write <<~RUBY
        class #{Formulary.class_s(name)} < Formula
        #{content.gsub(/^(?!$)/, "  ")}
        end
      RUBY

      tap.clear_cache
    end

    return formula_path if tab_attributes.nil?

    keg = Formula[name].prefix
    keg.mkpath

    tab = Tab.for_name(name)
    tab.tabfile ||= keg/AbstractTab::FILENAME
    tab_attributes.each do |key, value|
      tab.instance_variable_set(:"@#{key}", value)
    end
    tab.write

    formula_path
  end

  def install_test_formula(name, content = nil, build_bottle: false)
    setup_test_formula(name, content)
    fi = FormulaInstaller.new(Formula[name], build_bottle:, installed_on_request: true)
    fi.prelude_fetch
    fi.prelude
    fi.fetch
    fi.install
    fi.finish
  end

  def uninstall_test_formula(name)
    rack = HOMEBREW_CELLAR/name
    kegs = rack.children.map { |prefix| Keg.new(prefix) }
    Homebrew::Uninstall.uninstall_kegs({ rack => kegs }, force: true, ignore_dependencies: true)
  end

  def setup_test_tap
    path = HOMEBREW_TAP_DIRECTORY/"homebrew/homebrew-foo"
    path.mkpath
    path.cd do
      system "git", "init"
      system "git", "remote", "add", "origin", "https://github.com/Homebrew/homebrew-foo"
      FileUtils.touch "readme"
      system "git", "add", "--all"
      system "git", "commit", "-m", "init"
    end
    path
  end

  def setup_remote_tap(name)
    Tap.fetch(name).tap do |tap|
      next if tap.installed?

      full_name = Tap.fetch(name).full_name
      # Check to see if the original Homebrew process has taps we can use.
      system_tap_path = Pathname("#{ENV.fetch("HOMEBREW_LIBRARY")}/Taps/#{full_name}")
      if system_tap_path.exist?
        system "git", "clone", "--shared", system_tap_path, tap.path
        system "git", "-C", tap.path, "checkout", "master"
      else
        tap.install(quiet: true)
      end
    end
  end

  def install_and_rename_coretap_formula(old_name, new_name)
    CoreTap.instance.path.cd do |tap_path|
      system "git", "init"
      system "git", "add", "--all"
      system "git", "commit", "-m",
             "#{old_name.capitalize} has not yet been renamed"

      brew "install", old_name

      (tap_path/"Formula/#{old_name}.rb").unlink
      (tap_path/"formula_renames.json").write JSON.pretty_generate(old_name => new_name)

      system "git", "add", "--all"
      system "git", "commit", "-m",
             "#{old_name.capitalize} has been renamed to #{new_name.capitalize}"
    end
  end

  def testball
    "#{TEST_FIXTURE_DIR}/testball.rb"
  end
end

RSpec.configure do |config|
  config.include_context "integration test", :integration_test
end
