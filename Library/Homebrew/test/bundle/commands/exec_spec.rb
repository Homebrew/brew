# frozen_string_literal: true

require "bundle"
require "bundle/commands/exec"
require "bundle/brewfile"
require "bundle/brew_services"

RSpec.describe Homebrew::Bundle::Commands::Exec do
  context "when a Brewfile is not found" do
    it "raises an error" do
      expect { described_class.run }.to raise_error(RuntimeError)
    end
  end

  context "when a Brewfile is found", :no_api do
    let(:brewfile_contents) { "brew 'openssl'" }

    before do
      allow_any_instance_of(Pathname).to receive(:read)
        .and_return(brewfile_contents)

      # don't try to load gcc/glibc
      allow(DevelopmentTools).to receive_messages(needs_libc_formula?: false, needs_compiler_formula?: false)

      stub_formula_loader formula("openssl") { url "openssl-1.0" }
      stub_formula_loader formula("pkgconf") { url "pkgconf-1.0" }
      ENV.extend(Superenv)
      allow(ENV).to receive(:setup_build_environment)
    end

    context "with valid command setup" do
      before do
        allow(described_class).to receive(:exec).and_return(nil)
        Homebrew::Bundle.reset!
      end

      it "does not raise an error" do
        expect { described_class.run("bundle", "install") }.not_to raise_error
      end

      it "does not raise an error when HOMEBREW_BUNDLE_EXEC_ALL_KEG_ONLY_DEPS is set" do
        ENV["HOMEBREW_BUNDLE_EXEC_ALL_KEG_ONLY_DEPS"] = "1"
        expect { described_class.run("bundle", "install") }.not_to raise_error
      end

      it "uses the formula version from the environment variable" do
        openssl_version = "1.1.1"
        ENV["PATH"] = "/opt/homebrew/opt/openssl/bin:/usr/bin:/bin"
        ENV["MANPATH"] = "/opt/homebrew/opt/openssl/man"
        ENV["HOMEBREW_BUNDLE_FORMULA_VERSION_OPENSSL"] = openssl_version
        allow(described_class).to receive(:which).and_return(Pathname("/usr/bin/bundle"))
        described_class.run("bundle", "install")
        expect(ENV.fetch("PATH")).to include("/Cellar/openssl/1.1.1/bin")
      end

      it "is able to run without bundle arguments" do
        allow(described_class).to receive(:exec).with("bundle", "install").and_return(nil)
        expect { described_class.run("bundle", "install") }.not_to raise_error
      end

      it "raises an exception if called without a command" do
        expect { described_class.run }.to raise_error(RuntimeError)
      end
    end

    context "with env command" do
      it "outputs the environment variables" do
        allow(OS).to receive(:linux?).and_return(true)

        expect { described_class.run("env", subcommand: "env") }.to \
          output(/export PATH=".+:\${PATH:-}"/).to_stdout
      end
    end

    it "raises if called with a command that's not on the PATH" do
      allow(described_class).to receive_messages(exec: nil, which: nil)
      expect { described_class.run("bundle", "install") }.to raise_error(RuntimeError)
    end

    it "prepends the path of the requested command to PATH before running" do
      expect(described_class).to receive(:exec).with("bundle", "install").and_return(nil)
      expect(described_class).to receive(:which).twice.and_return(Pathname("/usr/local/bin/bundle"))
      allow(ENV).to receive(:prepend_path).with(any_args).and_call_original
      expect(ENV).to receive(:prepend_path).with("PATH", "/usr/local/bin").once.and_call_original
      described_class.run("bundle", "install")
    end

    describe "when running a command which exists but is not on the PATH" do
      let(:brewfile_contents) { "brew 'zlib'" }

      before do
        stub_formula_loader formula("zlib") { url "zlib-1.0" }
      end

      shared_examples "allows command execution" do |command|
        it "does not raise" do
          allow(described_class).to receive(:exec).with(command).and_return(nil)
          expect(described_class).not_to receive(:which)
          expect { described_class.run(command) }.not_to raise_error
        end
      end

      it_behaves_like "allows command execution", "./configure"
      it_behaves_like "allows command execution", "bin/install"
      it_behaves_like "allows command execution", "/Users/admin/Downloads/command"
    end

    describe "when the Brewfile contains rbenv" do
      let(:rbenv_root) { Pathname.new("/tmp/.rbenv") }
      let(:brewfile_contents) { "brew 'rbenv'" }

      before do
        stub_formula_loader formula("rbenv") { url "rbenv-1.0" }
        ENV["HOMEBREW_RBENV_ROOT"] = rbenv_root.to_s
      end

      it "prepends the path of the rbenv shims to PATH before running" do
        allow(described_class).to receive(:exec).with("/usr/bin/true").and_return(0)
        allow(ENV).to receive(:fetch).with(any_args).and_call_original
        allow(ENV).to receive(:prepend_path).with(any_args).once.and_call_original

        expect(ENV).to receive(:fetch).with("HOMEBREW_RBENV_ROOT", "#{Dir.home}/.rbenv").once.and_call_original
        expect(ENV).to receive(:prepend_path).with("PATH", rbenv_root/"shims").once.and_call_original
        described_class.run("/usr/bin/true")
      end
    end

    describe "--services" do
      let(:brewfile_contents) { "brew 'nginx'\nbrew 'redis'" }

      let(:nginx_formula) do
        instance_double(
          Formula,
          name:                     "nginx",
          any_version_installed?:   true,
          any_installed_prefix:     HOMEBREW_PREFIX/"opt/nginx",
          plist_name:               "homebrew.mxcl.nginx",
          service_name:             "nginx",
          versioned_formulae_names: [],
          conflicts:                [instance_double(FormulaConflict, name: "httpd")],
          keg_only?:                false,
        )
      end

      let(:redis_formula) do
        instance_double(
          Formula,
          name:                     "redis",
          any_version_installed?:   true,
          any_installed_prefix:     HOMEBREW_PREFIX/"opt/redis",
          plist_name:               "homebrew.mxcl.redis",
          service_name:             "redis",
          versioned_formulae_names: ["redis@6.2"],
          conflicts:                [],
          keg_only?:                false,
        )
      end

      let(:services_info_pre) do
        [
          { "name" => "nginx", "running" => true, "loaded" => true },
          { "name" => "httpd", "running" => true, "loaded" => true },
          { "name" => "redis", "running" => false, "loaded" => false },
          { "name" => "redis@6.2", "running" => true, "loaded" => true, "registered" => true },
        ]
      end

      let(:services_info_post) do
        [
          { "name" => "nginx", "running" => true, "loaded" => true },
          { "name" => "httpd", "running" => false, "loaded" => false },
          { "name" => "redis", "running" => true, "loaded" => true },
          { "name" => "redis@6.2", "running" => false, "loaded" => false, "registered" => true },
        ]
      end

      before do
        stub_formula_loader(nginx_formula, "nginx")
        stub_formula_loader(redis_formula, "redis")

        pkgconf = formula("pkgconf") { url "pkgconf-1.0" }
        stub_formula_loader(pkgconf)
        allow(pkgconf).to receive(:any_version_installed?).and_return(false)

        allow_any_instance_of(Pathname).to receive(:file?).and_return(true)
        allow_any_instance_of(Pathname).to receive(:realpath) { |path| path }

        allow(described_class).to receive(:exit!).and_return(nil)
      end

      shared_examples "handles service lifecycle correctly" do
        it "handles service lifecycle correctly" do
          # The order of operations is important. This unweildly looking test is so it tests that.

          # Return original service state
          expect(Utils).to receive(:safe_popen_read)
            .with(HOMEBREW_BREW_FILE, "services", "info", "--json", "nginx", "httpd", "redis", "redis@6.2")
            .and_return(services_info_pre.to_json)

          # Stop original nginx
          expect(Homebrew::Bundle::BrewServices).to receive(:stop)
            .with("nginx", keep: true).and_return(true).ordered

          # Stop nginx conflicts
          expect(Homebrew::Bundle::BrewServices).to receive(:stop)
            .with("httpd", keep: true).and_return(true).ordered

          # Start new nginx
          expect(Homebrew::Bundle::BrewServices).to receive(:run)
            .with("nginx", file: nginx_service_file).and_return(true).ordered

          # No need to stop original redis (not started)

          # Stop redis conflicts
          expect(Homebrew::Bundle::BrewServices).to receive(:stop)
            .with("redis@6.2", keep: true).and_return(true).ordered

          # Start new redis
          expect(Homebrew::Bundle::BrewServices).to receive(:run)
            .with("redis", file: redis_service_file).and_return(true).ordered

          # Run exec commands
          expect(Kernel).to receive(:system).with("/usr/bin/true").and_return(true).ordered

          # Return new service state
          expect(Utils).to receive(:safe_popen_read)
            .with(HOMEBREW_BREW_FILE, "services", "info", "--json", "nginx", "httpd", "redis", "redis@6.2")
            .and_return(services_info_post.to_json)

          # Stop new services
          expect(Homebrew::Bundle::BrewServices).to receive(:stop)
            .with("nginx", keep: true).and_return(true).ordered
          expect(Homebrew::Bundle::BrewServices).to receive(:stop)
            .with("redis", keep: true).and_return(true).ordered

          # Restart registered services we stopped due to conflicts (skip httpd as not registered)
          expect(Homebrew::Bundle::BrewServices).to receive(:run).with("redis@6.2").and_return(true).ordered

          described_class.run("/usr/bin/true", services: true)
        end
      end

      context "with launchctl" do
        before do
          allow(Homebrew::Services::System).to receive(:launchctl?).and_return(true)
        end

        let(:nginx_service_file) { nginx_formula.any_installed_prefix/"#{nginx_formula.plist_name}.plist" }
        let(:redis_service_file) { redis_formula.any_installed_prefix/"#{redis_formula.plist_name}.plist" }

        include_examples "handles service lifecycle correctly"
      end

      context "with systemd" do
        before do
          allow(Homebrew::Services::System).to receive(:launchctl?).and_return(false)
        end

        let(:nginx_service_file) { nginx_formula.any_installed_prefix/"#{nginx_formula.service_name}.service" }
        let(:redis_service_file) { redis_formula.any_installed_prefix/"#{redis_formula.service_name}.service" }

        include_examples "handles service lifecycle correctly"
      end
    end
  end
end
