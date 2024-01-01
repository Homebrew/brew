# frozen_string_literal: true

require "migrator"
require "test/support/fixtures/testball"
require "tab"
require "keg"

describe Migrator do
  subject(:migrator) { described_class.new(new_formula, old_formula.name) }

  let(:new_formula) { Testball.new("newname") }
  let(:old_formula) { Testball.new("oldname") }

  let(:new_keg_record) { HOMEBREW_CELLAR/"newname/0.1" }
  let(:old_keg_record) { HOMEBREW_CELLAR/"oldname/0.1" }

  let(:old_tab) { Tab.empty }

  let(:keg) { Keg.new(old_keg_record) }
  let(:old_pin) { HOMEBREW_PINNED_KEGS/"oldname" }

  before do |example|
    allow(new_formula).to receive(:oldname).and_return("oldname")

    # do not create directories for error tests
    next if example.metadata[:description].start_with?("raises an error")

    (old_keg_record/"bin").mkpath

    %w[inside bindir].each do |file|
      FileUtils.touch old_keg_record/"bin/#{file}"
    end

    old_tab.tabfile = HOMEBREW_CELLAR/"oldname/0.1/INSTALL_RECEIPT.json"
    old_tab.source["path"] = "/oldname"
    old_tab.write

    keg.link
    keg.optlink

    old_pin.make_relative_symlink old_keg_record

    migrator # needs to be evaluated eagerly

    (HOMEBREW_PREFIX/"bin").mkpath
  end

  after do
    keg.unlink if !old_keg_record.parent.symlink? && old_keg_record.directory?

    if new_keg_record.directory?
      new_keg = Keg.new(new_keg_record)
      new_keg.unlink
    end
  end

  describe "::new" do
    it "raises an error if there is no old path" do
      expect do
        described_class.new(new_formula, "oldname")
      end.to raise_error(Migrator::MigratorNoOldpathError)
    end

    it "raises an error if the Taps differ" do
      keg = HOMEBREW_CELLAR/"oldname/0.1"
      keg.mkpath
      tab = Tab.empty
      tab.tabfile = HOMEBREW_CELLAR/"oldname/0.1/INSTALL_RECEIPT.json"
      tab.source["tap"] = "homebrew/core"
      tab.write

      expect do
        described_class.new(new_formula, "oldname")
      end.to raise_error(Migrator::MigratorDifferentTapsError)
    end
  end

  specify "#move_to_new_directory" do
    keg.unlink
    migrator.move_to_new_directory

    expect(new_keg_record).to be_a_directory
    expect(new_keg_record/"bin").to be_a_directory
    expect(new_keg_record/"bin/inside").to be_a_file
    expect(new_keg_record/"bin/bindir").to be_a_file
    expect(old_keg_record).not_to be_a_directory
  end

  specify "#backup_oldname_cellar" do
    old_keg_record.parent.rmtree
    (new_keg_record/"bin").mkpath

    migrator.backup_oldname_cellar

    expect(old_keg_record/"bin").to be_a_directory
    expect(old_keg_record/"bin").to be_a_directory
  end

  specify "#repin" do
    (new_keg_record/"bin").mkpath
    expected_relative = new_keg_record.relative_path_from HOMEBREW_PINNED_KEGS

    migrator.repin

    expect(migrator.new_pin_record).to be_a_symlink
    expect(migrator.new_pin_record.readlink).to eq(expected_relative)
    expect(migrator.old_pin_record).not_to exist
  end

  specify "#unlink_oldname" do
    expect(HOMEBREW_LINKED_KEGS.children.count).to eq(1)
    expect((HOMEBREW_PREFIX/"opt").children.count).to eq(1)

    migrator.unlink_oldname

    expect(HOMEBREW_LINKED_KEGS).not_to exist
    expect(HOMEBREW_LIBRARY/"bin").not_to exist
  end

  specify "#link_newname" do
    keg.unlink
    keg.uninstall

    (new_keg_record/"bin").mkpath
    %w[inside bindir].each do |file|
      FileUtils.touch new_keg_record/"bin"/file
    end

    migrator.link_newname

    expect(HOMEBREW_LINKED_KEGS.children.count).to eq(1)
    expect((HOMEBREW_PREFIX/"opt").children.count).to eq(1)
  end

  specify "#link_oldname_opt" do
    new_keg_record.mkpath
    migrator.link_oldname_opt
    expect((HOMEBREW_PREFIX/"opt/oldname").realpath).to eq(new_keg_record.realpath)
  end

  specify "#link_oldname_cellar" do
    (new_keg_record/"bin").mkpath
    keg.unlink
    keg.uninstall
    migrator.link_oldname_cellar
    expect((HOMEBREW_CELLAR/"oldname").realpath).to eq(new_keg_record.parent.realpath)
  end

  specify "#update_tabs" do
    (new_keg_record/"bin").mkpath
    tab = Tab.empty
    tab.tabfile = HOMEBREW_CELLAR/"newname/0.1/INSTALL_RECEIPT.json"
    tab.source["path"] = "/path/that/must/be/changed/by/update_tabs"
    tab.write
    migrator.update_tabs
    expect(Tab.for_keg(new_keg_record).source["path"]).to eq(new_formula.path.to_s)
  end

  specify "#migrate" do
    tab = Tab.empty
    tab.tabfile = HOMEBREW_CELLAR/"oldname/0.1/INSTALL_RECEIPT.json"
    tab.source["path"] = old_formula.path.to_s
    tab.write

    migrator.migrate

    expect(new_keg_record).to exist
    expect(old_keg_record.parent).to be_a_symlink
    expect(HOMEBREW_LINKED_KEGS/"oldname").not_to exist
    expect((HOMEBREW_LINKED_KEGS/"newname").realpath).to eq(new_keg_record.realpath)
    expect(old_keg_record.realpath).to eq(new_keg_record.realpath)
    expect((HOMEBREW_PREFIX/"opt/oldname").realpath).to eq(new_keg_record.realpath)
    expect((HOMEBREW_CELLAR/"oldname").realpath).to eq(new_keg_record.parent.realpath)
    expect((HOMEBREW_PINNED_KEGS/"newname").realpath).to eq(new_keg_record.realpath)
    expect(Tab.for_keg(new_keg_record).source["path"]).to eq(new_formula.path.to_s)
  end

  specify "#unlinik_oldname_opt" do
    new_keg_record.mkpath
    old_opt_record = HOMEBREW_PREFIX/"opt/oldname"
    old_opt_record.unlink if old_opt_record.symlink?
    old_opt_record.make_relative_symlink(new_keg_record)
    migrator.unlink_oldname_opt
    expect(old_opt_record).not_to be_a_symlink
  end

  specify "#unlink_oldname_cellar" do
    new_keg_record.mkpath
    keg.unlink
    keg.uninstall
    old_keg_record.parent.make_relative_symlink(new_keg_record.parent)
    migrator.unlink_oldname_cellar
    expect(old_keg_record.parent).not_to be_a_symlink
  end

  specify "#backup_oldname_cellar after uninstall" do
    (new_keg_record/"bin").mkpath
    keg.unlink
    keg.uninstall
    migrator.backup_oldname_cellar
    expect(old_keg_record.subdirs).not_to be_empty
  end

  specify "#backup_old_tabs" do
    tab = Tab.empty
    tab.tabfile = HOMEBREW_CELLAR/"oldname/0.1/INSTALL_RECEIPT.json"
    tab.source["path"] = "/should/be/the/same"
    tab.write
    migrator = described_class.new(new_formula, "oldname")
    tab.tabfile.delete
    migrator.backup_old_tabs
    expect(Tab.for_keg(old_keg_record).source["path"]).to eq("/should/be/the/same")
  end

  describe "#backup_oldname" do
    context "when cellar exists" do
      it "backs up the old name" do
        migrator.backup_oldname
        expect(old_keg_record.parent).to be_a_directory
        expect(old_keg_record.parent.subdirs).not_to be_empty
        expect(HOMEBREW_LINKED_KEGS/"oldname").to exist
        expect(HOMEBREW_PREFIX/"opt/oldname").to exist
        expect(HOMEBREW_PINNED_KEGS/"oldname").to be_a_symlink
        expect(keg).to be_linked
      end
    end

    context "when cellar is removed" do
      it "backs up the old name" do
        (new_keg_record/"bin").mkpath
        keg.unlink
        keg.uninstall
        migrator.backup_oldname
        expect(old_keg_record.parent).to be_a_directory
        expect(old_keg_record.parent.subdirs).not_to be_empty
        expect(HOMEBREW_LINKED_KEGS/"oldname").to exist
        expect(HOMEBREW_PREFIX/"opt/oldname").to exist
        expect(HOMEBREW_PINNED_KEGS/"oldname").to be_a_symlink
        expect(keg).to be_linked
      end
    end

    context "when cellar is linked" do
      it "backs up the old name" do
        (new_keg_record/"bin").mkpath
        keg.unlink
        keg.uninstall
        old_keg_record.parent.make_relative_symlink(new_keg_record.parent)
        migrator.backup_oldname
        expect(old_keg_record.parent).to be_a_directory
        expect(old_keg_record.parent.subdirs).not_to be_empty
        expect(HOMEBREW_LINKED_KEGS/"oldname").to exist
        expect(HOMEBREW_PREFIX/"opt/oldname").to exist
        expect(HOMEBREW_PINNED_KEGS/"oldname").to be_a_symlink
        expect(keg).to be_linked
      end
    end
  end
end
