# typed: true
# frozen_string_literal: true

require "utils/pypi"
require "formulary"

RSpec.describe PyPI do
  let(:pypi_package_url) do
    "https://files.pythonhosted.org/packages/b0/3f/2e1dad67eb172b6443b5eb37eb885a054a55cfd733393071499514140282/" \
      "snakemake-5.29.0.tar.gz"
  end
  let(:old_pypi_package_url) do
    "https://files.pythonhosted.org/packages/6f/c4/da52bfdd6168ea46a0fe2b7c983b6c34c377a8733ec177cc00b197a96a9f/" \
      "snakemake-5.28.0.tar.gz"
  end
  let(:non_pypi_package_url) do
    "https://github.com/pypa/pip-audit/releases/download/v2.5.6/v2.5.6.tar.gz"
  end

  describe PyPI::Package do
    let(:package_checksum) { "47417307d08ecb0707b3b29effc933bd63d8c8e3ab15509c62b685b7614c6568" }
    let(:old_package_checksum) { "2367ce91baf7f8fa7738d33aff9670ffdf5410bbac49aeb209f73b45a3425046" }

    let(:package) { described_class.new("snakemake") }
    let(:package_with_version) { described_class.new("snakemake==5.28.0") }
    let(:package_with_different_version) { described_class.new("snakemake==5.29.0") }
    let(:package_with_extra) { described_class.new("snakemake[foo]") }
    let(:package_with_extra_and_version) { described_class.new("snakemake[foo]==5.28.0") }
    let(:package_with_different_capitalization) { described_class.new("SNAKEMAKE") }
    let(:package_from_pypi_url) { described_class.new(pypi_package_url, is_url: true) }
    let(:package_from_non_pypi_url) { described_class.new(non_pypi_package_url, is_url: true) }
    let(:other_package) { described_class.new("virtualenv==20.2.0") }

    it "uses the sandboxed resolver for direct distribution URLs" do
      allow(Formula).to receive(:[]).with("python").and_return(instance_double(Formula, ensure_installed!: nil))
      allow(Utils).to receive(:popen_read).and_raise("unsandboxed metadata")
      allow(PyPI).to receive(:pip_output).with([
        Utils::Path.formula_opt_libexec("python")/"bin/python", "-m", "pip", "install", "-q", "--no-deps",
        "--dry-run", "--ignore-installed", "--report", "/dev/stdout", non_pypi_package_url
      ]).and_return('{"install":[{"metadata":{"name":"example","version":"1.0"}}]}')

      expect(package_from_non_pypi_url.name).to eq("example")
    end

    describe "initialize" do
      specify do
        expect(described_class.new("foo").name).to eq "foo"
        expect(described_class.new("foo[bar]").name).to eq "foo"
        expect(described_class.new("foo[bar]").extras).to eq ["bar"]
        expect(described_class.new("foo[bar,baz]").extras).to eq ["bar", "baz"]
        expect(described_class.new("foo==1.2.3").name).to eq "foo"
        expect(described_class.new("foo==1.2.3").version).to eq "1.2.3"
        expect(described_class.new("foo[bar]==1.2.3").extras).to eq ["bar"]
        expect(described_class.new("foo[bar,baz]==1.2.3").extras).to eq ["bar", "baz"]
        expect(described_class.new("foo[bar]==1.2.3").version).to eq "1.2.3"
        expect(described_class.new("foo[bar,baz]==1.2.3").version).to eq "1.2.3"
        expect(described_class.new(pypi_package_url, is_url: true).name).to eq "snakemake"
        expect(described_class.new(pypi_package_url, is_url: true).version).to eq "5.29.0"
      end
    end

    describe ".version=" do
      it "sets for package names" do
        package = described_class.new("snakemake==5.28.0")
        expect(package.version).to eq "5.28.0"

        package.version = "5.29.0"
        expect(package.version).to eq "5.29.0"
      end

      it "sets for PyPI package URLs" do
        package = described_class.new(old_pypi_package_url, is_url: true)
        expect(package.version).to eq "5.28.0"

        package.version = "5.29.0"
        expect(package.version).to eq "5.29.0"
      end

      it "fails for non-PYPI package URLs" do
        package = described_class.new(non_pypi_package_url, is_url: true)

        expect { package.version = "1.2.3" }.to raise_error(ArgumentError)
      end
    end

    describe ".valid_pypi_package?" do
      specify do
        expect(package.valid_pypi_package?).to be true
        expect(package_from_pypi_url.valid_pypi_package?).to be true
        expect(package_from_non_pypi_url.valid_pypi_package?).to be false
      end
    end

    describe ".pypi_info", :needs_network do
      specify do
        expect(package.pypi_info.first).to eq "snakemake"
        expect(package_with_extra.pypi_info.first).to eq "snakemake"
        expect(package_with_version.pypi_info).to eq ["snakemake", old_pypi_package_url, old_package_checksum,
                                                      "5.28.0"]
        expect(package_from_pypi_url.pypi_info).to eq ["snakemake", pypi_package_url, package_checksum, "5.29.0"]
      end

      it "gets pypi info from a package name and specified version" do
        expect(package.pypi_info(new_version: "5.29.0")).to eq ["snakemake", pypi_package_url, package_checksum,
                                                                "5.29.0"]
      end

      it "gets pypi info from a package name with overridden version" do
        expected_result = ["snakemake", pypi_package_url, package_checksum, "5.29.0"]
        expect(package_with_version.pypi_info(new_version: "5.29.0")).to eq expected_result
      end

      it "gets pypi info from a package name, extras and version" do
        expected_result = ["snakemake", old_pypi_package_url, old_package_checksum, "5.28.0"]
        expect(package_with_extra_and_version.pypi_info).to eq expected_result
      end

      it "gets pypi info from a url with overridden version" do
        expected_result = ["snakemake", old_pypi_package_url, old_package_checksum, "5.28.0"]
        expect(package_from_pypi_url.pypi_info(new_version: "5.28.0")).to eq expected_result
      end
    end

    describe ".to_s" do
      specify do
        expect(package.to_s).to eq "snakemake"
        expect(package_with_version.to_s).to eq "snakemake==5.28.0"
        expect(package_with_extra.to_s).to eq "snakemake[foo]"
        expect(package_with_extra_and_version.to_s).to eq "snakemake[foo]==5.28.0"
        expect(package_from_pypi_url.to_s).to eq "snakemake==5.29.0"
      end
    end

    describe ".same_package?" do
      it "returns false for different packages" do
        expect(package.same_package?(other_package)).to be false
      end

      it "returns true for the same package" do
        expect(package.same_package?(package_with_version)).to be true
      end

      it "returns true for the same package with different versions" do
        expect(package_with_version.same_package?(package_with_different_version)).to be true
      end

      it "returns true for the same package with different capitalization" do
        expect(package.same_package?(package_with_different_capitalization)).to be true
      end
    end

    describe "<=>" do
      it "returns -1" do
        expect(package <=> other_package).to eq(-1)
      end

      it "returns 0" do
        expect(package <=> package_with_version).to eq 0
      end

      it "returns 1" do
        expect(other_package <=> package_with_extra_and_version).to eq 1
      end
    end
  end

  describe ".pip_report" do
    context "with sandbox execution stubbed" do
      before do
        allow(Sandbox).to receive_messages(available?: true, avoid_nested_sandboxing?: false,
                                           full_write_isolation?: true)
        sandbox = Sandbox.new
        allow(Sandbox).to receive(:new).and_return(sandbox)
        allow(sandbox).to receive(:sandbox_command) { |args, _tmpdir| args }
        allow(sandbox).to receive(:apply_before_exec?).and_return(false)
      end

      it "runs metadata inspection without a terminal" do
        expect(described_class.pip_output(["/bin/sh", "-c",
                                           "if [ -t 0 ]; then printf terminal; else printf pipe; fi"]))
          .to eq("pipe")
      end

      it "redacts proxy authentication from command diagnostics" do
        allow(Context).to receive(:current).and_return(Context::ContextStruct.new(debug: true, verbose: true))

        %w[http_proxy HTTPS_PROXY all_proxy].each do |proxy|
          ENV[proxy] = "http://user:#{proxy}p$a=ss@proxy.example:3128"
          expect { described_class.pip_output(["/usr/bin/false"]) }
            .to raise_error(ErrorDuringExecution, /#{proxy}=\*{6} /)
            .and output(/#{proxy}=\*{6} /).to_stderr
        end
      end

      it "redacts authenticated proxies from printed output" do
        ENV["HTTPS_PROXY"] = "http://user:p$a=ss@proxy.example:3128"
        ENV["http_proxy"] = ""

        expect { described_class.pip_output(["/bin/sh", "-c", 'printf %s "$HTTPS_PROXY" >&2'], print_stderr: true) }
          .to output("******").to_stderr
      end

      it "preserves authenticated and empty proxy settings in the command environment" do
        ENV["HTTPS_PROXY"] = "http://user:p$a=ss@proxy.example:3128"
        ENV["http_proxy"] = ""

        expect(described_class.pip_output(["/bin/sh", "-c", 'printf "%s|%s" "$HTTPS_PROXY" "${http_proxy-unset}"']))
          .to eq("http://user:p$a=ss@proxy.example:3128|")
      end

      it "redacts authenticated proxies from failure output and serialised errors" do
        ENV["HTTPS_PROXY"] = "http://user:p$a=ss@proxy.example:3128"

        expect do
          described_class.pip_output(["/bin/sh", "-c", 'printf %s "$HTTPS_PROXY"; exit 1'])
        end.to raise_error(ErrorDuringExecution) { |error|
          expect([error.message, error.output.to_s, Utils.child_error_hash(error).to_s].join)
            .not_to include(ENV.fetch("HTTPS_PROXY"))
        }
      end

      it "runs the Git shim with the configured Git executable" do
        git = mktmpdir/"custom-git"
        git.write <<~SH
          #!/bin/sh
          printf 'git version 2.50.1'
        SH
        git.chmod 0755
        ENV["HOMEBREW_GIT"] = git.to_s

        expect(described_class.pip_output([HOMEBREW_SHIMS_PATH/"shared/git", "--version"]))
          .to eq("git version 2.50.1")
      end

      it "fetches SSH resources with their download settings before inspecting local metadata" do
        source = mktmpdir
        source.cd do
          system "git", "init", "--quiet"
          (source/"pyproject.toml").write("[project]\nname = 'tool'\n")
          system "git", "add", "pyproject.toml"
          system "git", "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "Initial commit"
          system "git", "tag", "v0.20.1"
          (source/"pyproject.toml").write("[project]\nname = 'newer-tool'\n")
          system "git", "-c", "commit.gpgsign=false", "commit", "--quiet", "-am", "Newer commit"
        end
        ssh = mktmpdir/"ssh"
        ssh.write <<~SH
          #!/bin/sh
          exec git-upload-pack #{source.to_s.shellescape}
        SH
        ssh.chmod 0755
        ENV["GIT_SSH_COMMAND"] = ssh.to_s.shellescape
        ENV["GIT_SSH_VARIANT"] = "ssh"
        resource = Resource.new("tool")
        resource.url "ssh://user@gitlab.example/tool", using: :git, tag: "v0.20.1",
                     revision: Utils.popen_read("git", "-C", source, "rev-parse", "v0.20.1").chomp

        expect(described_class.pip_output(["/bin/sh", "-c", 'cat "$1/pyproject.toml"', "brew-pypi",
                                           resource]))
          .to eq("[project]\nname = 'tool'\n")
      end
    end

    it "captures metadata with a minimal sandbox environment" do
      skip Sandbox.failure_reason unless Sandbox.available?
      skip "Homebrew is running inside another sandbox" if Sandbox.avoid_nested_sandboxing?

      ENV["HOMEBREW_METADATA_TEST"] = "parent value"
      expect(described_class.pip_output(["/bin/sh", "-c", 'printf %s "${HOMEBREW_METADATA_TEST:-clean}"']))
        .to eq("clean")
    end

    it "passes proxy settings into the sandbox" do
      skip Sandbox.failure_reason unless Sandbox.available?
      skip "Homebrew is running inside another sandbox" if Sandbox.avoid_nested_sandboxing?

      ENV["HTTPS_PROXY"] = "http://proxy.example:3128"
      expect(described_class.pip_output(["/bin/sh", "-c", 'printf %s "${HTTPS_PROXY:-clean}"']))
        .to eq("http://proxy.example:3128")
    end

    it "refuses metadata inspection when the sandbox is unavailable" do
      allow(Sandbox).to receive(:available?).and_return(false)
      expect { described_class.pip_output(["/bin/echo", "metadata"]) }.to raise_error(RuntimeError, /sandbox/)
    end

    it "refuses metadata inspection inside another sandbox" do
      allow(Sandbox).to receive_messages(available?: true, avoid_nested_sandboxing?: true)
      expect { described_class.pip_output(["/bin/echo", "metadata"]) }
        .to raise_error(RuntimeError, /another sandbox/)
    end

    it "warns when the available sandbox cannot isolate metadata changes" do
      skip Sandbox.failure_reason unless Sandbox.available?
      skip "Homebrew is running inside another sandbox" if Sandbox.avoid_nested_sandboxing?

      allow(Sandbox).to receive(:full_write_isolation?).and_return(false)
      expect { described_class.pip_output(["/bin/echo", "metadata"]) }
        .to output(/cannot restrict file permissions or ownership/).to_stderr
    end

    it "filters packages uploaded within the last day" do
      system "true"

      allow(Utils).to receive(:popen_read).and_raise("unsandboxed metadata")
      expect(described_class).to receive(:pip_output).with([
        Utils::Path.formula_opt_libexec("python")/"bin/python", "-m", "pip", "install", "-q",
        "--disable-pip-version-check", "--dry-run", "--ignore-installed",
        "--uploaded-prior-to=P1D", "--report=/dev/stdout", "snakemake"
      ], print_stderr: false).and_return('{"install":[]}')

      expect(described_class.pip_report([PyPI::Package.new("snakemake")])).to eq([])
    end

    it "passes the ignored-cooldown package to pip by its direct URL" do
      system "true"

      main = PyPI::Package.new("snakemake==5.29.0")
      dependency = PyPI::Package.new("pyyaml==6.0")
      sdist_url = "https://files.pythonhosted.org/packages/snakemake-5.29.0.tar.gz"
      allow(main).to receive(:pypi_info).and_return(["snakemake", sdist_url, "a" * 64, "5.29.0"])

      allow(Utils).to receive(:popen_read).and_raise("unsandboxed metadata")
      expect(described_class).to receive(:pip_output).with([
        Utils::Path.formula_opt_libexec("python")/"bin/python", "-m", "pip", "install", "-q",
        "--disable-pip-version-check", "--dry-run", "--ignore-installed",
        "--uploaded-prior-to=P1D", "--report=/dev/stdout",
        sdist_url, "pyyaml==6.0"
      ], print_stderr: false).and_return('{"install":[]}')

      expect(described_class.pip_report([main, dependency], ignore_cooldown_package: main)).to eq([])
    end

    it "preserves extras on the ignored-cooldown package's direct URL" do
      system "true"

      main = PyPI::Package.new("snakemake[foo]==5.29.0")
      sdist_url = "https://files.pythonhosted.org/packages/snakemake-5.29.0.tar.gz"
      allow(main).to receive(:pypi_info).and_return(["snakemake", sdist_url, "a" * 64, "5.29.0"])

      allow(Utils).to receive(:popen_read).and_raise("unsandboxed metadata")
      expect(described_class).to receive(:pip_output).with([
        Utils::Path.formula_opt_libexec("python")/"bin/python", "-m", "pip", "install", "-q",
        "--disable-pip-version-check", "--dry-run", "--ignore-installed",
        "--uploaded-prior-to=P1D", "--report=/dev/stdout",
        "snakemake[foo] @ #{sdist_url}"
      ], print_stderr: false).and_return('{"install":[]}')

      expect(described_class.pip_report([main], ignore_cooldown_package: main)).to eq([])
    end

    it "keeps the ignored-cooldown package cooled when its sdist URL is unavailable" do
      system "true"

      main = PyPI::Package.new("snakemake==5.29.0")
      allow(main).to receive(:pypi_info).and_return(nil)

      allow(Utils).to receive(:popen_read).and_raise("unsandboxed metadata")
      expect(described_class).to receive(:pip_output).with([
        Utils::Path.formula_opt_libexec("python")/"bin/python", "-m", "pip", "install", "-q",
        "--disable-pip-version-check", "--dry-run", "--ignore-installed",
        "--uploaded-prior-to=P1D", "--report=/dev/stdout",
        "snakemake==5.29.0"
      ], print_stderr: false).and_return('{"install":[]}')

      expect(described_class.pip_report([main], ignore_cooldown_package: main)).to eq([])
    end
  end

  describe ".update_python_resources!" do
    it "uses the stable resource for dependency and package metadata resolution" do
      path = mktmpdir/"foo.rb"
      path.write <<~RUBY
        class Foo < Formula
          url "ssh://git@gitlab.example/foo.git", tag: "v1.0"

          def install
            bin.install "foo"
          end
        end
      RUBY
      formula = Formulary.from_contents("foo", path, path.read)
      allow(Formula).to receive(:[]).with("python").and_return(instance_double(Formula, ensure_installed!: true))
      allow(described_class).to receive(:pip_output)
        .with(array_including(formula.resource), any_args)
        .and_return('{"install":[{"metadata":{"name":"foo","version":"1.0"}}]}')

      expect(described_class.update_python_resources!(formula, quiet: true)).to be true
    end

    context "with a package name and a non-PyPI stable URL" do
      let(:url) { "https://github.com/example/foo/archive/refs/tags/v1.0.tar.gz" }
      let(:formula) do
        path = mktmpdir/"foo.rb"
        path.write <<~RUBY
          class Foo < Formula
            url "#{url}"
            sha256 "#{"a" * 64}"

            def install
              bin.install "foo"
            end
          end
        RUBY
        Formulary.from_contents("foo", path, path.read)
      end
      let(:report) { '{"install":[{"metadata":{"name":"foo","version":"1.0"}}]}' }

      before do
        allow(Formula).to receive(:[]).with("python").and_return(instance_double(Formula, ensure_installed!: true))
        allow(described_class).to receive(:pip_output).and_return(report)
      end

      it "resolves the stable URL with the package's extras when PyPI lacks the formula version" do
        allow(Utils::Curl).to receive(:curl_output)
          .and_return(instance_double(SystemCommand::Result,
                                      status: instance_double(Process::Status, success?: false)))
        expect(described_class).to receive(:pip_output)
          .with(array_including("--report=/dev/stdout", "foo[bar] @ #{url}"), any_args).and_return(report)

        described_class.update_python_resources!(formula, package_name: "foo[bar]", quiet: true)
      end

      it "resolves the package from PyPI when it has the formula version" do
        pypi_json = {
          info: { name: "foo", version: "1.0" },
          urls: [{ packagetype: "sdist", url: "https://files.pythonhosted.org/packages/foo-1.0.tar.gz",
                   digests: { sha256: "b" * 64 } }],
        }.to_json
        allow(Utils::Curl).to receive(:curl_output)
          .and_return(instance_double(SystemCommand::Result,
                                      status: instance_double(Process::Status, success?: true), stdout: pypi_json))
        expect(described_class).to receive(:pip_output)
          .with(array_including("--report=/dev/stdout", "foo[bar]==1.0"), any_args).and_return(report)

        described_class.update_python_resources!(formula, package_name: "foo[bar]", quiet: true)
      end
    end

    it "keeps resources with livecheck blocks" do
      path = mktmpdir/"foo.rb"
      livecheck_resource = <<~RUBY
        resource "aws-lambda-rie" do
          url "https://github.com/aws/aws-lambda-runtime-interface-emulator/archive/refs/tags/v1.0.tar.gz"
          sha256 "#{"c" * 64}"

          livecheck do
            url "https://github.com/aws/aws-lambda-runtime-interface-emulator/releases"
            regex(/^v?(\\d+(?:\\.\\d+)+)$/i)
          end
        end
      RUBY
      contents = <<~RUBY
        class Foo < Formula
          url "https://files.pythonhosted.org/packages/foo-1.0.tar.gz"
          sha256 "#{"a" * 64}"

          resource "bar" do
            url "https://files.pythonhosted.org/packages/bar-0.9.tar.gz"
            sha256 "#{"b" * 64}"
          end

        #{livecheck_resource}

          def install
            bin.install "foo"
          end
        end
      RUBY
      path.write(contents)
      package = PyPI::Package.new("bar==1.0")
      livecheck_package = PyPI::Package.new("aws-lambda-rie==1.0")

      allow(Formula).to receive(:[]).with("python").and_return(instance_double(Formula, ensure_installed!: true))
      allow(described_class).to receive(:pip_report)
        .and_return([PyPI::Package.new("foo==1.0"), package, livecheck_package])
      allow(package).to receive(:pypi_info).and_return(
        ["bar", "https://files.pythonhosted.org/packages/bar-1.0.tar.gz", "d" * 64, "1.0", nil],
      )
      expect(livecheck_package).not_to receive(:pypi_info)

      described_class.update_python_resources!(Formulary.from_contents("foo", path, contents),
                                               package_name: "foo", quiet: true)

      expect(path.read).to eq <<~RUBY
        class Foo < Formula
          url "https://files.pythonhosted.org/packages/foo-1.0.tar.gz"
          sha256 "#{"a" * 64}"

          resource "bar" do
            url "https://files.pythonhosted.org/packages/bar-1.0.tar.gz"
            sha256 "#{"d" * 64}"
          end

        #{livecheck_resource}

          def install
            bin.install "foo"
          end
        end
      RUBY
    end

    it "exempts the main package from the cooldown when requested" do
      path = mktmpdir/"foo.rb"
      contents = <<~RUBY
        class Foo < Formula
          url "https://files.pythonhosted.org/packages/foo-1.0.tar.gz"
          sha256 "#{"a" * 64}"

          resource "bar" do
            url "https://files.pythonhosted.org/packages/bar-0.9.tar.gz"
            sha256 "#{"b" * 64}"
          end

          def install
            bin.install "foo"
          end
        end
      RUBY
      path.write(contents)
      bar = PyPI::Package.new("bar==1.0")

      allow(Formula).to receive(:[]).with("python").and_return(instance_double(Formula, ensure_installed!: true))
      allow(bar).to receive(:pypi_info).and_return(
        ["bar", "https://files.pythonhosted.org/packages/bar-1.0.tar.gz", "d" * 64, "1.0", nil],
      )
      exempted = T.let(nil, T.nilable(PyPI::Package))
      allow(described_class).to receive(:pip_report) do |_packages, **kwargs|
        exempted = kwargs[:ignore_cooldown_package] if kwargs.key?(:ignore_cooldown_package)
        [PyPI::Package.new("foo==1.0"), bar]
      end

      described_class.update_python_resources!(Formulary.from_contents("foo", path, contents),
                                               package_name: "foo", quiet: true,
                                               ignore_main_package_cooldown: true)

      expect(exempted&.name).to eq "foo"
    end
  end

  describe "resolver failures" do
    let(:resource) do
      Resource.new("foo") do
        url "ssh://git@gitlab.example/foo.git", tag: "v1.0"
      end
    end
    let(:package) { PyPI::Package.new(resource.url, is_url: true, resource:) }

    before do
      allow(Formula).to receive(:[]).with("python").and_return(instance_double(Formula, ensure_installed!: true))
      allow(described_class).to receive(:pip_output).and_raise(ErrorDuringExecution.new(["pip"], status: 1))
    end

    it "renders resource URLs in failed metadata commands" do
      expect { package.name }
        .to raise_error(ArgumentError, %r{--report /dev/stdout ssh://git@gitlab\.example/foo\.git`})
    end

    it "renders resource URLs in failed dependency commands" do
      expect { described_class.pip_report([package]) }
        .to output(%r{--report=/dev/stdout ssh://git@gitlab\.example/foo\.git`}).to_stderr
        .and raise_error(SystemExit)
    end
  end

  describe "update_pypi_url", :needs_network do
    it "updates url to new version" do
      expect(described_class.update_pypi_url(old_pypi_package_url, "5.29.0")).to eq pypi_package_url
    end

    it "returns nil for invalid versions" do
      expect(described_class.update_pypi_url(old_pypi_package_url, "0.0.0")).to be_nil
    end

    it "returns nil for non-pypi urls" do
      expect(described_class.update_pypi_url(non_pypi_package_url, "1.1")).to be_nil
    end
  end
end
