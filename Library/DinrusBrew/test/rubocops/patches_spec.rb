# frozen_string_literal: true

require "rubocops/patches"

RSpec.describe RuboCop::Cop::FormulaAudit::Patches do
  subject(:cop) { described_class.new }

  def expect_offense_hash(message:, severity:, line:, column:, source:)
    [{ message:, severity:, line:, column:, source: }]
  end

  context "when auditing legacy patches" do
    it "reports no offenses if there is no legacy patch" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
        end
      RUBY
    end

    it "reports an offense if `def patches` is present" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          homepage "ftp://brew.sh/foo"
          url "https://brew.sh/foo-1.0.tgz"
          def patches
          ^^^^^^^^^^^ FormulaAudit/Patches: Use the patch DSL instead of defining a 'patches' method
            DATA
          end
        end
      RUBY
    end

    it "reports an offense for various patch URLs" do
      patch_urls = [
        "https://raw.github.com/mogaal/sendemail",
        "https://mirrors.ustc.edu.cn/macports/trunk/",
        "http://trac.macports.org/export/102865/trunk/dports/mail/uudeview/files/inews.c.patch",
        "http://bugs.debian.org/cgi-bin/bugreport.cgi?msg=5;filename=patch-libunac1.txt;att=1;bug=623340",
        "https://patch-diff.githubusercontent.com/raw/foo/foo-bar/pull/100.patch",
        "https://github.com/dlang/dub/commit/2c916b1a7999a050ac4970c3415ff8f91cd487aa.patch",
      ]
      patch_urls.each do |patch_url|
        source = <<~EOS
          class Foo < Formula
            homepage "ftp://brew.sh/foo"
            url "https://brew.sh/foo-1.0.tgz"
            def patches
              "#{patch_url}"
            end
          end
        EOS

        expected_offense = if patch_url.include?("/raw.github.com/")
          expect_offense_hash(message: <<~EOS.chomp, severity: :convention, line: 5, column: 4, source:)
            FormulaAudit/Patches: GitHub/Gist patches should specify a revision: #{patch_url}
          EOS
        elsif patch_url.include?("macports/trunk")
          expect_offense_hash(message: <<~EOS.chomp, severity: :convention, line: 5, column: 4, source:)
            FormulaAudit/Patches: MacPorts patches should specify a revision instead of trunk: #{patch_url}
          EOS
        elsif patch_url.start_with?("http://trac.macports.org/")
          expect_offense_hash(message: <<~EOS.chomp, severity: :convention, line: 5, column: 4, source:)
            FormulaAudit/Patches: Patches from MacPorts Trac should be https://, not http: #{patch_url}
          EOS
        elsif patch_url.start_with?("http://bugs.debian.org/")
          expect_offense_hash(message: <<~EOS.chomp, severity: :convention, line: 5, column: 4, source:)
            FormulaAudit/Patches: Patches from Debian should be https://, not http: #{patch_url}
          EOS
        # GitHub patch diff regexps can't be any shorter.
        # rubocop:disable Layout/LineLength
        elsif patch_url.match?(%r{https?://patch-diff\.githubusercontent\.com/raw/(.+)/(.+)/pull/(.+)\.(?:diff|patch)})
          # rubocop:enable Layout/LineLength
          expect_offense_hash(message: <<~EOS.chomp, severity: :convention, line: 5, column: 4, source:)
            FormulaAudit/Patches: Use a commit hash URL rather than patch-diff: #{patch_url}
          EOS
        elsif patch_url.match?(%r{https?://github\.com/.+/.+/(?:commit|pull)/[a-fA-F0-9]*.(?:patch|diff)})
          expect_offense_hash(message: <<~EOS.chomp, severity: :convention, line: 5, column: 4, source:)
            FormulaAudit/Patches: GitHub patches should use the full_index parameter: #{patch_url}?full_index=1
          EOS
        end
        expected_offense.zip([inspect_source(source).last]).each do |expected, actual|
          expect(actual.message).to eq(expected[:message])
          expect(actual.severity).to eq(expected[:severity])
          expect(actual.line).to eq(expected[:line])
          expect(actual.column).to eq(expected[:column])
        end
      end
    end

    it "reports an offense with nested `def patches`" do
      source = <<~RUBY
        class Foo < Formula
          homepage "ftp://brew.sh/foo"
          url "https://brew.sh/foo-1.0.tgz"
          def patches
            files = %w[patch-domain_resolver.c patch-colormask.c patch-trafshow.c patch-trafshow.1 patch-configure]
            {
              :p0 =>
              files.collect{|p| "http://trac.macports.org/export/68507/trunk/dports/net/trafshow/files/\#{p}"}
            }
          end
        end
      RUBY

      expected_offenses = [
        {
          message:  "FormulaAudit/Patches: Use the patch DSL instead of defining a 'patches' method",
          severity: :convention,
          line:     4,
          column:   2,
          source:,
        }, {
          message:  "FormulaAudit/Patches: Patches from MacPorts Trac should be https://, not http: " \
                    "http://trac.macports.org/export/68507/trunk/dports/net/trafshow/files/",
          severity: :convention,
          line:     8,
          column:   25,
          source:,
        }
      ]

      expected_offenses.zip(inspect_source(source)).each do |expected, actual|
        expect(actual.message).to eq(expected[:message])
        expect(actual.severity).to eq(expected[:severity])
        expect(actual.line).to eq(expected[:line])
        expect(actual.column).to eq(expected[:column])
      end
    end
  end

  context "when auditing inline patches" do
    it "reports no offenses for valid inline patches" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          patch :DATA
        end
        __END__
        patch content here
      RUBY
    end

    it "reports no offenses for valid nested inline patches" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          stable do
            patch :DATA
          end
        end
        __END__
        patch content here
      RUBY
    end

    it "reports an offense when DATA is found with no __END__" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          patch :DATA
          ^^^^^^^^^^^ FormulaAudit/Patches: patch is missing '__END__'
        end
      RUBY
    end

    it "reports an offense when __END__ is found with no DATA" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
        end
        __END__
        ^^^^^^^ FormulaAudit/Patches: patch is missing 'DATA'
        patch content here
      RUBY
    end
  end

  context "when auditing external patches" do
    it "reports an offense for various patch URLs" do
      patch_urls = [
        "https://raw.github.com/mogaal/sendemail",
        "https://mirrors.ustc.edu.cn/macports/trunk/",
        "http://trac.macports.org/export/102865/trunk/dports/mail/uudeview/files/inews.c.patch",
        "http://bugs.debian.org/cgi-bin/bugreport.cgi?msg=5;filename=patch-libunac1.txt;att=1;bug=623340",
        "https://patch-diff.githubusercontent.com/raw/foo/foo-bar/pull/100.patch",
        "https://github.com/uber/h3/pull/362.patch?full_index=1",
        "https://gitlab.gnome.org/GNOME/gitg/-/merge_requests/142.diff",
        "https://github.com/michaeldv/pit/commit/f64978d.diff?full_index=1",
        "https://gitlab.gnome.org/GNOME/msitools/commit/248450a.patch",
      ]
      patch_urls.each do |patch_url|
        source = <<~RUBY
          class Foo < Formula
            homepage "ftp://brew.sh/foo"
            url "https://brew.sh/foo-1.0.tgz"
            patch do
              url "#{patch_url}"
              sha256 "63376b8fdd6613a91976106d9376069274191860cd58f039b29ff16de1925621"
            end
          end
        RUBY

        expected_offense = if patch_url.include?("/raw.github.com/")
          expect_offense_hash(message: <<~EOS.chomp, severity: :convention, line: 5, column: 8, source:)
            FormulaAudit/Patches: GitHub/Gist patches should specify a revision: #{patch_url}
          EOS
        elsif patch_url.include?("macports/trunk")
          expect_offense_hash(message: <<~EOS.chomp, severity: :convention, line: 5, column: 8, source:)
            FormulaAudit/Patches: MacPorts patches should specify a revision instead of trunk: #{patch_url}
          EOS
        elsif patch_url.start_with?("http://trac.macports.org/")
          expect_offense_hash(message: <<~EOS.chomp, severity: :convention, line: 5, column: 8, source:)
            FormulaAudit/Patches: Patches from MacPorts Trac should be https://, not http: #{patch_url}
          EOS
        elsif patch_url.start_with?("http://bugs.debian.org/")
          expect_offense_hash(message: <<~EOS.chomp, severity: :convention, line: 5, column: 8, source:)
            FormulaAudit/Patches: Patches from Debian should be https://, not http: #{patch_url}
          EOS
        elsif patch_url.match?(%r{https://github.com/[^/]*/[^/]*/pull})
          expect_offense_hash(message: <<~EOS.chomp, severity: :convention, line: 5, column: 8, source:)
            FormulaAudit/Patches: Use a commit hash URL rather than an unstable pull request URL: #{patch_url}
          EOS
        elsif patch_url.match?(%r{.*gitlab.*/merge_request.*})
          expect_offense_hash(message: <<~EOS.chomp, severity: :convention, line: 5, column: 8, source:)
            FormulaAudit/Patches: Use a commit hash URL rather than an unstable merge request URL: #{patch_url}
          EOS
        elsif patch_url.match?(%r{https://github.com/[^/]*/[^/]*/commit/})
          expect_offense_hash(message: <<~EOS.chomp, severity: :convention, line: 5, column: 8, source:)
            FormulaAudit/Patches: GitHub patches should end with .patch, not .diff: #{patch_url}
          EOS
        elsif patch_url.match?(%r{.*gitlab.*/commit/})
          expect_offense_hash(message: <<~EOS.chomp, severity: :convention, line: 5, column: 8, source:)
            FormulaAudit/Patches: GitLab patches should end with .diff, not .patch: #{patch_url}
          EOS
        # GitHub patch diff regexps can't be any shorter.
        # rubocop:disable Layout/LineLength
        elsif patch_url.match?(%r{https?://patch-diff\.githubusercontent\.com/raw/(.+)/(.+)/pull/(.+)\.(?:diff|patch)})
          # rubocop:enable Layout/LineLength
          expect_offense_hash(message: <<~EOS.chomp, severity: :convention, line: 5, column: 8, source:)
            FormulaAudit/Patches: Use a commit hash URL rather than patch-diff: #{patch_url}
          EOS
        end
        expected_offense.zip([inspect_source(source).last]).each do |expected, actual|
          expect(actual.message).to eq(expected[:message])
          expect(actual.severity).to eq(expected[:severity])
          expect(actual.line).to eq(expected[:line])
          expect(actual.column).to eq(expected[:column])
        end
      end
    end
  end
end
