# typed: true
# frozen_string_literal: true

require "rubocops/install_steps"

RSpec.describe RuboCop::Cop::FormulaAudit::InstallSteps do
  subject(:cop) { RuboCop::Cop::FormulaAudit::InstallSteps.new }

  it "reports an offense when `post_install` and `post_install_steps` are both present" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
        ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: `post_install` and `post_install_steps` cannot both be used.
          touch "foo/state"
        end

        def post_install; end
      end
    RUBY
  end

  it "reports an offense when a steps block contains Ruby code" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          system "true"
          ^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Steps blocks may only contain install step DSL calls: `mkdir`, `mkdir_p`, `touch`, `move`, `mv`, `move_children`, `symlink`, `ln_s`, `ln_sf`.
        end
      end
    RUBY
  end

  it "accepts install step DSL calls" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          mkdir_p "foo"
          touch "foo/state"
          mv "source", "target"
          move_children "source", "target"
          ln_sf "source", "target", source_base: :relative, uninstall: true
        end
      end
    RUBY
  end

  it "autocorrects simple `post_install` file preparation" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        def post_install
        ^^^^^^^^^^^^^^^^ FormulaAudit/InstallSteps: Use `post_install_steps` for simple file preparation.
          (var/"log/foo").mkpath
          FileUtils.touch var/"foo/state"
          FileUtils.mv prefix/"move-source", prefix/"move-target"
          FileUtils.ln_sf "move-target", prefix/"linked-target"
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        post_install_steps do
          mkdir_p "log/foo"
          touch "foo/state"
          mv "move-source", "move-target"
          ln_sf "move-target", "linked-target", source_base: :relative
        end
      end
    RUBY
  end

  it "does not autocorrect non-file preparation in `post_install`" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        def post_install
          system "true"
        end
      end
    RUBY
  end

  it "does not autocorrect mixed `post_install` bodies" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        def post_install
          (var/"log/foo").mkpath
          system "true"
        end
      end
    RUBY
  end
end
