# typed: strict

class RSpec::Core::ExampleGroup
  include CopHelper
  include RSpec::SharedContext
  include RSpec::Matchers
  include RSpec::Mocks::ExampleMethods
  include RuboCop::RSpec::ExpectOffense

  # These methods are added to specs in
  # `test/support/helper/spec/shared_context/integration_test.rb`; declare them
  # here so Sorbet can resolve them in typed spec files.
  sig { params(args: T.untyped).returns(Process::Status) }
  def brew(*args); end

  sig { params(args: T.untyped).returns(Process::Status) }
  def brew_sh(*args); end

  sig {
    params(
      name:           String,
      content:        T.nilable(String),
      tap:            Tap,
      bottle_block:   T.nilable(String),
      tab_attributes: T.nilable(T::Hash[T.untyped, T.untyped]),
    ).returns(Pathname)
  }
  def setup_test_formula(name, content = T.unsafe(nil), tap: T.unsafe(nil), bottle_block: T.unsafe(nil),
                         tab_attributes: T.unsafe(nil))
  end

  sig { returns(Pathname) }
  def setup_test_tap; end

  sig { params(name: String, content: T.nilable(String), build_bottle: T::Boolean).void }
  def install_test_formula(name, content = T.unsafe(nil), build_bottle: false); end

  sig { params(old_name: String, new_name: String).void }
  def install_and_rename_coretap_formula(old_name, new_name); end

  sig { params(name: String).void }
  def uninstall_test_formula(name); end

  # These methods are mixed into specs via
  # `config.include(Test::Helper::{Formula,Cask})` in `test/spec_helper.rb`;
  # declare them here so Sorbet can resolve them in typed spec files.
  sig {
    params(
      name: String, path: T.nilable(Pathname), spec: Symbol, alias_path: T.nilable(Pathname),
      tap: T.nilable(Tap), block: T.nilable(T.proc.bind(Formula).void)
    ).returns(::Formula)
  }
  def formula(name = T.unsafe(nil), path: nil, spec: :stable, alias_path: nil, tap: nil, &block); end

  sig { params(formula: ::Formula, ref: T.nilable(String), call_original: T::Boolean).void }
  def stub_formula_loader(formula, ref = formula.full_name, call_original: false); end

  sig { params(cask: Cask::Cask, ref: T.nilable(String), call_original: T::Boolean).void }
  def stub_cask_loader(cask, ref = cask.token, call_original: false); end

  # `mktmpdir` is mixed into specs via `config.include(Test::Helper::MkTmpDir)`
  # in `test/spec_helper.rb`; declare it here so Sorbet can resolve it in typed
  # spec files.
  sig {
    type_parameters(:U)
      .params(
        prefix_suffix: T.nilable(T.any(String, T::Array[String])),
        block:         T.proc.params(path: Pathname).returns(T.type_parameter(:U)),
      ).returns(T.type_parameter(:U))
  }
  sig {
    params(
      prefix_suffix: T.nilable(T.any(String, T::Array[String])),
      block:         T.nilable(T.proc.params(path: Pathname).returns(Pathname)),
    ).returns(Pathname)
  }
  def mktmpdir(prefix_suffix = T.unsafe(nil), &block); end

  # These methods are mixed into specs via
  # `config.include(Test::Helper::Subcommand)` in `test/spec_helper.rb`;
  # declare them here so Sorbet can resolve them in typed spec files.
  sig {
    params(
      subcommand: T.nilable(T.any(String, Symbol)),
      named:      T.untyped,
      options:    T.untyped,
    ).returns(Test::Helper::Subcommand::Args)
  }
  def args_for_subcommand(subcommand = T.unsafe(nil), *named, **options); end

  sig {
    params(
      subcommand:   T.any(String, Symbol),
      global:       T::Boolean,
      file:         T.nilable(String),
      no_upgrade:   T::Boolean,
      verbose:      T::Boolean,
      force:        T::Boolean,
      ask:          T::Boolean,
      jobs:         Integer,
      zap:          T::Boolean,
      no_type_args: T::Boolean,
    ).returns(Homebrew::Cmd::Bundle::SubcommandContext)
  }
  def bundle_subcommand_context(subcommand, global: false, file: nil, no_upgrade: false, verbose: false,
                                force: false, ask: false, jobs: 1, zap: false, no_type_args: true)
  end

  # These methods are mixed into specs via
  # `config.include(Test::Helper::Fixtures)` in `test/spec_helper.rb`;
  # declare them here so Sorbet can resolve them in typed spec files.
  sig { params(name: String).returns(MachOShim) }
  def dylib_path(name); end

  sig { params(name: String).returns(MachOShim) }
  def bundle_path(name); end

  sig { params(name: String).returns(Pathname) }
  def cask_path(name); end

  sig { params(name: String).returns(Pathname) }
  def tarball_fixture(name); end

  sig { params(name: String).returns(String) }
  def tarball_fixture_sha256(name); end

  sig { params(name: String).returns(Pathname) }
  def patch_fixture(name); end

  sig { params(name: String).returns(String) }
  def patch_fixture_sha256(name); end

  sig { params(name: String).returns(Pathname) }
  def fixture(name); end

  # `formula(...) { ... }` helper blocks can be inferred as example group
  # contexts in typed specs; declare Formula DSL methods to satisfy static
  # analysis.
  sig { params(val: String, specs: T::Hash[Symbol, T.anything]).returns(String) }
  def url(val = "", specs = {}); end
end

# `formula(...) { ... }` helper blocks can be inferred as this helper module in
# typed specs; declare Formula DSL methods to satisfy static analysis.
module Test::Helper::Formula
  sig { params(val: String, specs: T::Hash[Symbol, T.anything]).returns(String) }
  def url(val = "", specs = {}); end
end

# Some helper blocks are inferred as Formula instances or class contexts.
class Formula
  sig { params(reason: T.any(String, Symbol), explanation: String).void }
  def keg_only(reason, explanation = ""); end

  sig { params(val: String, specs: T::Hash[Symbol, T.anything]).returns(String) }
  def url(val = "", specs = {}); end

  sig { params(paths: T.any(String, Symbol)).returns(T::Set[T.any(String, Symbol)]) }
  def skip_clean(*paths); end
end

# The rspec-mocks RBI defines `ExpectHost#expect(target)` with a required
# argument and no block, which conflicts with the block form `expect { ... }`
# required by matchers like `raise_error`, `output`, `change`, etc.
# Override it to match the rspec-expectations signature.
module RSpec::Mocks::ExampleMethods::ExpectHost
  sig { params(value: T.untyped, block: T.nilable(T.proc.void)).returns(T.untyped) }
  def expect(value = T.unsafe(nil), &block); end
end

# RuboCop cop specs include this helper at runtime via `rubocop/rspec/support`.
module CopHelper
  sig { params(source: String, file: T.untyped).returns(T::Array[T.untyped]) }
  def inspect_source(source, file = T.unsafe(nil)); end

  sig { params(source: String, file: T.untyped).returns(String) }
  def autocorrect_source(source, file = T.unsafe(nil)); end

  sig { params(source: String).returns(String) }
  def autocorrect_source_file(source); end

  sig { params(source: String, file: T.untyped).returns(T.untyped) }
  def parse_source(source, file = T.unsafe(nil)); end
end
