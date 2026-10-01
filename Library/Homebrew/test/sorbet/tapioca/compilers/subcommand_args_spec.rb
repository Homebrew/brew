# typed: true
# frozen_string_literal: true

require "bundler"
require "tapioca/dsl"

# Tapioca's CLI applies this through its RBS rewriter before loading custom compilers.
Tapioca::Dsl::Compiler.extend(T::Generic)

require "abstract_command"
require "abstract_subcommand"
require "sorbet/tapioca/compilers/args"
require "sorbet/tapioca/compilers/subcommand_args"

RSpec.describe Tapioca::Compilers::SubcommandArgs do
  def decorated_rbi(compiler_class, constant)
    file = RBI::File.new(strictness: "strong")
    pipeline = Tapioca::Dsl::Pipeline.new(requested_constants: [], requested_compilers: [compiler_class])
    compiler_class.new(pipeline, file.root, constant).decorate
    Tapioca::DEFAULT_RBI_FORMATTER.print_file(file)
  end

  before do
    stub_const("TapiocaArgsTestCmd", Class.new(Homebrew::AbstractCommand) do
      cmd_args do
        switch "--global"
        named_args :none
        Homebrew::AbstractSubcommand.define_all(self, command: TapiocaArgsTestCmd)
      end
      def run; end
    end)

    stub_const("TapiocaArgsTestCmd::InstallSubcommand", Class.new(Homebrew::AbstractSubcommand) do
      subcommand_args do
        switch "--force", "--f"
        # `env:`-backed switches still define an accessor when `odisabled`, so this exercises
        # that their subcommand ownership is still recorded (regression test for a real bug).
        switch "--legacy-cleanup", env: :bundle_install_cleanup, odisabled: true
        named_args :none
      end
      def run; end
    end)

    stub_const("TapiocaArgsTestCmd::RemoveSubcommand", Class.new(Homebrew::AbstractSubcommand) do
      subcommand_args do
        switch "--force"
        named_args :none
      end
      def run; end
    end)
  end

  describe Tapioca::Compilers::Args do
    it "limits the command's own `Args` class to command-wide options" do
      output = decorated_rbi(described_class, TapiocaArgsTestCmd)

      expect(output).to include("def global?; end")
      expect(output).not_to include("def force?; end")
      expect(output).not_to include("def f?; end")
      expect(output).not_to include("def legacy_cleanup?; end")
    end
  end

  def subcommand_named(name)
    Homebrew::AbstractSubcommand.subcommands_for(TapiocaArgsTestCmd)
                                .find { |subcommand| subcommand.subcommand_name == name }
  end

  it "scopes a subcommand's `Args` module to its own options, tracking every switch alias" do
    output = decorated_rbi(described_class, subcommand_named("install"))

    expect(output).to include(
      "returns(T.all(TapiocaArgsTestCmd::Args, TapiocaArgsTestCmd::InstallSubcommand::Args))",
    )
    expect(output).to include("module TapiocaArgsTestCmd::InstallSubcommand::Args")
    expect(output).to include("def force?; end")
    expect(output).to include("def f?; end")
    expect(output).not_to include("def global?; end")
  end

  it "scopes a disabled, environment-backed switch to its own subcommand" do
    output = decorated_rbi(described_class, subcommand_named("install"))

    expect(output).to include("def legacy_cleanup?; end")
  end

  it "keeps a sibling subcommand's option aliases off this subcommand's `Args` class" do
    output = decorated_rbi(described_class, subcommand_named("remove"))

    expect(output).to include("def force?; end")
    expect(output).not_to include("def f?; end")
    expect(output).not_to include("def legacy_cleanup?; end")
  end
end
