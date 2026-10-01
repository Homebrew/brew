# typed: true
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/generate-advisories-api"

RSpec.describe Homebrew::DevCmd::GenerateAdvisoriesApi do
  it_behaves_like "parseable arguments"

  def record(id, formula, source: nil, range_state: nil, schema_version: "1.7.3")
    affected = { "package" => { "ecosystem" => "Homebrew", "name" => formula } }
    affected["ecosystem_specific"] = { "range_state" => range_state } if range_state
    record = { "schema_version" => schema_version, "id" => id, "affected" => [affected] }
    record["database_specific"] = { "source" => source } if source
    record
  end

  def write_records(directory, records)
    advisories = directory/"advisories"
    advisories.mkpath
    records.each do |filename, body|
      (advisories/filename).write(JSON.generate(body))
    end
  end

  it "writes grouped, filtered, byte-stable advisory data" do
    mktmpdir do |database|
      write_records(database, {
        "z.json" => record("BREW-foo-CVE-2", "foo", source: "matched", range_state: "fixed"),
        "y.json" => record("BREW-foo-CVE-1", "foo", source: "generated"),
        "x.json" => record("BREW-foo-CVE-3", "foo", source: "matched"),
        "w.json" => record("BREW-bar-CVE-1", "bar", source: "matched", range_state: "affected"),
        "v.json" => record("BREW-baz-CVE-1", "baz", source: "matched"),
      })

      mktmpdir do |output|
        output.cd { described_class.new([database.to_s]).run }
        first_output = (output/"api/advisories.json").read
        output.cd { described_class.new([database.to_s]).run }
        second_output = (output/"api/advisories.json").read

        expected = {
          "meta"       => {
            "count"                => 3,
            "skipped_uncomparable" => 2,
            "schema_version"       => "1.7.3",
          },
          "advisories" => {
            "bar" => [record("BREW-bar-CVE-1", "bar", source: "matched", range_state: "affected")],
            "foo" => [
              record("BREW-foo-CVE-1", "foo", source: "generated"),
              record("BREW-foo-CVE-2", "foo", source: "matched", range_state: "fixed"),
            ],
          },
        }
        expected_output = "#{JSON.generate(expected)}\n"
        expect([first_output, second_output]).to eq([expected_output, expected_output])
      end
    end
  end

  it "fails when the advisories directory is missing" do
    mktmpdir do |database|
      mktmpdir do |output|
        expect do
          output.cd { described_class.new([database.to_s]).run }
        end.to raise_error(/is not a directory/)
      end
    end
  end

  it "fails on an empty advisories directory rather than writing an empty index" do
    mktmpdir do |database|
      (database/"advisories").mkpath

      mktmpdir do |output|
        expect do
          output.cd { described_class.new([database.to_s]).run }
        end.to raise_error(/no advisory records found/)
      end
    end
  end

  it "prefixes parse errors with the failing record path" do
    mktmpdir do |database|
      write_records(database, { "good.json" => record("BREW-foo-CVE-1", "foo") })
      (database/"advisories/bad.json").write("{")

      mktmpdir do |output|
        expect do
          output.cd { described_class.new([database.to_s]).run }
        end.to raise_error(%r{advisories/bad\.json})
      end
    end
  end

  it "fails on mixed schema versions" do
    mktmpdir do |database|
      write_records(database, {
        "a.json" => record("a", "foo", schema_version: "1.7.3"),
        "b.json" => record("b", "foo", schema_version: "1.8.0"),
      })

      mktmpdir do |output|
        expect do
          output.cd { described_class.new([database.to_s]).run }
        end.to raise_error(/mixed schema_version.*1\.7\.3.*1\.8\.0/)
      end
    end
  end
end
