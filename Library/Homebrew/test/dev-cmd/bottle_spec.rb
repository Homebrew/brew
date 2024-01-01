# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/bottle"

describe "brew bottle" do
  it_behaves_like "parseable arguments"

  it "builds a bottle for the given Formula", :integration_test do
    install_test_formula "testball", build_bottle: true

    # `brew bottle` should not fail with dead symlink
    # https://github.com/Homebrew/legacy-homebrew/issues/49007
    (HOMEBREW_CELLAR/"testball/0.1").cd do
      FileUtils.ln_s "not-exist", "symlink"
    end

    begin
      expect { brew "bottle", "--no-rebuild", "testball" }
        .to output(/testball--0\.1.*\.bottle\.tar\.gz/).to_stdout
        .and not_to_output.to_stderr
        .and be_a_success
      expect(HOMEBREW_CELLAR/"testball-bottle.tar").not_to exist
    ensure
      FileUtils.rm_f Dir.glob("testball--0.1*.bottle.tar.gz")
    end
  end

  describe "--merge", :integration_test do
    let(:core_tap) { CoreTap.new }
    let(:tarball) do
      if OS.linux?
        TEST_FIXTURE_DIR/"tarballs/testball-0.1-linux.tbz"
      else
        TEST_FIXTURE_DIR/"tarballs/testball-0.1.tbz"
      end
    end

    before do
      Pathname("#{TEST_TMPDIR}/testball-1.0.arm64_big_sur.bottle.json").write stub_hash(
        name:           "testball",
        version:        "1.0",
        path:           "#{core_tap.path}/Formula/testball.rb",
        cellar:         "any_skip_relocation",
        os:             "arm64_big_sur",
        filename:       "testball-1.0.arm64_big_sur.bottle.tar.gz",
        local_filename: "testball--1.0.arm64_big_sur.bottle.tar.gz",
        sha256:         "8f9aecd233463da6a4ea55f5f88fc5841718c013f3e2a7941350d6130f1dc149",
      )

      Pathname("#{TEST_TMPDIR}/testball-1.0.big_sur.bottle.json").write stub_hash(
        name:           "testball",
        version:        "1.0",
        path:           "#{core_tap.path}/Formula/testball.rb",
        cellar:         "any_skip_relocation",
        os:             "big_sur",
        filename:       "hello-1.0.big_sur.bottle.tar.gz",
        local_filename: "hello--1.0.big_sur.bottle.tar.gz",
        sha256:         "a0af7dcbb5c83f6f3f7ecd507c2d352c1a018f894d51ad241ce8492fa598010f",
      )

      Pathname("#{TEST_TMPDIR}/testball-1.0.catalina.bottle.json").write stub_hash(
        name:           "testball",
        version:        "1.0",
        path:           "#{core_tap.path}/Formula/testball.rb",
        cellar:         "any_skip_relocation",
        os:             "catalina",
        filename:       "testball-1.0.catalina.bottle.tar.gz",
        local_filename: "testball--1.0.catalina.bottle.tar.gz",
        sha256:         "5334dd344986e46b2aa4f0471cac7b0914bd7de7cb890a34415771788d03f2ac",
      )
    end

    after do
      FileUtils.rm_f "#{TEST_TMPDIR}/testball-1.0.arm64_big_sur.bottle.json"
      FileUtils.rm_f "#{TEST_TMPDIR}/testball-1.0.catalina.bottle.json"
      FileUtils.rm_f "#{TEST_TMPDIR}/testball-1.0.big_sur.bottle.json"
    end

    it "adds the bottle block to a formula that has none" do
      core_tap.path.cd do
        system "git", "-c", "init.defaultBranch=master", "init"
        setup_test_formula "testball"
        system "git", "add", "--all"
        system "git", "commit", "-m", "testball 0.1"
      end

      # RuboCop would align the `.and` with `.to_stdout` which is too floaty.
      # rubocop:disable Layout/MultilineMethodCallIndentation
      expect do
        brew "bottle",
             "--merge",
             "--write",
             "#{TEST_TMPDIR}/testball-1.0.arm64_big_sur.bottle.json",
             "#{TEST_TMPDIR}/testball-1.0.big_sur.bottle.json",
             "#{TEST_TMPDIR}/testball-1.0.catalina.bottle.json"
      end.to output(Regexp.new(<<~'EOS')).to_stdout
        ==> testball
          bottle do
            sha256 cellar: :any_skip_relocation, arm64_big_sur: "8f9aecd233463da6a4ea55f5f88fc5841718c013f3e2a7941350d6130f1dc149"
            sha256 cellar: :any_skip_relocation, big_sur:       "a0af7dcbb5c83f6f3f7ecd507c2d352c1a018f894d51ad241ce8492fa598010f"
            sha256 cellar: :any_skip_relocation, catalina:      "5334dd344986e46b2aa4f0471cac7b0914bd7de7cb890a34415771788d03f2ac"
          end
        \[master [0-9a-f]{4,40}\] testball: add 1\.0 bottle\.
         1 file changed, 6 insertions\(\+\)
      EOS
      .and not_to_output.to_stderr
      .and be_a_success
      # rubocop:enable Layout/MultilineMethodCallIndentation

      expect((core_tap.path/"Formula/testball.rb").read).to eq <<~EOS
        class Testball < Formula
          desc "Some test"
          homepage "https://brew.sh/testball"
          url "file://#{tarball}"
          sha256 "#{tarball.sha256}"

          bottle do
            sha256 cellar: :any_skip_relocation, arm64_big_sur: "8f9aecd233463da6a4ea55f5f88fc5841718c013f3e2a7941350d6130f1dc149"
            sha256 cellar: :any_skip_relocation, big_sur:       "a0af7dcbb5c83f6f3f7ecd507c2d352c1a018f894d51ad241ce8492fa598010f"
            sha256 cellar: :any_skip_relocation, catalina:      "5334dd344986e46b2aa4f0471cac7b0914bd7de7cb890a34415771788d03f2ac"
          end

          option "with-foo", "Build with foo"

          def install
            (prefix/"foo"/"test").write("test") if build.with? "foo"
            prefix.install Dir["*"]
            (buildpath/"test.c").write \
            "#include <stdio.h>\\nint main(){printf(\\"test\\");return 0;}"
            bin.mkpath
            system ENV.cc, "test.c", "-o", bin/"test"
          end



          # something here

        end
      EOS
    end

    it "replaces the bottle block in a formula that already has a bottle block" do
      core_tap.path.cd do
        system "git", "-c", "init.defaultBranch=master", "init"
        setup_test_formula "testball", bottle_block: <<~EOS

          bottle do
            sha256 cellar: :any_skip_relocation, arm64_big_sur: "c3c650d75f5188f5d6edd351dd3215e141b73b8ec1cf9144f30e39cbc45de72e"
            sha256 cellar: :any_skip_relocation, big_sur:       "6b276491297d4052538bd2fd22d5129389f27d90a98f831987236a5b90511b98"
            sha256 cellar: :any_skip_relocation, catalina:      "16cf230afdfcb6306c208d169549cf8773c831c8653d2c852315a048960d7e72"
          end
        EOS
        system "git", "add", "--all"
        system "git", "commit", "-m", "testball 0.1"
      end

      # RuboCop would align the `.and` with `.to_stdout` which is too floaty.
      # rubocop:disable Layout/MultilineMethodCallIndentation
      expect do
        brew "bottle",
             "--merge",
             "--write",
             "#{TEST_TMPDIR}/testball-1.0.arm64_big_sur.bottle.json",
             "#{TEST_TMPDIR}/testball-1.0.big_sur.bottle.json",
             "#{TEST_TMPDIR}/testball-1.0.catalina.bottle.json"
      end.to output(Regexp.new(<<~'EOS')).to_stdout
        ==> testball
          bottle do
            sha256 cellar: :any_skip_relocation, arm64_big_sur: "8f9aecd233463da6a4ea55f5f88fc5841718c013f3e2a7941350d6130f1dc149"
            sha256 cellar: :any_skip_relocation, big_sur:       "a0af7dcbb5c83f6f3f7ecd507c2d352c1a018f894d51ad241ce8492fa598010f"
            sha256 cellar: :any_skip_relocation, catalina:      "5334dd344986e46b2aa4f0471cac7b0914bd7de7cb890a34415771788d03f2ac"
          end
        \[master [0-9a-f]{4,40}\] testball: update 1\.0 bottle\.
         1 file changed, 3 insertions\(\+\), 3 deletions\(\-\)
      EOS
      .and not_to_output.to_stderr
      .and be_a_success
      # rubocop:enable Layout/MultilineMethodCallIndentation

      expect((core_tap.path/"Formula/testball.rb").read).to eq <<~EOS
        class Testball < Formula
          desc "Some test"
          homepage "https://brew.sh/testball"
          url "file://#{tarball}"
          sha256 "#{tarball.sha256}"

          option "with-foo", "Build with foo"

          bottle do
            sha256 cellar: :any_skip_relocation, arm64_big_sur: "8f9aecd233463da6a4ea55f5f88fc5841718c013f3e2a7941350d6130f1dc149"
            sha256 cellar: :any_skip_relocation, big_sur:       "a0af7dcbb5c83f6f3f7ecd507c2d352c1a018f894d51ad241ce8492fa598010f"
            sha256 cellar: :any_skip_relocation, catalina:      "5334dd344986e46b2aa4f0471cac7b0914bd7de7cb890a34415771788d03f2ac"
          end

          def install
            (prefix/"foo"/"test").write("test") if build.with? "foo"
            prefix.install Dir["*"]
            (buildpath/"test.c").write \
            "#include <stdio.h>\\nint main(){printf(\\"test\\");return 0;}"
            bin.mkpath
            system ENV.cc, "test.c", "-o", bin/"test"
          end



          # something here

        end
      EOS
    end

    it "updates the bottle block in a formula that already has a bottle block when using --keep-old" do
      core_tap.path.cd do
        system "git", "-c", "init.defaultBranch=master", "init"
        setup_test_formula "testball", bottle_block: <<~EOS

          bottle do
            sha256 cellar: :any, high_sierra: "6971b6eebf4c00eaaed72a1104a49be63861eabc95d679a0c84040398e320059"
          end
        EOS
        system "git", "add", "--all"
        system "git", "commit", "-m", "testball 0.1"
      end

      # RuboCop would align the `.and` with `.to_stdout` which is too floaty.
      # rubocop:disable Layout/MultilineMethodCallIndentation
      expect do
        brew "bottle",
             "--merge",
             "--write",
             "--keep-old",
             "#{TEST_TMPDIR}/testball-1.0.arm64_big_sur.bottle.json",
             "#{TEST_TMPDIR}/testball-1.0.big_sur.bottle.json",
             "#{TEST_TMPDIR}/testball-1.0.catalina.bottle.json"
      end.to output(Regexp.new(<<~'EOS')).to_stdout
        ==> testball
          bottle do
            sha256 cellar: :any_skip_relocation, arm64_big_sur: "8f9aecd233463da6a4ea55f5f88fc5841718c013f3e2a7941350d6130f1dc149"
            sha256 cellar: :any_skip_relocation, big_sur:       "a0af7dcbb5c83f6f3f7ecd507c2d352c1a018f894d51ad241ce8492fa598010f"
            sha256 cellar: :any_skip_relocation, catalina:      "5334dd344986e46b2aa4f0471cac7b0914bd7de7cb890a34415771788d03f2ac"
            sha256 cellar: :any,                 high_sierra:   "6971b6eebf4c00eaaed72a1104a49be63861eabc95d679a0c84040398e320059"
          end
        \[master [0-9a-f]{4,40}\] testball: update 1\.0 bottle\.
         1 file changed, 4 insertions\(\+\), 1 deletion\(\-\)
      EOS
      .and not_to_output.to_stderr
      .and be_a_success
      # rubocop:enable Layout/MultilineMethodCallIndentation

      expect((core_tap.path/"Formula/testball.rb").read).to eq <<~EOS
        class Testball < Formula
          desc "Some test"
          homepage "https://brew.sh/testball"
          url "file://#{tarball}"
          sha256 "#{tarball.sha256}"

          option "with-foo", "Build with foo"

          bottle do
            sha256 cellar: :any_skip_relocation, arm64_big_sur: "8f9aecd233463da6a4ea55f5f88fc5841718c013f3e2a7941350d6130f1dc149"
            sha256 cellar: :any_skip_relocation, big_sur:       "a0af7dcbb5c83f6f3f7ecd507c2d352c1a018f894d51ad241ce8492fa598010f"
            sha256 cellar: :any_skip_relocation, catalina:      "5334dd344986e46b2aa4f0471cac7b0914bd7de7cb890a34415771788d03f2ac"
            sha256 cellar: :any,                 high_sierra:   "6971b6eebf4c00eaaed72a1104a49be63861eabc95d679a0c84040398e320059"
          end

          def install
            (prefix/"foo"/"test").write("test") if build.with? "foo"
            prefix.install Dir["*"]
            (buildpath/"test.c").write \
            "#include <stdio.h>\\nint main(){printf(\\"test\\");return 0;}"
            bin.mkpath
            system ENV.cc, "test.c", "-o", bin/"test"
          end



          # something here

        end
      EOS
    end
  end

  describe Homebrew do
    subject(:homebrew) { described_class }

    let(:hello_hash_big_sur) do
      JSON.parse stub_hash(
        name:           "hello",
        version:        "1.0",
        path:           "/home/hello.rb",
        cellar:         "any_skip_relocation",
        os:             "big_sur",
        filename:       "hello-1.0.big_sur.bottle.tar.gz",
        local_filename: "hello--1.0.big_sur.bottle.tar.gz",
        sha256:         "a0af7dcbb5c83f6f3f7ecd507c2d352c1a018f894d51ad241ce8492fa598010f",
      )
    end
    let(:hello_hash_catalina) do
      JSON.parse stub_hash(
        name:           "hello",
        version:        "1.0",
        path:           "/home/hello.rb",
        cellar:         "any_skip_relocation",
        os:             "catalina",
        filename:       "hello-1.0.catalina.bottle.tar.gz",
        local_filename: "hello--1.0.catalina.bottle.tar.gz",
        sha256:         "5334dd344986e46b2aa4f0471cac7b0914bd7de7cb890a34415771788d03f2ac",
      )
    end
    let(:unzip_hash_big_sur) do
      JSON.parse stub_hash(
        name:           "unzip",
        version:        "2.0",
        path:           "/home/unzip.rb",
        cellar:         "any_skip_relocation",
        os:             "big_sur",
        filename:       "unzip-2.0.big_sur.bottle.tar.gz",
        local_filename: "unzip--2.0.big_sur.bottle.tar.gz",
        sha256:         "16cf230afdfcb6306c208d169549cf8773c831c8653d2c852315a048960d7e72",
      )
    end
    let(:unzip_hash_catalina) do
      JSON.parse stub_hash(
        name:           "unzip",
        version:        "2.0",
        path:           "/home/unzip.rb",
        cellar:         "any",
        os:             "catalina",
        filename:       "unzip-2.0.catalina.bottle.tar.gz",
        local_filename: "unzip--2.0.catalina.bottle.tar.gz",
        sha256:         "d9cc50eec8ac243148a121049c236cba06af4a0b1156ab397d0a2850aa79c137",
      )
    end

    specify "::parse_json_files" do
      Tempfile.open("hello--1.0.big_sur.bottle.json") do |f|
        f.write stub_hash(
          name:           "hello",
          version:        "1.0",
          path:           "/home/hello.rb",
          cellar:         "any_skip_relocation",
          os:             "big_sur",
          filename:       "hello-1.0.big_sur.bottle.tar.gz",
          local_filename: "hello--1.0.big_sur.bottle.tar.gz",
          sha256:         "a0af7dcbb5c83f6f3f7ecd507c2d352c1a018f894d51ad241ce8492fa598010f",
        )
        f.close
        expect(
          homebrew.parse_json_files([f.path]).first["hello"]["bottle"]["tags"]["big_sur"]["filename"],
        ).to eq("hello-1.0.big_sur.bottle.tar.gz")
      end
    end

    describe "::merge_json_files" do
      it "merges JSON files" do
        bottles_hash = homebrew.merge_json_files(
          [hello_hash_big_sur, hello_hash_catalina, unzip_hash_big_sur, unzip_hash_catalina],
        )

        hello_hash = bottles_hash["hello"]
        expect(hello_hash["bottle"]["tags"]["big_sur"]["cellar"]).to eq("any_skip_relocation")
        expect(hello_hash["bottle"]["tags"]["big_sur"]["filename"]).to eq("hello-1.0.big_sur.bottle.tar.gz")
        expect(hello_hash["bottle"]["tags"]["big_sur"]["local_filename"]).to eq("hello--1.0.big_sur.bottle.tar.gz")
        expect(hello_hash["bottle"]["tags"]["big_sur"]["sha256"]).to eq(
          "a0af7dcbb5c83f6f3f7ecd507c2d352c1a018f894d51ad241ce8492fa598010f",
        )
        expect(hello_hash["bottle"]["tags"]["catalina"]["cellar"]).to eq("any_skip_relocation")
        expect(hello_hash["bottle"]["tags"]["catalina"]["filename"]).to eq("hello-1.0.catalina.bottle.tar.gz")
        expect(hello_hash["bottle"]["tags"]["catalina"]["local_filename"]).to eq("hello--1.0.catalina.bottle.tar.gz")
        expect(hello_hash["bottle"]["tags"]["catalina"]["sha256"]).to eq(
          "5334dd344986e46b2aa4f0471cac7b0914bd7de7cb890a34415771788d03f2ac",
        )
        unzip_hash = bottles_hash["unzip"]
        expect(unzip_hash["bottle"]["tags"]["big_sur"]["cellar"]).to eq("any_skip_relocation")
        expect(unzip_hash["bottle"]["tags"]["big_sur"]["filename"]).to eq("unzip-2.0.big_sur.bottle.tar.gz")
        expect(unzip_hash["bottle"]["tags"]["big_sur"]["local_filename"]).to eq("unzip--2.0.big_sur.bottle.tar.gz")
        expect(unzip_hash["bottle"]["tags"]["big_sur"]["sha256"]).to eq(
          "16cf230afdfcb6306c208d169549cf8773c831c8653d2c852315a048960d7e72",
        )
        expect(unzip_hash["bottle"]["tags"]["catalina"]["cellar"]).to eq("any")
        expect(unzip_hash["bottle"]["tags"]["catalina"]["filename"]).to eq("unzip-2.0.catalina.bottle.tar.gz")
        expect(unzip_hash["bottle"]["tags"]["catalina"]["local_filename"]).to eq("unzip--2.0.catalina.bottle.tar.gz")
        expect(unzip_hash["bottle"]["tags"]["catalina"]["sha256"]).to eq(
          "d9cc50eec8ac243148a121049c236cba06af4a0b1156ab397d0a2850aa79c137",
        )
      end

      # TODO: add deduplication tests e.g.
      # it "deduplicates JSON files with matching macOS checksums"
      # it "deduplicates JSON files with matching OS checksums" do
    end

    describe "#merge_bottle_spec" do
      it "allows new bottle hash to be empty" do
        valid_keys = [:root_url, :cellar, :rebuild, :sha256]
        old_spec = BottleSpecification.new
        old_spec.sha256(big_sur: "f59bc65c91e4e698f6f050e1efea0040f57372d4dcf0996cbb8f97ced320403b")
        expect { homebrew.merge_bottle_spec(valid_keys, old_spec, {}) }.not_to raise_error
      end

      it "checks for conflicting root URL" do
        old_spec = BottleSpecification.new
        old_spec.root_url("https://failbrew.bintray.com/bottles")
        new_hash = { "root_url" => "https://testbrew.bintray.com/bottles" }
        expect(homebrew.merge_bottle_spec([:root_url], old_spec, new_hash)).to eq [
          ['root_url: old: "https://failbrew.bintray.com/bottles", new: "https://testbrew.bintray.com/bottles"'],
          [],
        ]
      end

      it "checks for conflicting rebuild number" do
        old_spec = BottleSpecification.new
        old_spec.rebuild(1)
        new_hash = { "rebuild" => 2 }
        expect(homebrew.merge_bottle_spec([:rebuild], old_spec, new_hash)).to eq [
          ['rebuild: old: "1", new: "2"'],
          [],
        ]
      end

      it "checks for conflicting checksums" do
        old_spec = BottleSpecification.new
        old_catalina_sha256 = "109c0cb581a7b5d84da36d84b221fb9dd0f8a927b3044d82611791c9907e202e"
        old_spec.sha256(catalina: old_catalina_sha256)
        old_spec.sha256(mojave: "7571772bf7a0c9fe193e70e521318b53993bee6f351976c9b6e01e00d13d6c3f")
        new_catalina_sha256 = "ec6d7f08412468f28dee2be17ad8cd8b883b16b34329efcecce019b8c9736428"
        new_hash = { "tags" => { "catalina" => { "sha256" => new_catalina_sha256 } } }
        expected_checksum_hash = { mojave: "7571772bf7a0c9fe193e70e521318b53993bee6f351976c9b6e01e00d13d6c3f" }
        expected_checksum_hash[:cellar] = Homebrew::DEFAULT_MACOS_CELLAR
        expect(homebrew.merge_bottle_spec([:sha256], old_spec, new_hash)).to eq [
          ["sha256 catalina: old: #{old_catalina_sha256.inspect}, new: #{new_catalina_sha256.inspect}"],
          [expected_checksum_hash],
        ]
      end
    end

    describe "::generate_sha256_line" do
      it "generates a string without cellar" do
        expect(homebrew.generate_sha256_line(:catalina, "deadbeef", nil, 0, 10)).to eq(
          <<~RUBY.chomp,
            sha256 catalina: "deadbeef"
          RUBY
        )
      end

      it "generates a string with cellar symbol" do
        expect(homebrew.generate_sha256_line(:catalina, "deadbeef", :any, 14, 24)).to eq(
          <<~RUBY.chomp,
            sha256 cellar: :any, catalina: "deadbeef"
          RUBY
        )
      end

      it "generates a string with default cellar path" do
        expect(homebrew.generate_sha256_line(:catalina, "deadbeef", Homebrew::DEFAULT_LINUX_CELLAR, 0, 10)).to eq(
          <<~RUBY.chomp,
            sha256 catalina: "deadbeef"
          RUBY
        )
      end

      it "generates a string with non-default cellar path" do
        expect(homebrew.generate_sha256_line(:catalina, "deadbeef", "/home/test", 22, 32)).to eq(
          <<~RUBY.chomp,
            sha256 cellar: "/home/test", catalina: "deadbeef"
          RUBY
        )
      end

      context "with offsets" do
        it "generates a string without cellar" do
          expect(homebrew.generate_sha256_line(:catalina, "deadbeef", nil, 0, 15)).to eq(
            <<~RUBY.chomp,
              sha256 catalina:      "deadbeef"
            RUBY
          )
        end

        it "generates a string with cellar symbol" do
          expect(homebrew.generate_sha256_line(:catalina, "deadbeef", :any, 20, 35)).to eq(
            <<~RUBY.chomp,
              sha256 cellar: :any,       catalina:      "deadbeef"
            RUBY
          )
        end

        it "generates a string with default cellar path" do
          expect(homebrew.generate_sha256_line(:catalina, "deadbeef", Homebrew::DEFAULT_LINUX_CELLAR, 14, 30)).to eq(
            <<~RUBY.chomp,
              sha256               catalina:       "deadbeef"
            RUBY
          )
        end

        it "generates a string with non-default cellar path" do
          expect(homebrew.generate_sha256_line(:catalina, "deadbeef", "/home/test", 25, 36)).to eq(
            <<~RUBY.chomp,
              sha256 cellar: "/home/test",    catalina:  "deadbeef"
            RUBY
          )
        end
      end
    end

    describe "::bottle_output" do
      it "includes a custom root_url" do
        bottle = BottleSpecification.new
        bottle.root_url("https://example.com")
        bottle.sha256(catalina: "109c0cb581a7b5d84da36d84b221fb9dd0f8a927b3044d82611791c9907e202e")

        expect(homebrew.bottle_output(bottle, nil)).to eq(
          <<~RUBY.indent(2),
            bottle do
              root_url "https://example.com"
              sha256 catalina: "109c0cb581a7b5d84da36d84b221fb9dd0f8a927b3044d82611791c9907e202e"
            end
          RUBY
        )
      end

      it "includes download strategy for custom root_url" do
        bottle = BottleSpecification.new
        bottle.root_url("https://example.com")
        bottle.sha256(catalina: "109c0cb581a7b5d84da36d84b221fb9dd0f8a927b3044d82611791c9907e202e")

        expect(homebrew.bottle_output(bottle, "ExampleStrategy")).to eq(
          <<~RUBY.indent(2),
            bottle do
              root_url "https://example.com",
                using: ExampleStrategy
              sha256 catalina: "109c0cb581a7b5d84da36d84b221fb9dd0f8a927b3044d82611791c9907e202e"
            end
          RUBY
        )
      end
    end
  end
end

def stub_hash(parameters)
  <<~EOS
    {
      "#{parameters[:name]}":{
         "formula":{
            "pkg_version":"#{parameters[:version]}",
            "path":"#{parameters[:path]}"
         },
         "bottle":{
            "root_url":"#{parameters[:root_url] || HOMEBREW_BOTTLE_DEFAULT_DOMAIN}",
            "prefix":"/usr/local",
            "cellar":"#{parameters[:cellar]}",
            "rebuild":0,
            "tags":{
               "#{parameters[:os]}":{
                  "filename":"#{parameters[:filename]}",
                  "local_filename":"#{parameters[:local_filename]}",
                  "sha256":"#{parameters[:sha256]}"
               }
            }
         }
      }
    }
  EOS
end
