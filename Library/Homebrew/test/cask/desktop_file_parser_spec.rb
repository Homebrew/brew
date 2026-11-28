# typed: true
# frozen_string_literal: true

require "cask/desktop_file_parser"

RSpec.describe Cask::DesktopFileParser do
  subject(:desktop_file) { described_class.new(contents) }

  let(:contents) do
    <<~'EOS'
      # A comment
      [Desktop Entry]
      Type=Application
      Name = Foo
      Name[de]=Foo DE
      Exec=foo %U
      Comment=Back\\slash and\sspace

      [Desktop Action new]
      Name=New
      Exec=foo --new
    EOS
  end

  describe "#desktop_entry?" do
    it "is true when the first group is `[Desktop Entry]`" do
      expect(desktop_file.desktop_entry?).to be(true)
    end

    describe "when another group comes first" do
      let(:contents) { "[Foo]\n[Desktop Entry]\n" }

      it "is false" do
        expect(desktop_file.desktop_entry?).to be(false)
      end
    end
  end

  describe "#get" do
    it "ignores spaces around `=`" do
      expect(desktop_file.get("Name")).to eq("Foo")
    end

    it "reads localised keys separately" do
      expect(desktop_file.get("Name[de]")).to eq("Foo DE")
    end

    it "resolves escape sequences" do
      expect(desktop_file.get("Comment")).to eq("Back\\slash and space")
    end

    it "reads only from the `[Desktop Entry]` group" do
      expect(described_class.new("[Desktop Action new]\nIcon=foo\n").get("Icon")).to be_nil
    end
  end

  describe "#update" do
    it "replaces the key in every group, keeping comments and layout" do
      desktop_file.update("Exec") { |exec| "#{exec} --bar" }

      expect(desktop_file.to_s).to eq(contents.sub("foo %U", "foo %U --bar").sub("foo --new", "foo --new --bar"))
    end

    it "escapes the value" do
      desktop_file.update("Comment") { "a\\b\nc" }

      expect(desktop_file.to_s).to include("Comment=a\\\\b\\nc\n")
    end
  end

  describe "#replace_program" do
    subject(:replaced_exec) do
      desktop_file.replace_program(environment: { "X" => "1" }) { program }
      desktop_file.get("Exec")
    end

    let(:contents) { "[Desktop Entry]\nExec=#{embedded_exec}\n" }
    let(:embedded_exec) { "AppRun" }
    let(:program) { "/A/Foo.AppImage" }

    describe "when it sets variables with `env`" do
      let(:embedded_exec) { "env GDK_BACKEND=x11 UBUNTU_MENUPROXY=0 audacity %F" }

      it "keeps them" do
        expect(replaced_exec).to eq("env X=1 GDK_BACKEND=x11 UBUNTU_MENUPROXY=0 /A/Foo.AppImage %F")
      end
    end

    describe "when it sets variables with an absolute `env`" do
      let(:embedded_exec) { "/usr/bin/env GDK_BACKEND=x11 audacity %F" }

      it "keeps them" do
        expect(replaced_exec).to eq("env X=1 GDK_BACKEND=x11 /A/Foo.AppImage %F")
      end
    end

    describe "when it sets variables without `env`" do
      let(:embedded_exec) { "LD_LIBRARY_PATH=usr/lib clashmi %u" }

      it "sets them with `env`" do
        expect(replaced_exec).to eq("env X=1 LD_LIBRARY_PATH=usr/lib /A/Foo.AppImage %u")
      end
    end

    describe "when its program is quoted" do
      let(:embedded_exec) { "'Foo Bar' --flag %U" }

      it "replaces the whole program" do
        expect(replaced_exec).to eq("env X=1 /A/Foo.AppImage --flag %U")
      end
    end

    describe "when it sets a variable from the environment among others" do
      let(:embedded_exec) { "env FOO=1 X=0 BAR=2 AppRun %U" }

      it "replaces only that variable" do
        expect(replaced_exec).to eq("env X=1 FOO=1 BAR=2 /A/Foo.AppImage %U")
      end
    end

    describe "when the program has reserved characters" do
      let(:program) { "/A/My $Apps/Foo%.AppImage" }

      it "quotes it and escapes its percent sign" do
        expect(replaced_exec).to eq('env X=1 "/A/My \$Apps/Foo%%.AppImage"')
      end
    end

    describe "when no variables are set" do
      subject(:replaced_exec) do
        desktop_file.replace_program { |embedded_program| "/A/bin/#{embedded_program}" }
        desktop_file.get("Exec")
      end

      let(:embedded_exec) { "audacity %F" }

      it "points it at the program for the one it names without `env`" do
        expect(replaced_exec).to eq("/A/bin/audacity %F")
      end
    end

    describe "when it has an unmatched quote" do
      let(:embedded_exec) { 'AppRun "--flag' }

      it "raises" do
        expect { replaced_exec }.to raise_error(ArgumentError)
      end
    end

    describe "when there is a `TryExec`" do
      let(:contents) { "[Desktop Entry]\nTryExec=AppRun\n" }

      it "points it at the program for the one it names" do
        desktop_file.replace_program { |embedded_program| "/A/bin/#{embedded_program}" }

        expect(desktop_file.get("TryExec")).to eq("/A/bin/AppRun")
      end
    end
  end
end
