# typed: strict
# frozen_string_literal: true

RSpec.shared_examples "switching users without sudo" do |command_name = nil|
  sig { returns(T::Boolean) }
  let(:macos) { true }

  sig { returns(Pathname) }
  let(:test_root) { mktmpdir }

  sig { returns(T::Hash[String, String]) }
  let(:macos_env) do
    {
      "HOMEBREW_BREW_FILE" => "brew",
      "HOMEBREW_LIBRARY"   => HOMEBREW_LIBRARY_PATH.parent.to_s,
      "HOMEBREW_MACOS"     => macos ? "1" : "",
    }
  end

  sig { params(script: String, env: T::Hash[String, String]).returns([String, String, Process::Status]) }
  def run_as_user_shell(script, env)
    Bundler.with_unbundled_env do
      Open3.capture3(env, "/bin/bash", "-c", script)
    end
  end

  sig { returns(T::Boolean) }
  let(:root) { true }

  sig { returns([String, String, Process::Status]) }
  let(:result) do
    brew_file = test_root/"brew command"
    brew_file.write <<~SH
      #!/bin/bash
      printf '%s\\n' "$USER" "$HOME" "$PWD" "$HOMEBREW_NO_SUDO" "${INHERITED-unset}" "$@"
      exit 42
    SH
    brew_file.chmod(0755)

    uid = root ? 0 : 501
    user = root ? "root" : "operator"
    run_as_user_shell(
      <<~SH,
        source "#{HOMEBREW_LIBRARY_PATH}/cmd/#{command_name}.sh"
        stat() { echo brewer; }
        id() {
          case "$1" in
            -u) echo #{uid} ;;
            -un) echo #{user} ;;
            -P) printf 'brewer:*:503:1234::0:0:Brewer:#{test_root}:/usr/bin/false\\n' ;;
          esac
        }
        getent() { printf 'brewer:x:503:1234:Brewer:#{test_root}:/usr/bin/false\\n'; }
        sudo() { echo unexpected-sudo; return 1; }
        chown() { :; }
        login() {
          [[ "#{macos}" == true && "$1 $2 $3 $4" == '-f -l -q brewer' ]] || return 1
          shift 4
          "$@"
          return 0
        }
        runuser() {
          [[ "#{macos}" == false && "$1 $2 $3" == '-u brewer --' ]] || return 1
          shift 3
          "$@"
        }
        homebrew-#{command_name} list 'argument with spaces' '' '$(exit 1); * "quotes"'
      SH
      macos_env.merge("HOMEBREW_PREFIX" => "/prefix",
                      "HOMEBREW_NO_SUDO" => "1", "HOMEBREW_BREW_FILE" => brew_file.to_s,
                      "INHERITED" => "discard-me"),
    )
  end

  it "switches users without sudo as root" do
    stdout, stderr, status = result

    expect([stdout.lines(chomp: true), stderr, status.exitstatus]).to eq([
      ["brewer", test_root.to_s, Dir.pwd, "1", "unset",
       "list", "argument with spaces", "", '$(exit 1); * "quotes"'],
      "", 42
    ])
  end

  context "when not running as root" do
    sig { returns(T::Boolean) }
    let(:root) { false }

    it "refuses to switch users without sudo" do
      stdout, stderr, status = result

      expect([stdout, stderr, status.exitstatus]).to eq([
        "", "Error: Cannot switch to brewer with sudo disabled. Log in as brewer instead.\n", 1
      ])
    end
  end

  it "keeps using sudo when available to root" do
    stdout, = run_as_user_shell(
      <<~SH,
        source "#{HOMEBREW_LIBRARY_PATH}/cmd/#{command_name}.sh"
        stat() { echo brewer; }
        id() {
          case "$1" in
            -u) echo 0 ;;
            -un) echo root ;;
            -P) printf 'brewer:*:503:1234::0:0:Brewer:#{test_root}:/usr/bin/false\\n' ;;
          esac
        }
        getent() { printf 'brewer:x:503:1234:Brewer:#{test_root}:/usr/bin/false\\n'; }
        sudo() { printf '%s\\n' "$1 $2 $3"; }
        login() { echo unexpected-login; }
        runuser() { echo unexpected-runuser; }
        homebrew-#{command_name} list
      SH
      macos_env.merge("HOMEBREW_NO_SUDO" => ""),
    )

    expect(stdout).to eq("-H -u brewer\n")
  end

  it "preserves the sudo caller and optional routing setting" do
    brew_file = test_root/"brew"
    brew_file.write <<~SH
      #!/bin/bash
      printf '%s\\n' "$SUDO_USER|${HOMEBREW_SUDO_THROUGH_SUDO_USER-unset}|${INHERITED-unset}"
    SH
    brew_file.chmod(0755)

    expect([["", "1"], ["original-user", "1"], ["", ""]].map do |sudo_user, sudo_setting|
      run_as_user_shell(
        <<~SH,
          source "#{HOMEBREW_LIBRARY_PATH}/cmd/#{command_name}.sh"
          stat() { echo brewer; }
          id() {
            [[ "$1" == -un ]] && { echo operator; return; }
            printf 'brewer:*:503:1234::0:0:Brewer:#{test_root}:/bin/bash\\n'
          }
          getent() { printf 'brewer:x:503:1234:Brewer:#{test_root}:/bin/bash\\n'; }
          sudo() { shift 3; "$@"; }
          homebrew-#{command_name} bundle
        SH
        macos_env.merge("HOMEBREW_BREW_FILE"              => brew_file.to_s,
                        "HOMEBREW_SUDO_USER"              => sudo_user,
                        "HOMEBREW_SUDO_THROUGH_SUDO_USER" => sudo_setting,
                        "INHERITED"                       => "discard-me"),
      ).first
    end).to eq(["operator|1|unset\n", "original-user|1|unset\n", "operator|unset|unset\n"])
  end
end
