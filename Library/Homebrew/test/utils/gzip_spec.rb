# frozen_string_literal: true

require "utils/gzip"

describe Utils::Gzip do
  describe "compress_with_options" do
    it "uses the explicitly specified mtime, orig_name, and output path when passed" do
      mktmpdir do |path|
        mtime = Time.at(12345).utc
        orig_name = "someotherfile"
        output = path/"subdir/anotherfile.gz"
        file_content = "Hello world"
        expected_checksum = "df509051b519faa8a1143157d2750d1694dc5fe6373e493c0d5c360be3e61516"

        somefile = path/"somefile"
        File.write(somefile, file_content)
        mkdir path/"subdir"

        expect(described_class.compress_with_options(somefile, mtime: mtime, orig_name: orig_name,
output: output)).to eq(output)
        expect(Digest::SHA256.hexdigest(File.read(output))).to eq(expected_checksum)
      end
    end

    it "uses SOURCE_DATE_EPOCH as mtime when not explicitly specified" do
      mktmpdir do |path|
        ENV["SOURCE_DATE_EPOCH"] = "23456"
        file_content = "Hello world"
        expected_checksum = "a579be88ec8073391a5753b1df4d87fbf008aaec6b5a03f8f16412e2e01f119a"

        somefile = path/"somefile"
        File.write(somefile, file_content)

        expect(described_class.compress_with_options(somefile).to_s).to eq("#{somefile}.gz")
        expect(Digest::SHA256.hexdigest(File.read("#{somefile}.gz"))).to eq(expected_checksum)
      end
    end
  end

  describe "compress" do
    it "creates non-reproducible gz files from input files" do
      mktmpdir do |path|
        files = (0..2).map { |n| path/"somefile#{n}" }
        FileUtils.touch files

        results = described_class.compress(*files, reproducible: false)
        3.times do |n|
          expect(results[n].to_s).to eq("#{files[n]}.gz")
          expect(Pathname.new("#{files[n]}.gz")).to exist
        end
      end
    end

    it "creates reproducible gz files from input files with explicit mtime" do
      mtime = Time.at(12345).utc
      expected_checksums = %w[
        5b45cabc7f0192854365aeccd82036e482e35131ba39fbbc6d0684266eb2e88a
        d422bf4cbede17ae242135d7f32ba5379fbffb288c29cd38b7e5e1a5f89073f8
        1d93a3808e2bd5d8c6371ea1c9b8b538774d6486af260719400fc3a5b7ac8d6f
      ]

      mktmpdir do |path|
        files = (0..2).map { |n| path/"somefile#{n}" }
        files.each { |f| File.write(f, "Hello world") }

        results = described_class.compress(*files, mtime: mtime)
        3.times do |n|
          expect(results[n].to_s).to eq("#{files[n]}.gz")
          expect(Digest::SHA256.hexdigest(File.read(results[n]))).to eq(expected_checksums[n])
        end
      end
    end

    it "creates reproducible gz files from input files with SOURCE_DATE_EPOCH as mtime" do
      ENV["SOURCE_DATE_EPOCH"] = "23456"
      expected_checksums = %w[
        d5e0cc3259b1eb61d93ee5a30d41aef4a382c1cf2b759719c289f625e27b915c
        068657725bca5f9c2bc62bc6bf679eb63786e92d16cae575dee2fd9787a338f3
        e566e9fdaf9aa2a7c9501f9845fed1b70669bfa679b0de609e3b63f99988784d
      ]

      mktmpdir do |path|
        files = (0..2).map { |n| path/"somefile#{n}" }
        files.each { |f| File.write(f, "Hello world") }

        results = described_class.compress(*files)
        3.times do |n|
          expect(results[n].to_s).to eq("#{files[n]}.gz")
          expect(Digest::SHA256.hexdigest(File.read(results[n]))).to eq(expected_checksums[n])
        end
      end
    end
  end
end
