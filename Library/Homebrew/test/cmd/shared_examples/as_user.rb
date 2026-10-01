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

    run_as_user_shell(
      <<~SH,
        source "#{HOMEBREW_LIBRARY_PATH}/cmd/#{command_name}.sh"
        stat() { echo brewer; }
        id() {
          case "$1" in
            -u) echo #{root ? 0 : 501} ;;
            -un) echo #{root ? "root" : "operator"} ;;
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
      ["brewer", test_root.to_s, test_root.to_s, "1", "unset",
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
end
