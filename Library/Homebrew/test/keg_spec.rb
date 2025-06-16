# frozen_string_literal: true

require "keg"
require "stringio"

RSpec.describe Keg do
  include FileUtils

  def setup_test_keg(name, version)
    path = HOMEBREW_CELLAR/name/version
    (path/"bin").mkpath

    %w[hiworld helloworld goodbye_cruel_world].each do |file|
      touch path/"bin"/file
    end

    keg = described_class.new(path)
    kegs << keg
    keg
  end

  let(:dst) { HOMEBREW_PREFIX/"bin"/"helloworld" }
  let(:nonexistent) { Pathname.new("/some/nonexistent/path") }
  let!(:keg) { setup_test_keg("foo", "1.0") }
  let(:kegs) { [] }

  before do
    (HOMEBREW_PREFIX/"bin").mkpath
    (HOMEBREW_PREFIX/"lib").mkpath
  end

  after do
    kegs.each(&:unlink)
    rmtree HOMEBREW_PREFIX/"lib"
  end

  specify "::all" do
    expect(described_class.all).to eq([keg])
  end

  specify "#empty_installation?" do
    %w[.DS_Store INSTALL_RECEIPT.json LICENSE.txt].each do |file|
      touch keg/file
    end

    expect(keg).to exist
    expect(keg).to be_a_directory
    expect(keg).not_to be_an_empty_installation

    FileUtils.rm_r(keg/"bin")
    expect(keg).to be_an_empty_installation

    (keg/"bin").mkpath
    touch keg.join("bin", "todo")
    expect(keg).not_to be_an_empty_installation
  end

  specify "#oldname_opt_records" do
    expect(keg.oldname_opt_records).to be_empty
    oldname_opt_record = HOMEBREW_PREFIX/"opt/oldfoo"
    oldname_opt_record.make_relative_symlink(HOMEBREW_CELLAR/"foo/1.0")
    expect(keg.oldname_opt_records).to eq([oldname_opt_record])
  end

  specify "#remove_oldname_opt_records" do
    oldname_opt_record = HOMEBREW_PREFIX/"opt/oldfoo"
    oldname_opt_record.make_relative_symlink(HOMEBREW_CELLAR/"foo/2.0")
    keg.remove_oldname_opt_records
    expect(oldname_opt_record).to be_a_symlink
    oldname_opt_record.unlink
    oldname_opt_record.make_relative_symlink(HOMEBREW_CELLAR/"foo/1.0")
    keg.remove_oldname_opt_records
    expect(oldname_opt_record).not_to be_a_symlink
  end

  describe "#link" do
    it "links a Keg" do
      expect(keg.link).to eq(3)
      (HOMEBREW_PREFIX/"bin").children.each do |c|
        expect(c.readlink).to be_relative
      end
    end

    context "with dry run set to true" do
      let(:options) { { dry_run: true } }

      it "only prints what would be done" do
        expect do
          expect(keg.link(**options)).to eq(0)
        end.to output(<<~EOF).to_stdout
          #{HOMEBREW_PREFIX}/bin/goodbye_cruel_world
          #{HOMEBREW_PREFIX}/bin/helloworld
          #{HOMEBREW_PREFIX}/bin/hiworld
        EOF

        expect(keg).not_to be_linked
      end
    end

    it "fails when already linked" do
      keg.link

      expect { keg.link }.to raise_error(Keg::AlreadyLinkedError)
    end

    it "fails when files exist" do
      touch dst

      expect { keg.link }.to raise_error(Keg::ConflictError)
    end

    it "ignores broken symlinks at target" do
      src = keg/"bin"/"helloworld"
      dst.make_symlink(nonexistent)
      keg.link
      expect(dst.readlink).to eq(src.relative_path_from(dst.dirname))
    end

    context "with overwrite set to true" do
      let(:options) { { overwrite: true } }

      it "overwrite existing files" do
        touch dst
        expect(keg.link(**options)).to eq(3)
        expect(keg).to be_linked
      end

      it "overwrites broken symlinks" do
        dst.make_symlink "nowhere"
        expect(keg.link(**options)).to eq(3)
        expect(keg).to be_linked
      end

      it "still supports dryrun" do
        touch dst

        options[:dry_run] = true

        expect do
          expect(keg.link(**options)).to eq(0)
        end.to output(<<~EOF).to_stdout
          #{dst}
        EOF

        expect(keg).not_to be_linked
      end
    end

    it "also creates an opt link" do
      expect(keg).not_to be_optlinked
      keg.link
      expect(keg).to be_optlinked
    end

    specify "pkgconfig directory is created" do
      link = HOMEBREW_PREFIX/"lib"/"pkgconfig"
      (keg/"lib"/"pkgconfig").mkpath
      keg.link
      expect(link.lstat).to be_a_directory
    end

    specify "cmake directory is created" do
      link = HOMEBREW_PREFIX/"lib"/"cmake"
      (keg/"lib"/"cmake").mkpath
      keg.link
      expect(link.lstat).to be_a_directory
    end

    specify "symlinks are linked directly" do
      link = HOMEBREW_PREFIX/"lib"/"pkgconfig"

      (keg/"lib"/"example").mkpath
      (keg/"lib"/"pkgconfig").make_symlink "example"
      keg.link

      expect(link.resolved_path).to be_a_symlink
      expect(link.lstat).to be_a_symlink
    end
  end

  describe "#unlink" do
    it "unlinks a Keg" do
      keg.link
      expect(dst).to be_a_symlink
      expect(keg.unlink).to eq(3)
      expect(dst).not_to be_a_symlink
    end

    it "prunes empty top-level directories" do
      mkpath HOMEBREW_PREFIX/"lib/foo/bar"
      mkpath keg/"lib/foo/bar"
      touch keg/"lib/foo/bar/file1"

      keg.unlink

      expect(HOMEBREW_PREFIX/"lib/foo").not_to be_a_directory
    end

    it "ignores .DS_Store when pruning empty directories" do
      mkpath HOMEBREW_PREFIX/"lib/foo/bar"
      touch HOMEBREW_PREFIX/"lib/foo/.DS_Store"
      mkpath keg/"lib/foo/bar"
      touch keg/"lib/foo/bar/file1"

      keg.unlink

      expect(HOMEBREW_PREFIX/"lib/foo").not_to be_a_directory
      expect(HOMEBREW_PREFIX/"lib/foo/.DS_Store").not_to exist
    end

    it "doesn't remove opt link" do
      keg.link
      keg.unlink
      expect(keg).to be_optlinked
    end

    it "preverves broken symlinks pointing outside the Keg" do
      keg.link
      dst.delete
      dst.make_symlink(nonexistent)
      keg.unlink
      expect(dst).to be_a_symlink
    end

    it "preverves broken symlinks pointing into the Keg" do
      keg.link
      dst.resolved_path.delete
      keg.unlink
      expect(dst).to be_a_symlink
    end

    it "preverves symlinks pointing outside the Keg" do
      keg.link
      dst.delete
      dst.make_symlink(Pathname.new("/bin/sh"))
      keg.unlink
      expect(dst).to be_a_symlink
    end

    it "preserves real files" do
      keg.link
      dst.delete
      touch dst
      keg.unlink
      expect(dst).to be_a_file
    end

    it "ignores nonexistent file" do
      keg.link
      dst.delete
      expect(keg.unlink).to eq(2)
    end

    it "doesn't remove links to symlinks" do
      a = HOMEBREW_CELLAR/"a"/"1.0"
      b = HOMEBREW_CELLAR/"b"/"1.0"

      (a/"lib"/"example").mkpath
      (a/"lib"/"example2").make_symlink "example"
      (b/"lib"/"example2").mkpath

      a = described_class.new(a)
      b = described_class.new(b)
      a.link

      lib = HOMEBREW_PREFIX/"lib"
      expect(lib.children.length).to eq(2)
      expect { b.link }.to raise_error(Keg::ConflictError)
      expect(lib.children.length).to eq(2)
    end

    # This is a legacy violation that would benefit from a clear expectation.
    # rubocop:disable RSpec/NoExpectationExample
    it "removes broken symlinks that conflict with directories" do
      a = HOMEBREW_CELLAR/"a"/"1.0"
      (a/"lib"/"foo").mkpath

      keg = described_class.new(a)

      link = HOMEBREW_PREFIX/"lib"/"foo"
      link.parent.mkpath
      link.make_symlink(nonexistent)

      keg.link
    end
    # rubocop:enable RSpec/NoExpectationExample
  end

  describe "#optlink" do
    it "creates an opt link" do
      oldname_opt_record = HOMEBREW_PREFIX/"opt/oldfoo"
      oldname_opt_record.make_relative_symlink(HOMEBREW_CELLAR/"foo/1.0")
      keg_record = HOMEBREW_CELLAR/"foo"/"2.0"
      (keg_record/"bin").mkpath
      keg = described_class.new(keg_record)
      keg.optlink
      expect(keg_record).to eq(oldname_opt_record.resolved_path)
      keg.uninstall
      expect(oldname_opt_record).not_to be_a_symlink
    end

    it "doesn't fail if already opt-linked" do
      keg.opt_record.make_relative_symlink Pathname.new(keg)
      keg.optlink
      expect(keg).to be_optlinked
    end

    it "replaces an existing directory" do
      keg.opt_record.mkpath
      keg.optlink
      expect(keg).to be_optlinked
    end

    it "replaces an existing file" do
      keg.opt_record.parent.mkpath
      keg.opt_record.write("foo")
      keg.optlink
      expect(keg).to be_optlinked
    end
  end

  specify "#link and #unlink" do
    expect(keg).not_to be_linked
    keg.link
    expect(keg).to be_linked
    keg.unlink
    expect(keg).not_to be_linked
  end
end
