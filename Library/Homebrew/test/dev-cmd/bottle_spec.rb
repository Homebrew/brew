# typed: true
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/bottle"

RSpec.describe Homebrew::DevCmd::Bottle do
  def stub_hash(parameters)
    <<~JSON
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
                    #{",\"sbom\":#{parameters[:sbom].to_json}" if parameters[:sbom]}
                    #{",\"tab\":#{parameters[:tab].to_json}" if parameters[:tab]}
                 }
              }
           }
        }
      }
    JSON
  end

  it_behaves_like "parseable arguments"

  describe "#binary_relocation_diagnostic_string" do
    let(:bottle) { described_class.new(["--no-rebuild", "testball"]) }
    let(:relative_path) { Pathname("bin/dbus-daemon") }

    it "returns the match unchanged when it is valid UTF-8" do
      # Matches are always tagged `ASCII-8BIT`, as `Utils.popen_read` reads in binary mode.
      match = "/opt/homebrew/Cellar".b

      result = bottle.binary_relocation_diagnostic_string(match, relative_path, "1000")

      expect(result).to eq("/opt/homebrew/Cellar").and have_attributes(encoding: Encoding::UTF_8)
    end

    it "warns when scrubbing a match that is not valid UTF-8" do
      # Mimics `strings -` gluing invalid UTF-8 bytes onto an adjacent real string.
      match = "\xFF\xFF\xFF\xFF/opt/homebrew/Cellar".b

      expect(bottle).to receive(:opoo)
        .with("Scrubbing string with invalid encoding in #{relative_path} at offset 0x203cc")

      bottle.binary_relocation_diagnostic_string(match, relative_path, "203cc")
    end

    it "scrubs a match that is not valid UTF-8, keeping the rest of the string" do
      # Mimics `strings -` gluing invalid UTF-8 bytes onto an adjacent real string.
      match = "\xFF\xFF\xFF\xFF/opt/homebrew/Cellar".b
      allow(bottle).to receive(:opoo)

      result = bottle.binary_relocation_diagnostic_string(match, relative_path, "203cc")

      expect(result).to have_attributes(encoding: Encoding::UTF_8, valid_encoding?: true)
        .and end_with("/opt/homebrew/Cellar")
    end
  end

  it "does not restore locations when placeholdering fails" do
    formula = formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/testball-1.0.tar.gz"
    end
    tap = instance_double(
      Tap,
      installed?: true,
      path:       HOMEBREW_REPOSITORY,
      git_head:   "HEAD",
      remote:     "https://github.com/Homebrew/homebrew-core",
    )
    keg = instance_double(Keg)
    bottle = described_class.new(["--no-rebuild", formula.name])

    allow(Utils::GemSetup).to receive(:install_bundler_gems!)
    allow(bottle.args.named).to receive(:to_resolved_formulae).with(uniq: false).and_return([formula])
    allow(formula).to receive_messages(latest_version_installed?: true, tap:, runtime_dependencies: [])
    allow(Utils::Bottles).to receive(:built_as?).with(formula).and_return(true)
    allow(Keg).to receive(:new).with(formula.prefix).and_return(keg)
    allow(keg).to receive(:lock).and_yield
    allow(keg).to receive(:delete_pyc_files!).and_raise("placeholdering failed")
    allow(keg).to receive(:replace_placeholders_with_locations).and_raise("restoration ran")

    expect { bottle.run }.to raise_error(RuntimeError, "placeholdering failed")
  end

  it "builds a bottle for the given Formula", :integration_test do
    setup_test_formula "testball",
                       tab_attributes: { built_as_bottle: true, built_prefix: Keg::PREFIX_PLACEHOLDER }
    formula = Formula["testball"]

    # `brew bottle` should not fail with dead symlink
    # https://github.com/Homebrew/legacy-homebrew/issues/49007
    formula.prefix.cd do
      FileUtils.ln_s "not-exist", "symlink"
    end
    formula.libexec.mkpath
    (formula.libexec/"raw-prefix").binwrite(
      "\0#{Array.new(Homebrew::DevCmd::Bottle::MAXIMUM_STRING_MATCHES + 1, formula.libexec.to_s).join("\0")}\0",
    )
    stderr = if !Sandbox.available?
      "Warning: Sandbox unavailable: processing downloaded files without sandboxing!\n"
    elsif Sandbox.nested_sandbox?
      "Warning: Processing downloaded files without Homebrew's sandbox; relying on the outer sandbox.\n"
    elsif OS.linux? && (abi = Sandbox::Landlock.abi_version) && abi < 10
      network_warning = if abi >= 4
        "Applying the network restrictions supported by this kernel."
      else
        "This kernel cannot restrict network access."
      end
      "Warning: Landlock ABI 10 or later is required to deny all network access; found ABI #{abi}. " \
        "#{network_warning}\n"
    else
      ""
    end
    stderr = "" if Sandbox.inherited_sandbox?

    begin
      expect { brew "bottle", "--no-rebuild", "--json", "testball" }
        .to output(/testball--0\.1.*\.bottle\.tar\.gz/).to_stdout
        .and output(stderr).to_stderr
        .and be_a_success
      expect(HOMEBREW_CELLAR/"testball-bottle.tar").not_to exist

      tag = JSON.parse(Pathname(Dir["testball--0.1*.bottle.json"].fetch(0)).read)
                .dig("testball", "bottle", "tags").values.fetch(0)
      expect(tag.fetch("tab")).to include(
        "changed_files"           => be_an(Array),
        "linkage_files"           => be_an(Array),
        "binary_relocation_files" => include("libexec/raw-prefix"),
        "built_prefix"            => HOMEBREW_PREFIX.to_s,
      )
      binary_relocation_diagnostics = tag.fetch("binary_relocation_diagnostics")
      expect(binary_relocation_diagnostics.size).to eq(Homebrew::DevCmd::Bottle::MAXIMUM_STRING_MATCHES)
      expect(binary_relocation_diagnostics).to include(
        include(
          "path"   => "libexec/raw-prefix",
          "string" => formula.libexec.to_s,
          "offset" => be_an(Integer),
        ),
      )

      expect { brew "bottle", "--no-rebuild", "--json", "--skip-relocation", "testball" }
        .to be_a_success
      skipped_tag = JSON.parse(Pathname(Dir["testball--0.1*.bottle.json"].fetch(0)).read)
                        .dig("testball", "bottle", "tags").values.fetch(0)
      expect(skipped_tag.fetch("tab").values_at(
               "changed_files", "linkage_files", "binary_relocation_files"
             )).to eq([nil, nil, nil])
    ensure
      FileUtils.rm_f Dir.glob("testball--0.1*.bottle.tar.gz")
      FileUtils.rm_f Dir.glob("testball--0.1*.bottle.json")
    end
  end

  describe "--merge", :integration_test do
    let(:core_tap) { CoreTap.instance }
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

      Pathname("#{TEST_TMPDIR}/testball-1.0.monterey.bottle.json").write stub_hash(
        name:           "testball",
        version:        "1.0",
        path:           "#{core_tap.path}/Formula/testball.rb",
        cellar:         "any_skip_relocation",
        os:             "monterey",
        filename:       "testball-1.0.monterey.bottle.tar.gz",
        local_filename: "testball--1.0.monterey.bottle.tar.gz",
        sha256:         "5334dd344986e46b2aa4f0471cac7b0914bd7de7cb890a34415771788d03f2ac",
      )
    end

    after do
      FileUtils.rm_f "#{TEST_TMPDIR}/testball-1.0.arm64_big_sur.bottle.json"
      FileUtils.rm_f "#{TEST_TMPDIR}/testball-1.0.monterey.bottle.json"
      FileUtils.rm_f "#{TEST_TMPDIR}/testball-1.0.big_sur.bottle.json"
      FileUtils.rm_f "#{TEST_TMPDIR}/testball-1.0.arm64_monterey.bottle.json"
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
             "#{TEST_TMPDIR}/testball-1.0.monterey.bottle.json"
      end.to output(Regexp.new(<<~'EOS')).to_stdout
        ==> testball
          bottle do
            sha256 cellar: :any_skip_relocation, arm64_big_sur: "8f9aecd233463da6a4ea55f5f88fc5841718c013f3e2a7941350d6130f1dc149"
            sha256 cellar: :any_skip_relocation, monterey:      "5334dd344986e46b2aa4f0471cac7b0914bd7de7cb890a34415771788d03f2ac"
            sha256 cellar: :any_skip_relocation, big_sur:       "a0af7dcbb5c83f6f3f7ecd507c2d352c1a018f894d51ad241ce8492fa598010f"
          end
        \[master [0-9a-f]{4,40}\] testball: add 1\.0 bottle\.
         1 file changed, 6 insertions\(\+\)
      EOS
      .and not_to_output.to_stderr
      .and be_a_success
      # rubocop:enable Layout/MultilineMethodCallIndentation

      expect((core_tap.path/"Formula/testball.rb").read).to eq <<~RUBY
        class Testball < Formula
          desc "Some test"
          homepage "https://brew.sh/testball"
          url "file://#{tarball}"
          sha256 "#{tarball.sha256}"

          bottle do
            sha256 cellar: :any_skip_relocation, arm64_big_sur: "8f9aecd233463da6a4ea55f5f88fc5841718c013f3e2a7941350d6130f1dc149"
            sha256 cellar: :any_skip_relocation, monterey:      "5334dd344986e46b2aa4f0471cac7b0914bd7de7cb890a34415771788d03f2ac"
            sha256 cellar: :any_skip_relocation, big_sur:       "a0af7dcbb5c83f6f3f7ecd507c2d352c1a018f894d51ad241ce8492fa598010f"
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
      RUBY
    end

    it "replaces the bottle block in a formula that already has a bottle block" do
      core_tap.path.cd do
        system "git", "-c", "init.defaultBranch=master", "init"
        setup_test_formula "testball", bottle_block: <<~RUBY

          bottle do
            sha256 cellar: :any_skip_relocation, arm64_big_sur: "c3c650d75f5188f5d6edd351dd3215e141b73b8ec1cf9144f30e39cbc45de72e"
            sha256 cellar: :any_skip_relocation, big_sur:       "6b276491297d4052538bd2fd22d5129389f27d90a98f831987236a5b90511b98"
            sha256 cellar: :any_skip_relocation, monterey:      "16cf230afdfcb6306c208d169549cf8773c831c8653d2c852315a048960d7e72"
          end
        RUBY
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
             "#{TEST_TMPDIR}/testball-1.0.monterey.bottle.json"
      end.to output(Regexp.new(<<~'EOS')).to_stdout
        ==> testball
          bottle do
            sha256 cellar: :any_skip_relocation, arm64_big_sur: "8f9aecd233463da6a4ea55f5f88fc5841718c013f3e2a7941350d6130f1dc149"
            sha256 cellar: :any_skip_relocation, monterey:      "5334dd344986e46b2aa4f0471cac7b0914bd7de7cb890a34415771788d03f2ac"
            sha256 cellar: :any_skip_relocation, big_sur:       "a0af7dcbb5c83f6f3f7ecd507c2d352c1a018f894d51ad241ce8492fa598010f"
          end
        \[master [0-9a-f]{4,40}\] testball: update 1\.0 bottle\.
         1 file changed, 3 insertions\(\+\), 3 deletions\(\-\)
      EOS
      .and not_to_output.to_stderr
      .and be_a_success
      # rubocop:enable Layout/MultilineMethodCallIndentation

      expect((core_tap.path/"Formula/testball.rb").read).to eq <<~RUBY
        class Testball < Formula
          desc "Some test"
          homepage "https://brew.sh/testball"
          url "file://#{tarball}"
          sha256 "#{tarball.sha256}"

          option "with-foo", "Build with foo"

          bottle do
            sha256 cellar: :any_skip_relocation, arm64_big_sur: "8f9aecd233463da6a4ea55f5f88fc5841718c013f3e2a7941350d6130f1dc149"
            sha256 cellar: :any_skip_relocation, monterey:      "5334dd344986e46b2aa4f0471cac7b0914bd7de7cb890a34415771788d03f2ac"
            sha256 cellar: :any_skip_relocation, big_sur:       "a0af7dcbb5c83f6f3f7ecd507c2d352c1a018f894d51ad241ce8492fa598010f"
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
      RUBY
    end

    it "updates the bottle block in a formula that already has a bottle block when using --keep-old" do
      core_tap.path.cd do
        system "git", "-c", "init.defaultBranch=master", "init"
        setup_test_formula "testball", bottle_block: <<~RUBY

          bottle do
            sha256 cellar: :any, sonoma: "6971b6eebf4c00eaaed72a1104a49be63861eabc95d679a0c84040398e320059"
          end
        RUBY
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
             "#{TEST_TMPDIR}/testball-1.0.monterey.bottle.json"
      end.to output(Regexp.new(<<~'EOS')).to_stdout
        ==> testball
          bottle do
            sha256 cellar: :any_skip_relocation, arm64_big_sur: "8f9aecd233463da6a4ea55f5f88fc5841718c013f3e2a7941350d6130f1dc149"
            sha256 cellar: :any,                 sonoma:        "6971b6eebf4c00eaaed72a1104a49be63861eabc95d679a0c84040398e320059"
            sha256 cellar: :any_skip_relocation, monterey:      "5334dd344986e46b2aa4f0471cac7b0914bd7de7cb890a34415771788d03f2ac"
            sha256 cellar: :any_skip_relocation, big_sur:       "a0af7dcbb5c83f6f3f7ecd507c2d352c1a018f894d51ad241ce8492fa598010f"
          end
        \[master [0-9a-f]{4,40}\] testball: update 1\.0 bottle\.
         1 file changed, 4 insertions\(\+\), 1 deletion\(\-\)
      EOS
      .and not_to_output.to_stderr
      .and be_a_success
      # rubocop:enable Layout/MultilineMethodCallIndentation

      expect((core_tap.path/"Formula/testball.rb").read).to eq <<~RUBY
        class Testball < Formula
          desc "Some test"
          homepage "https://brew.sh/testball"
          url "file://#{tarball}"
          sha256 "#{tarball.sha256}"

          option "with-foo", "Build with foo"

          bottle do
            sha256 cellar: :any_skip_relocation, arm64_big_sur: "8f9aecd233463da6a4ea55f5f88fc5841718c013f3e2a7941350d6130f1dc149"
            sha256 cellar: :any,                 sonoma:        "6971b6eebf4c00eaaed72a1104a49be63861eabc95d679a0c84040398e320059"
            sha256 cellar: :any_skip_relocation, monterey:      "5334dd344986e46b2aa4f0471cac7b0914bd7de7cb890a34415771788d03f2ac"
            sha256 cellar: :any_skip_relocation, big_sur:       "a0af7dcbb5c83f6f3f7ecd507c2d352c1a018f894d51ad241ce8492fa598010f"
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
      RUBY
    end

    it "writes an all bottle JSON for matching platform bottles" do
      core_tap.path.cd do
        system "git", "-c", "init.defaultBranch=master", "init"
        setup_test_formula "testball"
        system "git", "add", "--all"
        system "git", "commit", "-m", "testball 0.1"
      end

      mktmpdir.cd do
        sha256 = "8f9aecd233463da6a4ea55f5f88fc5841718c013f3e2a7941350d6130f1dc149"
        bottle_json_paths = ["arm64_big_sur", "big_sur"].map do |tag|
          Pathname("testball--1.0.#{tag}.bottle.tar.gz").write("test")
          Pathname("#{TEST_TMPDIR}/testball-1.0.#{tag}.bottle.json").tap do |path|
            path.write stub_hash(
              name:           "testball",
              version:        "1.0",
              path:           "#{core_tap.path}/Formula/testball.rb",
              cellar:         "any_skip_relocation",
              os:             tag,
              filename:       "testball-1.0.#{tag}.bottle.tar.gz",
              local_filename: "testball--1.0.#{tag}.bottle.tar.gz",
              sha256:,
              sbom:           { "packages" => [{ "SPDXID" => "SPDXRef-#{tag}" }] },
            )
          end
        end

        # RuboCop would align the `.and` with `.to_stdout` which is too floaty.
        # rubocop:disable Layout/MultilineMethodCallIndentation
        expect do
          brew "bottle", "--merge", "--write", "--no-commit", *bottle_json_paths
        end.to output(/sha256 cellar: :any_skip_relocation, all: "#{sha256}"/).to_stdout
        .and not_to_output.to_stderr
        .and be_a_success
        # rubocop:enable Layout/MultilineMethodCallIndentation

        all_bottle_hash = JSON.parse(Pathname("testball--1.0.all.bottle.json").read)
        all_bottle_tag_hash = all_bottle_hash.dig("testball", "bottle", "tags", "all")

        expect(all_bottle_hash.dig("testball", "bottle", "cellar")).to eq("any_skip_relocation")
        expect(all_bottle_hash.dig("testball", "bottle", "tags").keys).to eq(["all"])
        expect(all_bottle_tag_hash).to include(
          "filename"       => "testball-1.0.all.bottle.tar.gz",
          "local_filename" => "testball--1.0.all.bottle.tar.gz",
          "sha256"         => sha256,
        )
        expect(all_bottle_tag_hash.dig("sbom", "tags").keys).to contain_exactly("arm64_big_sur", "big_sur")
        expect(all_bottle_tag_hash).not_to have_key("cellar")
        expect(Pathname("testball--1.0.all.bottle.tar.gz")).to exist
      end
    end

    it "merges when an all bottle cannot be created" do
      core_tap.path.cd do
        system "git", "-c", "init.defaultBranch=master", "init"
        setup_test_formula "testball", bottle_block: <<~RUBY

          bottle do
            sha256 cellar: :any_skip_relocation, all: "d7b9f4e8bf83608b71fe958a99f19f2e5e68bb2582965d32e41759c24f1aef97"
          end
        RUBY
        system "git", "add", "--all"
        system "git", "commit", "-m", "testball 0.1"
      end

      expect do
        brew "bottle",
             "--merge",
             "--write",
             "--no-commit",
             "#{TEST_TMPDIR}/testball-1.0.arm64_big_sur.bottle.json",
             "#{TEST_TMPDIR}/testball-1.0.big_sur.bottle.json",
             { "GITHUB_EVENT_PATH" => nil }
      end.to output(/sha256 cellar: :any_skip_relocation, arm64_big_sur:/).to_stdout
                                                                          .and not_to_output.to_stderr
                                                                                            .and be_a_success

      formula_contents = (core_tap.path/"Formula/testball.rb").read
      expect(formula_contents).to include("big_sur:")
      expect(formula_contents).not_to include("all:")
    end

    it "does not collapse padded bottles into an all bottle" do
      core_tap.path.cd do
        system "git", "-c", "init.defaultBranch=master", "init"
        setup_test_formula "testball"
        system "git", "add", "--all"
        system "git", "commit", "-m", "testball 0.1"
      end

      sha256 = "8f9aecd233463da6a4ea55f5f88fc5841718c013f3e2a7941350d6130f1dc149"
      bottle_json_paths = ["arm64_big_sur", "arm64_monterey"].map do |tag|
        Pathname("#{TEST_TMPDIR}/testball-1.0.#{tag}.bottle.json").tap do |path|
          path.write stub_hash(
            name:           "testball",
            version:        "1.0",
            path:           "#{core_tap.path}/Formula/testball.rb",
            cellar:         Homebrew::DEFAULT_MACOS_ARM_CELLAR,
            os:             tag,
            filename:       "testball-1.0.#{tag}.bottle.tar.gz",
            local_filename: "testball--1.0.#{tag}.bottle.tar.gz",
            sha256:,
            tab:            { "padded_prefix" => true },
          )
        end
      end

      expect do
        brew "bottle", "--merge", *bottle_json_paths
      end.to(
        output(/\A(?!.* all:)(?=.*sha256 arm64_big_sur:)(?=.*sha256 arm64_monterey:)/m).to_stdout
          .and(not_to_output.to_stderr)
          .and(be_a_success),
      )
    end
  end

  describe "bottle_cmd" do
    subject(:homebrew) { described_class.new(["foo"]) }

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
    let(:hello_hash_monterey) do
      JSON.parse stub_hash(
        name:           "hello",
        version:        "1.0",
        path:           "/home/hello.rb",
        cellar:         "any_skip_relocation",
        os:             "monterey",
        filename:       "hello-1.0.monterey.bottle.tar.gz",
        local_filename: "hello--1.0.monterey.bottle.tar.gz",
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
    let(:unzip_hash_monterey) do
      JSON.parse stub_hash(
        name:           "unzip",
        version:        "2.0",
        path:           "/home/unzip.rb",
        cellar:         "any",
        os:             "monterey",
        filename:       "unzip-2.0.monterey.bottle.tar.gz",
        local_filename: "unzip--2.0.monterey.bottle.tar.gz",
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
          [hello_hash_big_sur, hello_hash_monterey, unzip_hash_big_sur, unzip_hash_monterey],
        )

        hello_hash = bottles_hash["hello"]
        expect(hello_hash["bottle"]["tags"]["big_sur"]["cellar"]).to eq("any_skip_relocation")
        expect(hello_hash["bottle"]["tags"]["big_sur"]["filename"]).to eq("hello-1.0.big_sur.bottle.tar.gz")
        expect(hello_hash["bottle"]["tags"]["big_sur"]["local_filename"]).to eq("hello--1.0.big_sur.bottle.tar.gz")
        expect(hello_hash["bottle"]["tags"]["big_sur"]["sha256"]).to eq(
          "a0af7dcbb5c83f6f3f7ecd507c2d352c1a018f894d51ad241ce8492fa598010f",
        )
        expect(hello_hash["bottle"]["tags"]["monterey"]["cellar"]).to eq("any_skip_relocation")
        expect(hello_hash["bottle"]["tags"]["monterey"]["filename"]).to eq("hello-1.0.monterey.bottle.tar.gz")
        expect(hello_hash["bottle"]["tags"]["monterey"]["local_filename"]).to eq("hello--1.0.monterey.bottle.tar.gz")
        expect(hello_hash["bottle"]["tags"]["monterey"]["sha256"]).to eq(
          "5334dd344986e46b2aa4f0471cac7b0914bd7de7cb890a34415771788d03f2ac",
        )
        unzip_hash = bottles_hash["unzip"]
        expect(unzip_hash["bottle"]["tags"]["big_sur"]["cellar"]).to eq("any_skip_relocation")
        expect(unzip_hash["bottle"]["tags"]["big_sur"]["filename"]).to eq("unzip-2.0.big_sur.bottle.tar.gz")
        expect(unzip_hash["bottle"]["tags"]["big_sur"]["local_filename"]).to eq("unzip--2.0.big_sur.bottle.tar.gz")
        expect(unzip_hash["bottle"]["tags"]["big_sur"]["sha256"]).to eq(
          "16cf230afdfcb6306c208d169549cf8773c831c8653d2c852315a048960d7e72",
        )
        expect(unzip_hash["bottle"]["tags"]["monterey"]["cellar"]).to eq("any")
        expect(unzip_hash["bottle"]["tags"]["monterey"]["filename"]).to eq("unzip-2.0.monterey.bottle.tar.gz")
        expect(unzip_hash["bottle"]["tags"]["monterey"]["local_filename"]).to eq("unzip--2.0.monterey.bottle.tar.gz")
        expect(unzip_hash["bottle"]["tags"]["monterey"]["sha256"]).to eq(
          "d9cc50eec8ac243148a121049c236cba06af4a0b1156ab397d0a2850aa79c137",
        )
      end

      # TODO: add deduplication tests e.g.
      #       it "deduplicates JSON files with matching macOS checksums"
      #       it "deduplicates JSON files with matching OS checksums" do
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
        old_sequoia_sha256 = "109c0cb581a7b5d84da36d84b221fb9dd0f8a927b3044d82611791c9907e202e"
        old_spec.sha256(sequoia: old_sequoia_sha256)
        old_spec.sha256(sonoma: "7571772bf7a0c9fe193e70e521318b53993bee6f351976c9b6e01e00d13d6c3f")
        new_sequoia_sha256 = "ec6d7f08412468f28dee2be17ad8cd8b883b16b34329efcecce019b8c9736428"
        new_hash = { "tags" => { "sequoia" => { "sha256" => new_sequoia_sha256 } } }
        expected_checksum_hash = { sonoma: "7571772bf7a0c9fe193e70e521318b53993bee6f351976c9b6e01e00d13d6c3f" }
        expected_checksum_hash[:cellar] = Homebrew::DEFAULT_MACOS_CELLAR
        expect(homebrew.merge_bottle_spec([:sha256], old_spec, new_hash)).to eq [
          ["sha256 sequoia: old: #{old_sequoia_sha256.inspect}, new: #{new_sequoia_sha256.inspect}"],
          [expected_checksum_hash],
        ]
      end
    end

    describe "::generate_sha256_line" do
      it "generates a string without cellar" do
        expect(homebrew.generate_sha256_line(:sequoia, "deadbeef", nil, 0, 10)).to eq(
          <<~RUBY.chomp,
            sha256 sequoia:  "deadbeef"
          RUBY
        )
      end

      it "generates a string with cellar symbol" do
        expect(homebrew.generate_sha256_line(:sequoia, "deadbeef", :any, 14, 24)).to eq(
          <<~RUBY.chomp,
            sha256 cellar: :any, sequoia:  "deadbeef"
          RUBY
        )
      end

      it "generates a string with default cellar path" do
        expect(homebrew.generate_sha256_line(:sequoia, "deadbeef", Homebrew::DEFAULT_LINUX_CELLAR, 0, 10)).to eq(
          <<~RUBY.chomp,
            sha256 sequoia:  "deadbeef"
          RUBY
        )
      end

      it "generates a string with non-default cellar path" do
        expect(homebrew.generate_sha256_line(:sequoia, "deadbeef", "/home/test", 22, 32)).to eq(
          <<~RUBY.chomp,
            sha256 cellar: "/home/test", sequoia:  "deadbeef"
          RUBY
        )
      end

      context "with offsets" do
        it "generates a string without cellar" do
          expect(homebrew.generate_sha256_line(:sequoia, "deadbeef", nil, 0, 15)).to eq(
            <<~RUBY.chomp,
              sha256 sequoia:       "deadbeef"
            RUBY
          )
        end

        it "generates a string with cellar symbol" do
          expect(homebrew.generate_sha256_line(:sequoia, "deadbeef", :any, 20, 35)).to eq(
            <<~RUBY.chomp,
              sha256 cellar: :any,       sequoia:       "deadbeef"
            RUBY
          )
        end

        it "generates a string with default cellar path" do
          expect(homebrew.generate_sha256_line(:sequoia, "deadbeef", Homebrew::DEFAULT_LINUX_CELLAR, 14, 30)).to eq(
            <<~RUBY.chomp,
              sha256               sequoia:        "deadbeef"
            RUBY
          )
        end

        it "generates a string with non-default cellar path" do
          expect(homebrew.generate_sha256_line(:sequoia, "deadbeef", "/home/test", 25, 36)).to eq(
            <<~RUBY.chomp,
              sha256 cellar: "/home/test",    sequoia:   "deadbeef"
            RUBY
          )
        end
      end
    end

    describe "::bottle_output" do
      it "omits a padded bottle's tag-default cellar" do
        bottle = BottleSpecification.new
        bottle.sha256(cellar:      Homebrew::DEFAULT_MACOS_ARM_CELLAR,
                      arm64_tahoe: "109c0cb581a7b5d84da36d84b221fb9dd0f8a927b3044d82611791c9907e202e")

        expect(homebrew.bottle_output(bottle, nil)).to include("sha256 arm64_tahoe:")
      end

      it "includes a custom root_url" do
        bottle = BottleSpecification.new
        bottle.root_url("https://example.com")
        bottle.sha256(monterey: "109c0cb581a7b5d84da36d84b221fb9dd0f8a927b3044d82611791c9907e202e")

        expect(homebrew.bottle_output(bottle, nil)).to eq(
          <<-RUBY,
  bottle do
    root_url "https://example.com"
    sha256 monterey: "109c0cb581a7b5d84da36d84b221fb9dd0f8a927b3044d82611791c9907e202e"
  end
          RUBY
        )
      end

      it "includes download strategy for custom root_url" do
        bottle = BottleSpecification.new
        bottle.root_url("https://example.com")
        bottle.sha256(monterey: "109c0cb581a7b5d84da36d84b221fb9dd0f8a927b3044d82611791c9907e202e")

        expect(homebrew.bottle_output(bottle, "ExampleStrategy")).to eq(
          <<-RUBY,
  bottle do
    root_url "https://example.com",
      using: ExampleStrategy
    sha256 monterey: "109c0cb581a7b5d84da36d84b221fb9dd0f8a927b3044d82611791c9907e202e"
  end
          RUBY
        )
      end
    end
  end
end
