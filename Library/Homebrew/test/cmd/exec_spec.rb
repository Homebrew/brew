# typed: true
# frozen_string_literal: true

require "cmd/exec"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Exec do
  it_behaves_like "parseable arguments"

  describe "exec" do
    let(:formula_name) { "test-executable" }
    let(:executable_name) { "test-executable-tool" }
    let(:shell_cellar) do
      if (HOMEBREW_LIBRARY_PATH.parent.parent/"Cellar").directory?
        HOMEBREW_LIBRARY_PATH.parent.parent/"Cellar"
      else
        HOMEBREW_CELLAR
      end
    end
    let(:db) { HOMEBREW_CACHE/"api/internal/executables.txt" }
    let(:active_executable) { shell_cellar/"#{formula_name}/2.10/bin/#{executable_name}" }
    let(:env_formula_name) { "test-env" }
    let(:env_executable_name) { "test-env-tool" }
    let(:env_executable) { shell_cellar/"#{env_formula_name}/1.0/bin/#{env_executable_name}" }
    let(:installable_formula_name) { "test-installable" }
    let(:installable_executable_name) { "test-installable-tool" }
    let(:brew_wrapper) { HOMEBREW_TEMP/"brew-exec-wrapper/brew" }
    let(:inline_script) { HOMEBREW_TEMP/"brew-exec-wrapper/script.sh" }
    let(:brew_sh_env) do
      {
        "HOMEBREW_BREW_SH"               => (HOMEBREW_PREFIX/"bin/brew").to_s,
        "HOMEBREW_FORCE_BREW_WRAPPER"    => brew_wrapper.to_s,
        "HOMEBREW_NO_FORCE_BREW_WRAPPER" => "1",
        "HOMEBREW_TEMP"                  => HOMEBREW_TEMP.to_s,
        "HOMEBREW_COLOR"                 => nil,
        "GITHUB_ACTIONS"                 => nil,
      }
    end

    before do
      FileUtils.ln_sf HOMEBREW_LIBRARY_PATH.parent.parent/"bin/brew", HOMEBREW_PREFIX/"bin/brew"

      db.dirname.mkpath
      db.write(<<~EOS)
        test-uninstalled(1.0.0):#{executable_name}
        #{formula_name}(1.0.0):#{executable_name}
        #{installable_formula_name}(1.0.0):#{installable_executable_name}
      EOS

      old_executable = shell_cellar/"#{formula_name}/2.9/bin/#{executable_name}"
      old_executable.dirname.mkpath
      old_executable.write("#!/bin/sh\necho old-version\n")
      FileUtils.chmod 0755, old_executable

      active_executable.dirname.mkpath
      active_executable.write("#!/bin/sh\necho active-version \"$@\"\n")
      FileUtils.chmod 0755, active_executable

      (HOMEBREW_PREFIX/"opt").mkpath
      FileUtils.ln_sf active_executable.dirname.parent, HOMEBREW_PREFIX/"opt/#{formula_name}"

      env_executable.dirname.mkpath
      env_executable.write("#!/bin/sh\necho env-version \"$@\"\n")
      FileUtils.chmod 0755, env_executable
      FileUtils.ln_sf env_executable.dirname.parent, HOMEBREW_PREFIX/"opt/#{env_formula_name}"

      linked_executable = HOMEBREW_PREFIX/"bin/#{executable_name}"
      linked_executable.write("#!/bin/sh\necho linked-provider\n")
      FileUtils.chmod 0755, linked_executable

      brew_wrapper.dirname.mkpath
      inline_script.write(<<~SH)
        #!/bin/sh
        #{executable_name} "$@"
        #{env_executable_name} "$@"
      SH
      FileUtils.chmod 0755, inline_script

      brew_wrapper.write(<<~SH)
        #!/bin/sh
        case "$1" in
          deps)
            exit 0
            ;;
          install)
            echo fake install stdout
            echo fake install stderr >&2
            mkdir -p "#{shell_cellar}/#{installable_formula_name}/1.0.0/bin" "#{HOMEBREW_PREFIX}/opt"
            cat > "#{shell_cellar}/#{installable_formula_name}/1.0.0/bin/#{installable_executable_name}" <<'EOS'
        #!/bin/sh
        echo installable-version "$@"
        EOS
            chmod 755 "#{shell_cellar}/#{installable_formula_name}/1.0.0/bin/#{installable_executable_name}"
            ln -sfn "#{shell_cellar}/#{installable_formula_name}/1.0.0" "#{HOMEBREW_PREFIX}/opt/#{installable_formula_name}"
            ;;
          *)
            echo "unexpected brew wrapper call: $*" >&2
            exit 1
            ;;
        esac
      SH
      FileUtils.chmod 0755, brew_wrapper
    end

    after do
      FileUtils.rm_rf shell_cellar/formula_name
      FileUtils.rm_rf shell_cellar/env_formula_name
      FileUtils.rm_rf shell_cellar/installable_formula_name
      FileUtils.rm_rf HOMEBREW_PREFIX/"opt/#{formula_name}"
      FileUtils.rm_rf HOMEBREW_PREFIX/"opt/#{env_formula_name}"
      FileUtils.rm_rf HOMEBREW_PREFIX/"opt/#{installable_formula_name}"
      FileUtils.rm_f HOMEBREW_PREFIX/"bin/#{executable_name}"
      FileUtils.rm_rf brew_wrapper.dirname
    end

    it "runs commands in formula environments and supports the x alias", :aggregate_failures, :integration_test do
      expect do
        expect(brew_sh("exec", executable_name, "arg", brew_sh_env)).to be_a_success
      end.to(
        output("active-version arg\n").to_stdout
          .and(output("").to_stderr),
      )

      expect do
        expect(brew_sh("x", executable_name, brew_sh_env)).to be_a_success
      end.to(
        output("active-version\n").to_stdout
          .and(output("").to_stderr),
      )

      expect do
        expect(brew_sh("exec", "--formulae=#{formula_name}, #{env_formula_name}", "--", inline_script.to_s, "arg",
                       brew_sh_env)).to be_a_success
      end.to(
        output("active-version arg\nenv-version arg\n").to_stdout
          .and(output("").to_stderr),
      )

      expect do
        expect(brew_sh("exec", "--formulae=", executable_name, brew_sh_env)).to be_a_failure
      end.to(
        output("").to_stdout
          .and(output("Error: `--formulae` requires a comma-separated formula list.\n").to_stderr),
      )

      expect do
        expect(brew_sh("exec", "--sandbox=", executable_name, brew_sh_env)).to be_a_failure
      end.to(
        output("").to_stdout
          .and(output("Error: `--sandbox` requires a writable path.\n").to_stderr),
      )

      expect do
        expect(brew_sh("exec", installable_executable_name, "arg",
                       brew_sh_env)).to be_a_success
      end.to(
        output("installable-version arg\n").to_stdout
          .and(
            output(
              "==> Installing `#{installable_formula_name}` because it provides " \
              "`#{installable_executable_name}`.\n" \
              "fake install stdout\n" \
              "fake install stderr\n",
            ).to_stderr,
          ),
      )
    end
  end
end
