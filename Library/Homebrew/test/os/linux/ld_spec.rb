# frozen_string_literal: true

require "os/linux/ld"
require "tmpdir"

RSpec.describe OS::Linux::Ld do
  describe "::library_paths" do
    ld_etc = Pathname("")
    before do
      ld_etc = Pathname(Dir.mktmpdir("homebrew-tests-ld-etc-", Dir.tmpdir))
      FileUtils.mkdir [ld_etc/"subdir1", ld_etc/"subdir2"]
      (ld_etc/"ld.so.conf").write <<~EOS
        # This line is a comment

        include #{ld_etc}/subdir1/*.conf # This is an end-of-line comment, should be ignored

        # subdir2 is an empty directory
        include #{ld_etc}/subdir2/*.conf

        /a/b/c
          /d/e/f # Indentation on this line should be ignored
        /a/b/c # Duplicate entry should be ignored
      EOS

      (ld_etc/"subdir1/1-1.conf").write <<~EOS
        /foo/bar
        /baz/qux
      EOS

      (ld_etc/"subdir1/1-2.conf").write <<~EOS
        /g/h/i
      EOS

      # Empty files (or files containing only whitespace) should be ignored
      (ld_etc/"subdir1/1-3.conf").write "\n\t\n\t\n"
      (ld_etc/"subdir1/1-4.conf").write ""
    end

    after do
      FileUtils.rm_rf ld_etc
    end

    it "parses library paths successfully" do
      expect(described_class.library_paths(ld_etc/"ld.so.conf")).to eq(%w[/foo/bar /baz/qux /g/h/i /a/b/c /d/e/f])
    end
  end
end
