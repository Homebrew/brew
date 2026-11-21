# typed: true
# frozen_string_literal: true

require "utils/shell"

require "formula"
require "caveats"

RSpec.describe Caveats do
  subject(:caveats) { described_class.new(f) }

  let(:f) do
    formula do
      T.bind(self, T.class_of(Formula))
      url "foo-1.0"
    end
  end

  specify "#f" do
    expect(caveats.formula).to eq(f)
  end

  describe "#empty?" do
    it "returns true if the Formula has no caveats" do
      expect(caveats).to be_empty
    end

    it "returns false if the Formula has caveats" do
      f = formula do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"

        def caveats
          "something"
        end
      end

      expect(described_class.new(f)).not_to be_empty
    end
  end

  describe "#caveats" do
    context "when service block is defined" do
      before do
        allow(Utils::Service).to receive_messages(launchctl?: true, systemctl?: true)
      end

      it "gives information about service" do
        f = formula do
          T.bind(self, T.class_of(Formula))
          url "foo-1.0"
          service do
            T.bind(self, Homebrew::Service)
            run [bin/"php", "test"]
          end
        end
        caveats = described_class.new(f).caveats

        expect(f.service?).to be(true)
        expect(caveats).to include("#{f.bin}/php test")
        expect(caveats).to include("background service")
      end

      it "prints warning when no service daemon is found" do
        f = formula do
          T.bind(self, T.class_of(Formula))
          url "foo-1.0"
          service do
            T.bind(self, Homebrew::Service)
            run [bin/"cmd"]
          end
        end
        expect(Utils::Service).to receive(:launchctl?).and_return(false)
        expect(Utils::Service).to receive(:systemctl?).and_return(false)
        expect(described_class.new(f).caveats).to include("service which can only be used on macOS or systemd!")
      end

      it "prints service startup information when service.require_root is true" do
        f = formula do
          T.bind(self, T.class_of(Formula))
          url "foo-1.0"
          service do
            T.bind(self, Homebrew::Service)
            run [bin/"cmd"]
            require_root true
          end
        end
        expect(Utils::Service).to receive(:running?).with(f).once.and_return(false)
        expect(described_class.new(f).caveats).to include("startup")
      end

      it "prints service login information" do
        f = formula do
          T.bind(self, T.class_of(Formula))
          url "foo-1.0"
          service do
            T.bind(self, Homebrew::Service)
            run [bin/"cmd"]
          end
        end
        expect(Utils::Service).to receive(:running?).with(f).once.and_return(false)
        expect(described_class.new(f).caveats).to include("restart at login")
      end

      it "gives information about require_root restarting services after upgrade" do
        f = formula do
          T.bind(self, T.class_of(Formula))
          url "foo-1.0"
          service do
            T.bind(self, Homebrew::Service)
            run [bin/"cmd"]
            require_root true
          end
        end
        f_obj = described_class.new(f)
        expect(Utils::Service).to receive(:running?).with(f).once.and_return(true)
        expect(f_obj.caveats).to include("  sudo brew services restart #{f.full_name}")
      end

      it "gives information about user restarting services after upgrade" do
        f = formula do
          T.bind(self, T.class_of(Formula))
          url "foo-1.0"
          service do
            T.bind(self, Homebrew::Service)
            run [bin/"cmd"]
          end
        end
        f_obj = described_class.new(f)
        expect(Utils::Service).to receive(:running?).with(f).once.and_return(true)
        expect(f_obj.caveats).to include("  brew services restart #{f.full_name}")
      end

      it "gives information about require_root starting services after upgrade" do
        f = formula do
          T.bind(self, T.class_of(Formula))
          url "foo-1.0"
          service do
            T.bind(self, Homebrew::Service)
            run [bin/"cmd"]
            require_root true
          end
        end
        f_obj = described_class.new(f)
        expect(Utils::Service).to receive(:running?).with(f).once.and_return(false)
        expect(f_obj.caveats).to include("  sudo brew services start #{f.full_name}")
      end

      it "gives information about user starting services after upgrade" do
        f = formula do
          T.bind(self, T.class_of(Formula))
          url "foo-1.0"
          service do
            T.bind(self, Homebrew::Service)
            run [bin/"cmd"]
          end
        end
        f_obj = described_class.new(f)
        expect(Utils::Service).to receive(:running?).with(f).once.and_return(false)
        expect(f_obj.caveats).to include("  brew services start #{f.full_name}")
      end

      it "gives information about service manual command" do
        f = formula do
          T.bind(self, T.class_of(Formula))
          url "foo-1.0"
          service do
            T.bind(self, Homebrew::Service)
            run [bin/"cmd", "start"]
            environment_variables VAR: "foo"
          end
        end
        cmd = "#{HOMEBREW_CELLAR}/formula_name/1.0/bin/cmd"
        caveats = described_class.new(f).caveats

        expect(caveats).to include("if you don't want/need a background service")
        expect(caveats).to include("VAR=\"foo\" #{cmd} start")
      end

      it "prints info when there are custom service files" do
        f = formula do
          T.bind(self, T.class_of(Formula))
          url "foo-1.0"
          service do
            T.bind(self, Homebrew::Service)
            name macos: "custom.mxcl.foo", linux: "custom.foo"
          end
        end
        expect(Utils::Service).to receive(:installed?).with(f).once.and_return(true)
        expect(Utils::Service).to receive(:running?).with(f).once.and_return(false)
        expect(described_class.new(f).caveats).to include("restart at login")
      end
    end

    context "when f.keg_only is not nil" do
      let(:f) do
        formula do
          T.bind(self, T.class_of(Formula))
          url "foo-1.0"
          keg_only "some reason"
        end
      end
      let(:caveats) { described_class.new(f).caveats }

      it "tells formula is keg_only" do
        expect(caveats).to include("keg-only")
      end

      it "omits keg-only caveats when the formula is linked" do
        allow(f).to receive(:linked?).and_return(true)

        expect(caveats).to be_empty
      end

      it "gives command to be run when f.bin is a directory" do
        Pathname.new(f.bin).mkpath
        expect(caveats).to include(f.opt_bin.to_s)
      end

      it "gives command to be run when f.sbin is a directory" do
        Pathname.new(f.sbin).mkpath
        expect(caveats).to include(f.opt_sbin.to_s)
      end

      context "when f.lib or f.include is a directory" do
        it "gives command to be run when f.lib is a directory" do
          Pathname.new(f.lib).mkpath
          expect(caveats).to include("-L#{f.opt_lib}")
        end

        it "gives command to be run when f.include is a directory" do
          Pathname.new(f.include).mkpath
          expect(caveats).to include("-I#{f.opt_include}")
        end

        it "gives PKG_CONFIG_PATH when f.lib/'pkgconfig' and f.share/'pkgconfig' are directories" do
          allow_any_instance_of(Object).to receive(:which).with(any_args).and_return(Pathname.new("blah"))

          Pathname.new(f.share/"pkgconfig").mkpath
          Pathname.new(f.lib/"pkgconfig").mkpath

          expect(caveats).to include("#{f.opt_lib}/pkgconfig")
          expect(caveats).to include("#{f.opt_share}/pkgconfig")
        end
      end

      context "when joining different caveat types together" do
        let(:f) do
          formula do
            T.bind(self, T.class_of(Formula))
            url "foo-1.0"
            keg_only "some reason"

            def caveats
              "something else"
            end

            service do
              T.bind(self, Homebrew::Service)
              run [bin/"cmd"]
            end
          end
        end

        let(:caveats) { described_class.new(f).caveats }

        it "adds the correct amount of new lines to the output" do
          allow(Utils::Service).to receive_messages(running?: false, systemctl?: true)
          expect(caveats).to include("something else")
          expect(caveats).to include("keg-only")
          expect(caveats).to include("if you don't want/need a background service")
          expect(caveats.count("\n")).to eq(9)
        end
      end
    end

    describe "PATH shadowing" do
      let(:f) do
        formula do
          T.bind(self, T.class_of(Formula))
          url "foo-1.0"
        end
      end

      before do
        Pathname.new(f.opt_bin).mkpath
        FileUtils.touch(f.opt_bin/"foo")
        FileUtils.chmod(0755, f.opt_bin/"foo")
        allow(f).to receive(:any_version_installed?).and_return(true)
        allow_any_instance_of(Object).to receive(:which).and_call_original
      end

      it "groups shadowed executables on PATH by directory in alphabetical order" do
        %w[bar baz].each do |name|
          FileUtils.touch(f.opt_bin/name)
          FileUtils.chmod(0755, f.opt_bin/name)
        end

        { "foo" => "/usr/local/bin", "bar" => "/usr/local/bin", "baz" => "/opt/local/bin" }.each do |name, dir|
          shadower = Pathname.new("#{dir}/#{name}")
          allow_any_instance_of(Object).to receive(:which).with(name, ORIGINAL_PATHS).and_return(shadower)
          allow(shadower).to receive(:realpath).and_return(shadower)
        end
        allow(f.opt_bin).to receive(:children).and_return([f.opt_bin/"foo", f.opt_bin/"baz", f.opt_bin/"bar"])

        expect(described_class.new(f).shadowed_path_text)
          .to include("commands in /usr/local/bin:\nbar\nfoo\n" \
                      "The following #{f.name} executables are shadowed by commands in /opt/local/bin:\nbaz\n" \
                      "Running these by name will not invoke the version provided by Homebrew\n" \
                      "because the shadowing commands come earlier in your PATH.\n")
      end

      it "lays out shadowed executables in compact columns in a terminal" do
        FileUtils.touch(f.opt_bin/"bar")
        FileUtils.chmod(0755, f.opt_bin/"bar")
        %w[foo bar].each do |name|
          shadower = Pathname.new("/usr/local/bin/#{name}")
          allow_any_instance_of(Object).to receive(:which).with(name, ORIGINAL_PATHS).and_return(shadower)
          allow(shadower).to receive(:realpath).and_return(shadower)
        end
        allow($stdout).to receive(:tty?).and_return(true)
        allow(Tty).to receive(:width).and_return(80)

        expect(described_class.new(f).shadowed_path_text).to include("commands in /usr/local/bin:\nbar  foo\n")
      end

      it "does not warn when PATH resolves to the formula's own executable" do
        own = f.opt_bin/"foo"
        allow_any_instance_of(Object).to receive(:which).with("foo", ORIGINAL_PATHS).and_return(own)

        expect(described_class.new(f).shadowed_path_text).to be_nil
      end

      it "does not warn for keg-only formulae" do
        keg_only_f = formula do
          T.bind(self, T.class_of(Formula))
          url "foo-1.0"
          keg_only "some reason"
        end
        Pathname.new(keg_only_f.opt_bin).mkpath
        FileUtils.touch(keg_only_f.opt_bin/"foo")
        FileUtils.chmod(0755, keg_only_f.opt_bin/"foo")
        allow_any_instance_of(Object).to receive(:which)
          .with("foo", ORIGINAL_PATHS)
          .and_return(Pathname.new("/usr/local/bin/foo"))

        expect(described_class.new(keg_only_f).shadowed_path_text).to be_nil
      end

      it "does not warn when the queried formula itself is not installed" do
        uninstalled_f = formula("foo@old") do
          T.bind(self, T.class_of(Formula))
          url "foo-1.0"
          keg_only :versioned_formula
        end
        Pathname.new(uninstalled_f.opt_bin).mkpath
        FileUtils.touch(uninstalled_f.opt_bin/"foo")
        FileUtils.chmod(0755, uninstalled_f.opt_bin/"foo")

        sibling_keg_bin = HOMEBREW_CELLAR/"foo@2.0/2.0/bin"
        sibling_keg_bin.mkpath
        sibling_shadower = sibling_keg_bin/"foo"
        sibling_shadower.write("#!/bin/sh\n")
        sibling_shadower.chmod(0755)

        allow(uninstalled_f).to receive_messages(versioned_formulae_names: ["foo@2.0"],
                                                 unversioned_formula_name: "foo",
                                                 any_version_installed?:   false)
        allow_any_instance_of(Object).to receive(:which).with("foo", ORIGINAL_PATHS).and_return(sibling_shadower)

        expect(described_class.new(uninstalled_f).shadowed_path_text).to be_nil
      end

      it "warns for a keg-only formula when a sibling keg is linked over it" do
        keg_only_f = formula("foo@1.0") do
          T.bind(self, T.class_of(Formula))
          url "foo-1.0"
          keg_only :versioned_formula
        end
        Pathname.new(keg_only_f.opt_bin).mkpath
        FileUtils.touch(keg_only_f.opt_bin/"foo")
        FileUtils.chmod(0755, keg_only_f.opt_bin/"foo")

        sibling_keg_bin = HOMEBREW_CELLAR/"foo@2.0/2.0/bin"
        sibling_keg_bin.mkpath
        sibling_shadower = sibling_keg_bin/"foo"
        sibling_shadower.write("#!/bin/sh\n")
        sibling_shadower.chmod(0755)

        allow(keg_only_f).to receive_messages(versioned_formulae_names: ["foo@2.0"],
                                              unversioned_formula_name: "foo",
                                              any_version_installed?:   true)
        allow_any_instance_of(Object).to receive(:which).with("foo", ORIGINAL_PATHS).and_return(sibling_shadower)

        text = described_class.new(keg_only_f).shadowed_path_text
        expect(text).to include("linked foo@2.0 commands in #{sibling_shadower.dirname}:\nfoo\n")
        expect(text).to include("Run `brew link foo@1.0`")
      end

      it "warns when a keg-only formula has been linked" do
        keg_only_f = formula do
          T.bind(self, T.class_of(Formula))
          url "foo-1.0"
          keg_only "some reason"
        end
        Pathname.new(keg_only_f.opt_bin).mkpath
        FileUtils.touch(keg_only_f.opt_bin/"foo")
        FileUtils.chmod(0755, keg_only_f.opt_bin/"foo")
        allow(keg_only_f).to receive_messages(linked?: true, any_version_installed?: true)
        shadower = Pathname.new("/usr/local/bin/foo")
        allow_any_instance_of(Object).to receive(:which).with("foo", ORIGINAL_PATHS).and_return(shadower)
        allow(shadower).to receive(:realpath).and_return(shadower)

        expect(described_class.new(keg_only_f).shadowed_path_text)
          .to include("commands in #{shadower.dirname}:\nfoo\n")
      end

      it "does not warn when HOMEBREW_NO_PATH_SHADOW_CHECK is set" do
        shadower = Pathname.new("/usr/local/bin/foo")
        allow_any_instance_of(Object).to receive(:which).with("foo", ORIGINAL_PATHS).and_return(shadower)
        allow(Homebrew::EnvConfig).to receive(:no_path_shadow_check?).and_return(true)

        expect(described_class.new(f).shadowed_path_text).to be_nil
      end

      it "looks up each executable on PATH only once" do
        shadower = Pathname.new("/usr/local/bin/foo")
        allow(shadower).to receive(:realpath).and_return(shadower)
        caveats = described_class.new(f)
        expect(caveats).to receive(:which).with("foo", ORIGINAL_PATHS).once.and_return(shadower)

        caveats.shadowed_path_executables
        caveats.shadowed_path_text
      end

      it "is included in the caveats by default" do
        shadower = Pathname.new("/usr/local/bin/foo")
        allow_any_instance_of(Object).to receive(:which).with("foo", ORIGINAL_PATHS).and_return(shadower)
        allow(shadower).to receive(:realpath).and_return(shadower)

        expect(described_class.new(f).caveats).to include("shadowed by commands in /usr/local/bin:\nfoo\n")
      end

      it "is not included in the caveats when `shadowed_path` is false" do
        shadower = Pathname.new("/usr/local/bin/foo")
        allow_any_instance_of(Object).to receive(:which).with("foo", ORIGINAL_PATHS).and_return(shadower)
        allow(shadower).to receive(:realpath).and_return(shadower)

        expect(described_class.new(f, shadowed_path: false).caveats).not_to include("shadowed")
      end

      it "shows the opt-out hint by default" do
        shadower = Pathname.new("/usr/local/bin/foo")
        allow_any_instance_of(Object).to receive(:which).with("foo", ORIGINAL_PATHS).and_return(shadower)
        allow(shadower).to receive(:realpath).and_return(shadower)

        expect(described_class.new(f).shadowed_path_text).to include("HOMEBREW_NO_PATH_SHADOW_CHECK=1")
      end

      it "hides the opt-out hint when HOMEBREW_NO_ENV_HINTS is set" do
        shadower = Pathname.new("/usr/local/bin/foo")
        allow_any_instance_of(Object).to receive(:which).with("foo", ORIGINAL_PATHS).and_return(shadower)
        allow(shadower).to receive(:realpath).and_return(shadower)
        allow(Homebrew::EnvConfig).to receive(:no_env_hints?).and_return(true)

        expect(described_class.new(f).shadowed_path_text).not_to include("HOMEBREW_NO_PATH_SHADOW_CHECK")
      end

      it "annotates sibling-keg shadowers with the keg name and adds a `brew link` hint" do
        sibling_keg_bin = HOMEBREW_CELLAR/"#{f.name}@1.0/1.0/bin"
        sibling_keg_bin.mkpath
        sibling_shadower = sibling_keg_bin/"foo"
        sibling_shadower.write("#!/bin/sh\n")
        sibling_shadower.chmod(0755)

        allow(f).to receive_messages(versioned_formulae_names: ["#{f.name}@1.0"], unversioned_formula_name: nil)
        allow_any_instance_of(Object).to receive(:which).with("foo", ORIGINAL_PATHS).and_return(sibling_shadower)

        text = described_class.new(f).shadowed_path_text
        expect(text).to include("linked #{f.name}@1.0 commands in #{sibling_shadower.dirname}:\nfoo\n")
        expect(text).to include("Run `brew link #{f.name}`")
        expect(text).not_to include("shadowed by commands")
      end

      it "annotates only the sibling line when shadowers are mixed" do
        Pathname.new(f.opt_bin).mkpath
        FileUtils.touch(f.opt_bin/"bar")
        FileUtils.chmod(0755, f.opt_bin/"bar")

        sibling_keg_bin = HOMEBREW_CELLAR/"#{f.name}@1.0/1.0/bin"
        sibling_keg_bin.mkpath
        sibling_shadower = sibling_keg_bin/"foo"
        sibling_shadower.write("#!/bin/sh\n")
        sibling_shadower.chmod(0755)

        bar_shadower = Pathname.new("/usr/local/bin/bar")
        allow(bar_shadower).to receive(:realpath).and_return(bar_shadower)

        allow(f).to receive_messages(versioned_formulae_names: ["#{f.name}@1.0"], unversioned_formula_name: nil)
        allow_any_instance_of(Object).to receive(:which).with("foo", ORIGINAL_PATHS).and_return(sibling_shadower)
        allow_any_instance_of(Object).to receive(:which).with("bar", ORIGINAL_PATHS).and_return(bar_shadower)

        text = described_class.new(f).shadowed_path_text
        expect(text).to include("linked #{f.name}@1.0 commands in #{sibling_shadower.dirname}:\nfoo\n")
        expect(text).to include("shadowed by commands in #{bar_shadower.dirname}:\nbar\n")
        expect(text).to include("Run `brew link #{f.name}`")
      end
    end

    describe "shell completions" do
      let(:f) do
        formula do
          T.bind(self, T.class_of(Formula))
          url "foo-1.0"
        end
      end
      let(:caveats) { described_class.new(f) }
      let(:path) { Utils::Path.resolved_path(f.prefix) }

      let(:bash_completion_dir) { path/"etc/bash_completion.d" }
      let(:fish_vendor_completions) { path/"share/fish/vendor_completions.d" }
      let(:zsh_site_functions) { path/"share/zsh/site-functions" }
      let(:pwsh_completion_dir) { path/"share/pwsh/completions" }

      before do
        # don't try to load/fetch gcc/glibc
        allow(DevelopmentTools).to receive_messages(needs_libc_formula?: false, needs_compiler_formula?: false)

        allow_any_instance_of(Object).to receive(:which).with(any_args).and_return(Pathname.new("shell"))
        allow(Utils::Shell).to receive_messages(preferred: nil, parent: nil)
      end

      it "includes where Bash completions have been installed to" do
        bash_completion_dir.mkpath
        FileUtils.touch bash_completion_dir/f.name
        expect(caveats.completions_and_elisp.join).to include(HOMEBREW_PREFIX/"etc/bash_completion.d")
      end

      it "includes where fish completions have been installed to" do
        fish_vendor_completions.mkpath
        FileUtils.touch fish_vendor_completions/f.name
        expect(caveats.completions_and_elisp.join).to include(HOMEBREW_PREFIX/"share/fish/vendor_completions.d")
      end

      it "includes where zsh completions have been installed to" do
        zsh_site_functions.mkpath
        FileUtils.touch zsh_site_functions/f.name
        expect(caveats.completions_and_elisp.join).to include(HOMEBREW_PREFIX/"share/zsh/site-functions")
      end

      it "includes where pwsh completions have been installed to" do
        pwsh_completion_dir.mkpath
        FileUtils.touch pwsh_completion_dir/f.name
        expect(caveats.completions_and_elisp.join).to include(HOMEBREW_PREFIX/"share/pwsh/completions")
      end
    end
  end
end
