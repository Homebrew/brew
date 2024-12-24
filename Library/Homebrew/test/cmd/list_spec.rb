# frozen_string_literal: true

require "cmd/list"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::List do
  let(:formulae) { %w[bar qux foo] }
  let(:casks) { %w[tex git sgb] }

  it_behaves_like "parseable arguments"

  it "prints all installed Formulae", :integration_test do
    formulae.each do |f|
      (HOMEBREW_CELLAR/f/"1.0/somedir").mkpath
    end
    # casks.each do |f|
    #   (HOMEBREW_CELLAR/"../Caskroom"/f/"42.0/somedir").mkpath
    # end

    expect { brew "list", "--formula" }
      .to output("#{formulae.sort.join("\n")}\n").to_stdout
      .and not_to_output.to_stderr
      .and be_a_success

    # expect { brew "list", "--cask" }
    #   .to output("#{casks.sort.join("\n")}\n").to_stdout
    #   .and not_to_output.to_stderr
    #   .and be_a_success

    expect { brew "list", "--formula", "--version" }
      .to output("#{formulae.sort.map { |name| "#{name} 1.0" }.join("\n")}\n").to_stdout
      .and not_to_output.to_stderr
      .and be_a_success

    # expect { brew "list", "--cask", "--version" }
    #   .to output("#{casks.sort.map { |name| "#{name} 42.0" }.join("\n")}\n").to_stdout
    #   .and not_to_output.to_stderr
    #   .and be_a_success

    # expect { brew "list", "--version" }
    #   .to output("#{formulae.sort.map { |name| "#{name} 1.0" }.join("\n")}\n" +
    #              "#{casks.sort.map { |name| "#{name} 42.0" }.join("\n")}\n").to_stdout
    #   .and not_to_output.to_stderr
    #   .and be_a_success
  end

  # TODO: add a test for the shell fast-path (`brew_sh`)
end
