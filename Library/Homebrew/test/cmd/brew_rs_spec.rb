# frozen_string_literal: true

require "json"

# This spec exercises brew.sh dispatch rather than a Ruby class API.
# rubocop:disable RSpec/DescribeClass
RSpec.describe "brew-rs" do
  let(:brew_rs_bin) { HOMEBREW_LIBRARY_PATH/"vendor/brew-rs/brew-rs" }
  let(:brew_rs_cache) { Pathname(TEST_TMPDIR)/"brew-rs-cache" }
  let(:brew_rs_env) do
    {
      "HOMEBREW_DEVELOPER"     => "1",
      "HOMEBREW_RUST_FRONTEND" => "1",
      "HOMEBREW_CACHE"         => brew_rs_cache.to_s,
    }
  end
  let(:api_cache) { brew_rs_cache/"api" }

  before do
    skip "brew-rs is not built." unless brew_rs_bin.executable?
  end

  after do
    FileUtils.rm_rf brew_rs_cache
  end

  it "uses the brew-rs search flow", :integration_test do
    api_cache.mkpath
    (api_cache/"formula_names.txt").write("testball\n")
    (api_cache/"cask_names.txt").write("local-caffeine\n")

    expect { brew_sh "search", "l", brew_rs_env }
      .to output(/testball\n\nlocal-caffeine\n/).to_stdout
      .and be_a_success
  end

  it "uses the brew-rs info flow", :integration_test do
    formula_json_path = api_cache/"formula/testball.json"
    cask_json_path = api_cache/"cask/local-caffeine.json"
    formula_json_path.dirname.mkpath
    cask_json_path.dirname.mkpath

    formula_json_path.write(
      JSON.generate(
        {
          name:      "testball",
          full_name: "testball",
          desc:      "Some test",
          homepage:  "https://brew.sh/testball",
          versions:  {
            stable: "0.1",
          },
        },
      ),
    )
    cask_json_path.write(
      JSON.generate(
        {
          token:    "local-caffeine",
          name:     ["Local Caffeine"],
          desc:     "Local test cask",
          homepage: "https://brew.sh/",
          version:  "1.2.3",
        },
      ),
    )

    expect { brew_sh "info", "testball", "local-caffeine", brew_rs_env }
      .to output(/testball: 0\.1.*Some test.*local-caffeine: 1\.2\.3.*Local Caffeine/m).to_stdout
      .and be_a_success
  end

  it "uses the brew-rs list flow", :integration_test do
    (HOMEBREW_CELLAR/"foo/1.0/bin").mkpath
    (HOMEBREW_CELLAR/"foo/1.0/bin/foo").write("foo")
    (HOMEBREW_PREFIX/"Caskroom/local-caffeine/1.2.3").mkpath

    expect { brew_sh "list", brew_rs_env }
      .to output(/foo.*local-caffeine/m).to_stdout
      .and be_a_success
  end

  it "delegates unsupported read flags to Ruby", :integration_test do
    expect { brew_sh "info", "git", "--json=v1", brew_rs_env }
      .to output(/\[\s*\{\s*"name": "git"/m).to_stdout
      .and be_a_success
  end

  it "delegates install help to the existing brew frontend", :integration_test do
    expect { brew_sh "install", "--help", brew_rs_env }
      .to output(/Install a formula or cask\./).to_stdout
      .and be_a_success
  end

  it "delegates update help to the existing brew frontend", :integration_test do
    expect { brew_sh "update", "--help", brew_rs_env }
      .to output(/Fetch the newest version of Homebrew/).to_stdout
      .and be_a_success
  end

  it "delegates upgrade help to the existing brew frontend", :integration_test do
    expect { brew_sh "upgrade", "--help", brew_rs_env }
      .to output(/Upgrade outdated casks and outdated, unpinned formulae/).to_stdout
      .and be_a_success
  end

  it "delegates uninstall help to the existing brew frontend", :integration_test do
    expect { brew_sh "uninstall", "--help", brew_rs_env }
      .to output(/Uninstall a formula or cask/).to_stdout
      .and be_a_success
  end
end
# rubocop:enable RSpec/DescribeClass
