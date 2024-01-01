# frozen_string_literal: true

require "completions"

describe Homebrew::Completions do
  let(:completions_dir) { HOMEBREW_REPOSITORY/"completions" }
  let(:internal_path) { HOMEBREW_REPOSITORY/"Library/Taps/homebrew/homebrew-bar" }
  let(:external_path) { HOMEBREW_REPOSITORY/"Library/Taps/foo/homebrew-bar" }

  before do
    HOMEBREW_REPOSITORY.cd do
      system "git", "init"
    end
    described_class::SHELLS.each do |shell|
      (completions_dir/shell).mkpath
    end
    internal_path.mkpath
    external_path.mkpath
  end

  after do
    FileUtils.rm_rf completions_dir
    FileUtils.rm_rf internal_path
    FileUtils.rm_rf external_path.dirname
  end

  context "when linking or unlinking completions" do
    def setup_completions(external:)
      internal_bash_completion = internal_path/"completions/bash"
      external_bash_completion = external_path/"completions/bash"

      internal_bash_completion.mkpath
      (internal_bash_completion/"foo_internal").write "#foo completions"
      if external
        external_bash_completion.mkpath
        (external_bash_completion/"foo_external").write "#foo completions"
      elsif (external_bash_completion/"foo_external").exist?
        (external_bash_completion/"foo_external").delete
      end
    end

    def setup_completions_setting(state, setting: "linkcompletions")
      HOMEBREW_REPOSITORY.cd do
        system "git", "config", "--replace-all", "homebrew.#{setting}", state.to_s
      end
    end

    def read_completions_setting(setting: "linkcompletions")
      HOMEBREW_REPOSITORY.cd do
        Utils.popen_read("git", "config", "--get", "homebrew.#{setting}").chomp.presence
      end
    end

    def delete_completions_setting(setting: "linkcompletions")
      HOMEBREW_REPOSITORY.cd do
        system "git", "config", "--unset-all", "homebrew.#{setting}"
      end
    end

    describe ".link!" do
      it "sets homebrew.linkcompletions to true" do
        setup_completions_setting false
        expect { described_class.link! }.not_to raise_error
        expect(read_completions_setting).to eq "true"
      end

      it "sets homebrew.linkcompletions to true if unset" do
        delete_completions_setting
        expect { described_class.link! }.not_to raise_error
        expect(read_completions_setting).to eq "true"
      end

      it "keeps homebrew.linkcompletions set to true" do
        setup_completions_setting true
        expect { described_class.link! }.not_to raise_error
        expect(read_completions_setting).to eq "true"
      end
    end

    describe ".unlink!" do
      it "sets homebrew.linkcompletions to false" do
        setup_completions_setting true
        expect { described_class.unlink! }.not_to raise_error
        expect(read_completions_setting).to eq "false"
      end

      it "sets homebrew.linkcompletions to false if unset" do
        delete_completions_setting
        expect { described_class.unlink! }.not_to raise_error
        expect(read_completions_setting).to eq "false"
      end

      it "keeps homebrew.linkcompletions set to false" do
        setup_completions_setting false
        expect { described_class.unlink! }.not_to raise_error
        expect(read_completions_setting).to eq "false"
      end
    end

    describe ".link_completions?" do
      it "returns true if homebrew.linkcompletions is true" do
        setup_completions_setting true
        expect(described_class.link_completions?).to be true
      end

      it "returns false if homebrew.linkcompletions is false" do
        setup_completions_setting false
        expect(described_class.link_completions?).to be false
      end

      it "returns false if homebrew.linkcompletions is not set" do
        expect(described_class.link_completions?).to be false
      end
    end

    describe ".completions_to_link?" do
      it "returns false if only internal taps have completions" do
        setup_completions external: false
        expect(described_class.completions_to_link?).to be false
      end

      it "returns true if external taps have completions" do
        setup_completions external: true
        expect(described_class.completions_to_link?).to be true
      end
    end

    describe ".show_completions_message_if_needed" do
      it "doesn't show the message if there are no completions to link" do
        setup_completions external: false
        delete_completions_setting setting: :completionsmessageshown
        expect { described_class.show_completions_message_if_needed }.not_to output.to_stdout
      end

      it "doesn't show the message if there are completions to link but the message has already been shown" do
        setup_completions external: true
        setup_completions_setting true, setting: :completionsmessageshown
        expect { described_class.show_completions_message_if_needed }.not_to output.to_stdout
      end

      it "shows the message if there are completions to link and the message hasn't already been shown" do
        setup_completions external: true
        delete_completions_setting setting: :completionsmessageshown

        message = /Homebrew completions for external commands are unlinked by default!/
        expect { described_class.show_completions_message_if_needed }
          .to output(message).to_stdout
      end
    end
  end

  context "when generating completions" do
    describe ".update_shell_completions!" do
      it "generates shell completions" do
        described_class.update_shell_completions!
        expect(completions_dir/"bash/brew").to be_a_file
      end
    end

    describe ".format_description" do
      it "escapes single quotes" do
        expect(described_class.format_description("Homebrew's")).to eq "Homebrew'\\''s"
      end

      it "escapes single quotes for fish" do
        expect(described_class.format_description("Homebrew's", fish: true)).to eq "Homebrew\\'s"
      end

      it "removes angle brackets" do
        expect(described_class.format_description("<formula>")).to eq "formula"
      end

      it "replaces newlines with spaces" do
        expect(described_class.format_description("Homebrew\ncommand")).to eq "Homebrew command"
      end

      it "removes trailing period" do
        expect(described_class.format_description("Homebrew.")).to eq "Homebrew"
      end
    end

    describe ".command_options" do
      it "returns an array of options for a ruby command" do
        expected_options = {
          "--debug"   => "Display any debugging information.",
          "--help"    => "Show this message.",
          "--hide"    => "Act as if none of the specified <hidden> are installed. <hidden> should be " \
                         "a comma-separated list of formulae.",
          "--quiet"   => "Make some output more quiet.",
          "--verbose" => "Make some output more verbose.",
        }
        expect(described_class.command_options("missing")).to eq expected_options
      end

      it "returns an array of options for a shell command" do
        expected_options = {
          "--auto-update" => "Run on auto-updates (e.g. before `brew install`). Skips some slower steps.",
          "--debug"       => "Display a trace of all shell commands as they are executed.",
          "--force"       => "Always do a slower, full update check (even if unnecessary).",
          "--help"        => "Show this message.",
          "--merge"       => "Use `git merge` to apply updates (rather than `git rebase`).",
          "--quiet"       => "Make some output more quiet.",
          "--verbose"     => "Print the directories checked and `git` operations performed.",
        }
        expect(described_class.command_options("update")).to eq expected_options
      end

      it "handles --[no]- options correctly" do
        options = described_class.command_options("audit")
        expect(options.key?("--signing")).to be true
        expect(options.key?("--no-signing")).to be true
        expect(options["--signing"] == options["--no-signing"]).to be true
      end

      it "return an empty array if command is not found" do
        expect(described_class.command_options("foobar")).to eq({})
      end

      it "return an empty array for a command with no options" do
        expect(described_class.command_options("help")).to eq({})
      end

      it "will override global options with local descriptions" do
        options = described_class.command_options("upgrade")
        expect(options["--verbose"]).to eq "Print the verification and post-install steps."
      end
    end

    describe ".command_gets_completions?" do
      it "returns true for a non-cask command with options" do
        expect(described_class.command_gets_completions?("install")).to be true
      end

      it "returns false for a non-cask command with no options" do
        expect(described_class.command_gets_completions?("help")).to be false
      end

      it "returns false for a cask command" do
        expect(described_class.command_gets_completions?("cask install")).to be false
      end
    end

    describe ".generate_bash_subcommand_completion" do
      it "returns nil if completions aren't needed" do
        expect(described_class.generate_bash_subcommand_completion("help")).to be_nil
      end

      it "returns appropriate completion for a ruby command" do
        completion = described_class.generate_bash_subcommand_completion("missing")
        expect(completion).to eq <<~COMPLETION
          _brew_missing() {
            local cur="${COMP_WORDS[COMP_CWORD]}"
            case "${cur}" in
              -*)
                __brewcomp "
                --debug
                --help
                --hide
                --quiet
                --verbose
                "
                return
                ;;
              *) ;;
            esac
            __brew_complete_formulae
          }
        COMPLETION
      end

      it "returns appropriate completion for a shell command" do
        completion = described_class.generate_bash_subcommand_completion("update")
        expect(completion).to eq <<~COMPLETION
          _brew_update() {
            local cur="${COMP_WORDS[COMP_CWORD]}"
            case "${cur}" in
              -*)
                __brewcomp "
                --auto-update
                --debug
                --force
                --help
                --merge
                --quiet
                --verbose
                "
                return
                ;;
              *) ;;
            esac
          }
        COMPLETION
      end

      it "returns appropriate completion for a command with multiple named arg types" do
        completion = described_class.generate_bash_subcommand_completion("upgrade")
        expect(completion).to match(/__brew_complete_outdated_formulae\n  __brew_complete_outdated_casks\n}$/)
      end
    end

    describe ".generate_bash_completion_file" do
      it "returns the correct completion file" do
        file = described_class.generate_bash_completion_file(%w[install missing update])
        expect(file).to match(/^__brewcomp\(\) {$/)
        expect(file).to match(/^_brew_install\(\) {$/)
        expect(file).to match(/^_brew_missing\(\) {$/)
        expect(file).to match(/^_brew_update\(\) {$/)
        expect(file).to match(/^_brew\(\) {$/)
        expect(file).to match(/^ {4}install\) _brew_install ;;/)
        expect(file).to match(/^ {4}missing\) _brew_missing ;;/)
        expect(file).to match(/^ {4}update\) _brew_update ;;/)
        expect(file).to match(/^complete -o bashdefault -o default -F _brew brew$/)
      end
    end

    describe ".generate_zsh_subcommand_completion" do
      it "returns nil if completions aren't needed" do
        expect(described_class.generate_zsh_subcommand_completion("help")).to be_nil
      end

      it "returns appropriate completion for a ruby command" do
        completion = described_class.generate_zsh_subcommand_completion("missing")
        expect(completion).to eq <<~COMPLETION
          # brew missing
          _brew_missing() {
            _arguments \\
              '--debug[Display any debugging information]' \\
              '--help[Show this message]' \\
              '--hide[Act as if none of the specified hidden are installed. hidden should be a comma-separated list of formulae]' \\
              '--quiet[Make some output more quiet]' \\
              '--verbose[Make some output more verbose]' \\
              - formula \\
              '*::formula:__brew_formulae'
          }
        COMPLETION
      end

      it "returns appropriate completion for a shell command" do
        completion = described_class.generate_zsh_subcommand_completion("update")
        expect(completion).to eq <<~COMPLETION
          # brew update
          _brew_update() {
            _arguments \\
              '--auto-update[Run on auto-updates (e.g. before `brew install`). Skips some slower steps]' \\
              '--debug[Display a trace of all shell commands as they are executed]' \\
              '--force[Always do a slower, full update check (even if unnecessary)]' \\
              '--help[Show this message]' \\
              '--merge[Use `git merge` to apply updates (rather than `git rebase`)]' \\
              '--quiet[Make some output more quiet]' \\
              '--verbose[Print the directories checked and `git` operations performed]'
          }
        COMPLETION
      end

      it "returns appropriate completion for a command with multiple named arg types" do
        completion = described_class.generate_zsh_subcommand_completion("livecheck")
        expect(completion).to match(
          /'*::formula:__brew_formulae'/,
        )
        expect(completion).to match(
          /'*::cask:__brew_casks'\n}$/,
        )
      end
    end

    describe ".generate_zsh_completion_file" do
      it "returns the correct completion file" do
        file = described_class.generate_zsh_completion_file(%w[install missing update])
        expect(file).to match(/^__brew_list_aliases\(\) {$/)
        expect(file).to match(/^    up update$/)
        expect(file).to match(/^__brew_internal_commands\(\) {$/)
        expect(file).to match(/^    'install:Install a formula or cask'$/)
        expect(file).to match(/^    'missing:Check the given formula kegs for missing dependencies'$/)
        expect(file).to match(/^    'update:Fetch the newest version of Homebrew and all formulae from GitHub .*'$/)
        expect(file).to match(/^_brew_install\(\) {$/)
        expect(file).to match(/^_brew_missing\(\) {$/)
        expect(file).to match(/^_brew_update\(\) {$/)
        expect(file).to match(/^_brew "\$@"$/)
      end
    end

    describe ".generate_fish_subcommand_completion" do
      it "returns nil if completions aren't needed" do
        expect(described_class.generate_fish_subcommand_completion("help")).to be_nil
      end

      it "returns appropriate completion for a ruby command" do
        completion = described_class.generate_fish_subcommand_completion("missing")
        expect(completion).to eq <<~COMPLETION
          __fish_brew_complete_cmd 'missing' 'Check the given formula kegs for missing dependencies'
          __fish_brew_complete_arg 'missing' -l debug -d 'Display any debugging information'
          __fish_brew_complete_arg 'missing' -l help -d 'Show this message'
          __fish_brew_complete_arg 'missing' -l hide -d 'Act as if none of the specified hidden are installed. hidden should be a comma-separated list of formulae'
          __fish_brew_complete_arg 'missing' -l quiet -d 'Make some output more quiet'
          __fish_brew_complete_arg 'missing' -l verbose -d 'Make some output more verbose'
          __fish_brew_complete_arg 'missing' -a '(__fish_brew_suggest_formulae_all)'
        COMPLETION
      end

      it "returns appropriate completion for a shell command" do
        completion = described_class.generate_fish_subcommand_completion("update")
        expect(completion).to eq <<~COMPLETION
          __fish_brew_complete_cmd 'update' 'Fetch the newest version of Homebrew and all formulae from GitHub using `git`(1) and perform any necessary migrations'
          __fish_brew_complete_arg 'update' -l auto-update -d 'Run on auto-updates (e.g. before `brew install`). Skips some slower steps'
          __fish_brew_complete_arg 'update' -l debug -d 'Display a trace of all shell commands as they are executed'
          __fish_brew_complete_arg 'update' -l force -d 'Always do a slower, full update check (even if unnecessary)'
          __fish_brew_complete_arg 'update' -l help -d 'Show this message'
          __fish_brew_complete_arg 'update' -l merge -d 'Use `git merge` to apply updates (rather than `git rebase`)'
          __fish_brew_complete_arg 'update' -l quiet -d 'Make some output more quiet'
          __fish_brew_complete_arg 'update' -l verbose -d 'Print the directories checked and `git` operations performed'
        COMPLETION
      end

      it "returns appropriate completion for a command with multiple named arg types" do
        completion = described_class.generate_fish_subcommand_completion("upgrade")
        expected_line_start = "__fish_brew_complete_arg 'upgrade; and not __fish_seen_argument"
        expect(completion).to match(
          /#{expected_line_start} -l cask -l casks' -a '\(__fish_brew_suggest_formulae_outdated\)'/,
        )
        expect(completion).to match(
          /#{expected_line_start} -l formula -l formulae' -a '\(__fish_brew_suggest_casks_outdated\)'/,
        )
      end
    end

    describe ".generate_fish_completion_file" do
      it "returns the correct completion file" do
        file = described_class.generate_fish_completion_file(%w[install missing update])
        expect(file).to match(/^function __fish_brew_complete_cmd/)
        expect(file).to match(/^__fish_brew_complete_cmd 'install' 'Install a formula or cask'$/)
        expect(file).to match(/^__fish_brew_complete_cmd 'missing' 'Check the given formula kegs for .*'$/)
        expect(file).to match(/^__fish_brew_complete_cmd 'update' 'Fetch the newest version of Homebrew .*'$/)
      end
    end
  end
end
