# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/test"
require "sandbox"

RSpec.describe Homebrew::DevCmd::Test do
  define_negated_matcher :not_matching, :matching

  it_behaves_like "parseable arguments"

  test_each([false, true]) do |fetch_failed|
    it "handles #{fetch_failed ? "failed" : "successful"} test resource downloads before starting the sandbox" do
      cmd = described_class.new(["foo"])
      foo = formula("foo") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/foo-1.0.tar.gz"

        resource "fixture", :test do
          url "https://brew.sh/fixture-1.0.tar.gz"
        end

        test do
          true
        end
      end
      allow(cmd.args.named).to receive(:to_resolved_formulae).and_return([foo])
      allow(foo).to receive_messages(latest_version_installed?: true, linked?: true, recursive_dependencies: [])
      allow(Utils::GemSetup).to receive(:install_bundler_gems!)
      download_queue = instance_double(Homebrew::DownloadQueue,
                                       failed_downloads: fetch_failed ? [foo.resource("fixture")] : [])
      allow(Homebrew::DownloadQueue).to receive(:new).and_return(download_queue)
      events = []
      allow(download_queue).to receive(:enqueue) { |resource| events << resource.name }
      allow(download_queue).to receive(:fetch) { events << :fetch }
      allow(download_queue).to receive(:shutdown) { events << :shutdown }
      allow(Sandbox).to receive(:run_or_fork) { events << :sandbox }

      cmd.run

      expect(events).to eq(["fixture", :fetch, :shutdown, *(fetch_failed ? [] : [:sandbox])])
      expect(Homebrew.failed?).to eq(fetch_failed)
    end
  end

  it "asks to upgrade outdated test dependencies" do
    cmd = described_class.new(["foo"])
    foo = formula("foo") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/foo-1.0.tar.gz"

      test do
        true
      end
    end
    bar = formula("bar") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/bar-1.0.tar.gz"
    end
    dependency = Dependency.new(bar.name)
    allow(bar).to receive(:any_version_installed?).and_return(true)
    stub_formula_loader(bar)
    allow(dependency).to receive(:installed?).and_return(false)
    allow(cmd.args.named).to receive(:to_resolved_formulae).and_return([foo])
    allow(foo).to receive_messages(latest_version_installed?: true, linked?: true, deps: [dependency])
    allow(Utils::GemSetup).to receive(:install_bundler_gems!)

    expect { cmd.run }.to output(/foo has outdated test dependencies: bar\nUpgrade them with `brew upgrade bar`/)
      .to_stderr
  end

  it "asks to install missing and upgrade outdated test dependencies" do
    cmd = described_class.new(["foo"])
    foo = formula("foo") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/foo-1.0.tar.gz"

      test do
        true
      end
    end
    bar = formula("bar") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/bar-1.0.tar.gz"
    end
    baz = formula("baz") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/baz-1.0.tar.gz"
    end
    outdated_dependency = Dependency.new(bar.name)
    missing_dependency = Dependency.new(baz.name)
    allow(bar).to receive(:any_version_installed?).and_return(true)
    allow(baz).to receive(:any_version_installed?).and_return(false)
    stub_formula_loader(bar)
    stub_formula_loader(baz)
    allow(outdated_dependency).to receive(:installed?).and_return(false)
    allow(missing_dependency).to receive(:installed?).and_return(false)
    allow(cmd.args.named).to receive(:to_resolved_formulae).and_return([foo])
    allow(foo).to receive_messages(latest_version_installed?: true, linked?: true,
                                   deps: [missing_dependency, outdated_dependency])
    allow(Utils::GemSetup).to receive(:install_bundler_gems!)

    expect { cmd.run }.to output(<<~EOS).to_stderr
      Error: foo is missing test dependencies: baz
      Install with `brew install baz`.
      Error: foo has outdated test dependencies: bar
      Upgrade them with `brew upgrade bar`.
    EOS
  end

  it "tests a given Formula without process-listing warnings", :integration_test do
    skip "Nested sandboxing is not supported." if Sandbox.nested_sandbox?

    setup_test_formula "testball", <<~'RUBY', tab_attributes: { installed_on_request: true }
      test do
        assert_equal "test", shell_output("#{bin}/test")
        (logs/"testpath").write(testpath)
        require "socket"
        (testpath/"sockets").mkpath
        UNIXServer.open("sockets/test.sock") do
          UNIXSocket.open("sockets/test.sock", &:close)
        end
      end
    RUBY
    formula_prefix = Formula["testball"].prefix
    (formula_prefix/"bin").mkpath
    (formula_prefix/"bin/test").write <<~SH
      #!/bin/sh
      printf test
    SH
    (formula_prefix/"bin/test").chmod 0755
    HOMEBREW_LINKED_KEGS.mkpath
    (HOMEBREW_LINKED_KEGS/"testball").make_relative_symlink(formula_prefix)

    expect { brew "test", "--verbose", "testball", "HOMEBREW_NO_INSTALL_FROM_API" => "1" }
      .to output(a_string_matching(/Testing testball/)
        .and(not_matching(/sysmon request failed|pgrep: Cannot get process list/))).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success

    expect(Pathname((Formula["testball"].logs/"testpath").read)).not_to exist
  end

  it "blocks network access when test phase is offline", :integration_test, :needs_sandbox do
    skip "Sandbox not available." unless Sandbox.available?
    skip "Nested sandboxing is not supported." if Sandbox.nested_sandbox?

    formula_name = "testball_offline_test"
    setup_test_formula formula_name, <<~RUBY, tab_attributes: { installed_on_request: true }
      deny_network_access! :test
      test do
        require "socket"
        UNIXServer.open("test.sock") do
          UNIXSocket.open("test.sock", &:close)
        end
        system "curl", "example.org"
      end
    RUBY
    HOMEBREW_LINKED_KEGS.mkpath
    (HOMEBREW_LINKED_KEGS/formula_name).make_relative_symlink(Formula[formula_name].prefix)

    expect { brew "test", "--verbose", formula_name, "HOMEBREW_NO_INSTALL_FROM_API" => "1" }
      .to output(/curl: \((?:6\) Could not resolve host:|7\) Failed to connect to) example\.org/).to_stdout
      .and be_a_failure
  end
end
