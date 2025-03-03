# frozen_string_literal: true

require "formula"
require "caveats"

RSpec.describe Caveats do
  subject(:caveats) { described_class.new(f) }

  let(:f) { formula { url "foo-1.0" } }

  specify "#f" do
    expect(caveats.formula).to eq(f)
  end

  describe "#empty?" do
    it "returns true if the Formula has no caveats" do
      expect(caveats).to be_empty
    end

    it "returns false if the Formula has caveats" do
      f = formula do
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
          url "foo-1.0"
          service do
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
          url "foo-1.0"
          service do
            run [bin/"cmd"]
          end
        end
        expect(Utils::Service).to receive(:launchctl?).and_return(false)
        expect(Utils::Service).to receive(:systemctl?).and_return(false)
        expect(described_class.new(f).caveats).to include("service which can only be used on macOS or systemd!")
      end

      it "prints service startup information when service.require_root is true" do
        f = formula do
          url "foo-1.0"
          service do
            run [bin/"cmd"]
            require_root true
          end
        end
        expect(Utils::Service).to receive(:running?).with(f).once.and_return(false)
        expect(described_class.new(f).caveats).to include("startup")
      end

      it "prints service login information" do
        f = formula do
          url "foo-1.0"
          service do
            run [bin/"cmd"]
          end
        end
        expect(Utils::Service).to receive(:running?).with(f).once.and_return(false)
        expect(described_class.new(f).caveats).to include("restart at login")
      end

      it "gives information about require_root restarting services after upgrade" do
        f = formula do
          url "foo-1.0"
          service do
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
          url "foo-1.0"
          service do
            run [bin/"cmd"]
          end
        end
        f_obj = described_class.new(f)
        expect(Utils::Service).to receive(:running?).with(f).once.and_return(true)
        expect(f_obj.caveats).to include("  brew services restart #{f.full_name}")
      end

      it "gives information about require_root starting services after upgrade" do
        f = formula do
          url "foo-1.0"
          service do
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
          url "foo-1.0"
          service do
            run [bin/"cmd"]
          end
        end
        f_obj = described_class.new(f)
        expect(Utils::Service).to receive(:running?).with(f).once.and_return(false)
        expect(f_obj.caveats).to include("  brew services start #{f.full_name}")
      end

      it "gives information about service manual command" do
        f = formula do
          url "foo-1.0"
          service do
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
          url "foo-1.0"
          service do
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
          url "foo-1.0"
          keg_only "some reason"
        end
      end
      let(:caveats) { described_class.new(f).caveats }

      it "tells formula is keg_only" do
        expect(caveats).to include("keg-only")
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
            url "foo-1.0"
            keg_only "some reason"

            def caveats
              "something else"
            end

            service do
              run [bin/"cmd"]
            end
          end
        end

        let(:caveats) { described_class.new(f).caveats }

        it "adds the correct amount of new lines to the output" do
          expect(Utils::Service).to receive(:launchctl?).at_least(:once).and_return(true)
          expect(caveats).to include("something else")
          expect(caveats).to include("keg-only")
          expect(caveats).to include("if you don't want/need a background service")
          expect(caveats.count("\n")).to eq(9)
        end
      end
    end

    describe "shell completions" do
      let(:f) do
        formula do
          url "foo-1.0"
        end
      end
      let(:caveats) { described_class.new(f).caveats }
      let(:path) { f.prefix.resolved_path }

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
        expect(caveats).to include(HOMEBREW_PREFIX/"etc/bash_completion.d")
      end

      it "includes where fish completions have been installed to" do
        fish_vendor_completions.mkpath
        FileUtils.touch fish_vendor_completions/f.name
        expect(caveats).to include(HOMEBREW_PREFIX/"share/fish/vendor_completions.d")
      end

      it "includes where zsh completions have been installed to" do
        zsh_site_functions.mkpath
        FileUtils.touch zsh_site_functions/f.name
        expect(caveats).to include(HOMEBREW_PREFIX/"share/zsh/site-functions")
      end

      it "includes where pwsh completions have been installed to" do
        pwsh_completion_dir.mkpath
        FileUtils.touch pwsh_completion_dir/f.name
        expect(caveats).to include(HOMEBREW_PREFIX/"share/pwsh/completions")
      end
    end
  end
end
