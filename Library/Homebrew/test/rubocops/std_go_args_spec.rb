# typed: strict
# frozen_string_literal: true

require "rubocops/std_go_args"

RSpec.describe RuboCop::Cop::FormulaAudit::StdGoArgs, :config do
  it "reports GoReleaser metadata inside a staged resource" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        def install
          resource("bar").stage do
            system "go", "build", *std_go_args(ldflags: :goreleaser)
                                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not use `ldflags: :goreleaser` in staged resources; it uses the formula's metadata.
          end
        end
      end
    RUBY
  end

  it "reports GoReleaser metadata when iterating over resources" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        def install
          resources.each do |resource|
            resource.stage do
              system "go", "build", *std_go_args(output: bin/"bar", ldflags: :goreleaser)
                                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not use `ldflags: :goreleaser` in staged resources; it uses the formula's metadata.
            end
          end
        end
      end
    RUBY
  end

  it "reports GoReleaser metadata inside a nested block with an explicit self receiver" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        def install
          resource("bar").stage do
            cd "cmd/bar" do
              system "go", "build", *self.std_go_args(ldflags: :goreleaser)
                                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not use `ldflags: :goreleaser` in staged resources; it uses the formula's metadata.
            end
          end
        end
      end
    RUBY
  end

  it "allows GoReleaser metadata outside staged resources" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        def install
          cd "cmd/foo" do
            system "go", "build", *std_go_args(ldflags: :goreleaser)
          end
        end
      end
    RUBY
  end

  it "allows GoReleaser metadata when staging the formula itself" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        def install
          stage do
            system "go", "build", *std_go_args(ldflags: :goreleaser)
          end
          self.stage do
            system "go", "build", *std_go_args(ldflags: :goreleaser)
          end
        end
      end
    RUBY
  end

  it "allows default and custom linker flags inside staged resources" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        def install
          resource("bar").stage do
            system "go", "build", *std_go_args
            system "go", "build", *std_go_args(ldflags: "-X main.version=1.0")
            system "go", "build", *std_go_args(ldflags: ["-X main.version=1.0"])
          end
        end
      end
    RUBY
  end

  it "ignores another object's Go build arguments inside staged resources" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        def install
          resource("bar").stage do
            system "go", "build", *other.std_go_args(ldflags: :goreleaser)
          end
        end
      end
    RUBY
  end

  it "allows an empty formula" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
      end
    RUBY
  end
end
