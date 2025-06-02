# frozen_string_literal: true

require "rubocops/checksum"

RSpec.describe RuboCop::Cop::FormulaAudit::ChecksumCase do
  subject(:cop) { described_class.new }

  context "when auditing spec checksums" do
    it "reports an offense if a checksum contains uppercase letters" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          stable do
            url "https://github.com/foo-lang/foo-compiler/archive/0.18.0.tar.gz"
            sha256 "5cf6e1ae0A645b426c0a7cc7cd3f7d1605ffa1ac5756a39a8b2268ddc7ea0e9a"
                             ^ FormulaAudit/ChecksumCase: sha256 should be lowercase

            resource "foo-package" do
              url "https://github.com/foo-lang/foo-package/archive/0.18.0.tar.gz"
              sha256 "5cf6e1Ae0a645b426b047aa4cc7cd3f7d1605ffa1ac5756a39a8b2268ddc7ea9"
                            ^ FormulaAudit/ChecksumCase: sha256 should be lowercase
            end
          end
        end
      RUBY
    end

    it "reports and corrects an offense if a checksum outside a `stable` block contains uppercase letters" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          resource "foo-outside" do
            url "https://github.com/foo-lang/foo-outside/archive/0.18.0.tar.gz"
            sha256 "A4cc7cd3f7d1605ffa1ac5755cf6e1ae0a645b426b047a6a39a8b2268ddc7ea9"
                    ^ FormulaAudit/ChecksumCase: sha256 should be lowercase
          end
          stable do
            url "https://github.com/foo-lang/foo-compiler/archive/0.18.0.tar.gz"
            sha256 "5cf6e1ae0a645b426c0a7cc7cd3f7d1605ffa1ac5756a39a8b2268ddc7ea0e9a"

            resource "foo-package" do
              url "https://github.com/foo-lang/foo-package/archive/0.18.0.tar.gz"
              sha256 "5cf6e1ae0a645b426b047aa4cc7cd3f7d1605ffa1ac5756a39a8b2268ddc7ea9"
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          resource "foo-outside" do
            url "https://github.com/foo-lang/foo-outside/archive/0.18.0.tar.gz"
            sha256 "a4cc7cd3f7d1605ffa1ac5755cf6e1ae0a645b426b047a6a39a8b2268ddc7ea9"
          end
          stable do
            url "https://github.com/foo-lang/foo-compiler/archive/0.18.0.tar.gz"
            sha256 "5cf6e1ae0a645b426c0a7cc7cd3f7d1605ffa1ac5756a39a8b2268ddc7ea0e9a"

            resource "foo-package" do
              url "https://github.com/foo-lang/foo-package/archive/0.18.0.tar.gz"
              sha256 "5cf6e1ae0a645b426b047aa4cc7cd3f7d1605ffa1ac5756a39a8b2268ddc7ea9"
            end
          end
        end
      RUBY
    end
  end
end
