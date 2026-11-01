# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/update-sponsors"
require "utils/sponsors"

RSpec.describe Homebrew::DevCmd::UpdateSponsors do
  before do
    allow(Sponsors).to receive_messages(github_one_time: [], patreon: [], open_collective: [])
  end

  it_behaves_like "parseable arguments"

  test_each([
    { monthly_amount: 99, named_types: [], logo: false },
    { monthly_amount: 100, named_types: ["User"], logo: false },
    { monthly_amount: 249, named_types: ["User"], logo: false },
    { monthly_amount: 250, named_types: %w[User Organization], logo: false },
    { monthly_amount: 1000, named_types: %w[User Organization], logo: false },
    { monthly_amount: 1499, named_types: %w[User Organization], logo: false },
    { monthly_amount: 1500, named_types: %w[User Organization], logo: true },
    { monthly_amount: 1750, named_types: %w[User Organization], logo: true },
    {
      monthly_amount:   100,
      tier_description: "We will note your name in plain-text in our README.",
      named_types:      %w[User Organization],
      logo:             false,
    },
    {
      monthly_amount:   1000,
      tier_description: "We will put your name and linked organisation's logo in our README.",
      named_types:      %w[User Organization],
      logo:             true,
    },
    {
      monthly_amount:   50,
      tier_description: "We will note your user's name in our README (individuals only, no organisations).",
      named_types:      ["User"],
      logo:             false,
    },
  ].product(%w[User
               Organization], [0, 50], [:github, :open_collective])) do |sponsorship, type, price_increase, platform|
    it "uses current and subscribed tiers for #{type} at $#{sponsorship[:monthly_amount]} plus $#{price_increase}, " \
       "with tier #{sponsorship[:tier_description].inspect} on #{platform}" do
      readme = mktmpdir/"README.md"
      stub_const("HOMEBREW_REPOSITORY", readme.dirname)
      readme.write "Homebrew is generously supported by [Old sponsor](https://github.com/old).\n" \
                   "\n[![Old sponsor](https://github.com/old.png?size=64)](https://github.com/old)\n"
      command = described_class.new([])
      allow(command).to receive(:system_command).and_return(
        instance_double(SystemCommand::Result, status: instance_double(Process::Status, success?: false)),
      )
      allow(command).to receive(:puts)
      allow(GitHub).to receive(:sponsorship_tiers).with("Homebrew").and_return([
        { monthly_amount: 1, description: "You get a warm fuzzy feeling for supporting the project." },
        {
          monthly_amount: 100 + price_increase,
          description:    "We will note your user's name in plain-text in our README " \
                          "(individuals only, no organisations).",
        },
        {
          monthly_amount: 250 + price_increase,
          description:    "We will note your organisation's or user's name in plain-text in our README.",
        },
        {
          monthly_amount: 1500 + price_increase,
          description:    "We will put your name and linked organisation's logo in our README.",
        },
      ])
      allow(GitHub).to receive(:sponsorships).with("Homebrew").and_return([{
        type:,
        monthly_amount:   sponsorship[:monthly_amount] + price_increase,
        tier_description: sponsorship.fetch(:tier_description, ""),
        name:             "Sponsor",
        login:            "sponsor",
      }])
      if platform == :open_collective
        allow(GitHub).to receive(:sponsorships).with("Homebrew").and_return([{
          type: "User", monthly_amount: 1, tier_description: "", name: "Small sponsor", login: "small-sponsor"
        }])
        allow(Sponsors).to receive(:open_collective).and_return([{
          type:, monthly_amount: sponsorship[:monthly_amount] + price_increase,
          tier_descriptions: [sponsorship.fetch(:tier_description, "")], name: "Sponsor",
          url: "https://opencollective.com/sponsor", logo: "https://example.com/sponsor.png"
        }])
      end

      command.run

      expected = "Homebrew is generously supported by:\n\n- "
      if platform == :github && sponsorship[:named_types].include?(type)
        expected += sponsorship[:logo] ? "[Sponsor](https://github.com/sponsor) and " : "Sponsor and "
      end
      expected += "[many others](https://github.com/sponsors/Homebrew#sponsors) " \
                  "via [GitHub Sponsors](https://github.com/sponsors/Homebrew).\n- "
      if platform == :open_collective && sponsorship[:named_types].include?(type)
        expected += sponsorship[:logo] ? "[Sponsor](https://opencollective.com/sponsor) and " : "Sponsor and "
      end
      expected += "[many others](https://opencollective.com/homebrew/transactions?" \
                  "kind=ADDED_FUNDS&kind=CONTRIBUTION) " \
                  "via [Open Collective](https://opencollective.com/homebrew).\n" \
                  "- [many others](https://www.patreon.com/homebrew) via [Patreon](https://www.patreon.com/homebrew).\n"
      expected += "\n<!-- release-sponsors -->\n"
      if sponsorship[:logo]
        expected += if platform == :github
          "[![Sponsor](https://github.com/sponsor.png?size=64)](https://github.com/sponsor)\n"
        else
          "[![Sponsor](https://example.com/sponsor.png)](https://opencollective.com/sponsor)\n"
        end
      end
      expected += "<!-- /release-sponsors -->\n"
      expect(readme.read).to eq(expected)
    end
  end

  describe "profile data" do
    # Keep each memoised helper with its type signature.
    # rubocop:disable RSpec/ScatteredLet
    sig { returns(Pathname) }
    let(:readme) { mktmpdir/"README.md" }

    sig { returns(Homebrew::DevCmd::UpdateSponsors) }
    let(:command) { described_class.new([]) }

    sig { returns(Sponsors::Record) }
    let(:sponsor) do
      {
        name: "Sponsor", type: "Organization", monthly_amount: 1000, tier_descriptions: [],
        logo: "https://example.com/logo.png", url: "https://example.com/sponsor"
      }
    end
    # rubocop:enable RSpec/ScatteredLet

    before do
      stub_const("HOMEBREW_REPOSITORY", readme.dirname)
      readme.write "Homebrew is generously supported by Old Sponsor.\n"
      allow(GitHub).to receive_messages(
        sponsorship_tiers: [{ monthly_amount: 1000, description: "Name and logo in our README" }],
        sponsorships:      [{
          name: "Small Sponsor", login: "small", type: "User", monthly_amount: 1, tier_description: ""
        }],
      )
      allow(Sponsors).to receive(:patreon).and_return([sponsor])
      allow(command).to receive(:system_command).and_return(
        instance_double(SystemCommand::Result, status: instance_double(Process::Status, success?: false)),
      )
      allow(command).to receive(:puts)
      allow(command).to receive(:opoo)
    end

    test_each([nil, 0]) do |recurring_amount|
      it "updates all platforms with a GitHub gift and recurring amount #{recurring_amount.inspect}" do
        allow(GitHub).to receive(:sponsorships).and_return(
          recurring_amount.nil? ? [] : [{
            name: "Recurring Sponsor", login: "recurring", type: "User",
            monthly_amount: recurring_amount, tier_description: ""
          }],
        )
        allow(Sponsors).to receive_messages(
          github_one_time: [sponsor.merge(name: "Gift Sponsor")],
          open_collective: [sponsor.merge(name: "Collective Sponsor")],
        )

        command.run

        expect(readme.read).to include(
          "[Gift Sponsor](https://example.com/sponsor) and " \
          "[many others](https://github.com/sponsors/Homebrew#sponsors) via [GitHub Sponsors]",
          "[Sponsor](https://example.com/sponsor) and [many others](https://www.patreon.com/homebrew) via [Patreon]",
          "[Collective Sponsor](https://example.com/sponsor) and " \
          "[many others](https://opencollective.com/homebrew/transactions?kind=ADDED_FUNDS&kind=CONTRIBUTION) " \
          "via [Open Collective]",
        )
      end
    end

    test_each([:patreon, :open_collective].product([[], [0]])) do |platform, github_amounts|
      it "recognises #{platform} sponsors with GitHub amounts #{github_amounts}" do
        allow(GitHub).to receive(:sponsorships).and_return(github_amounts.map do |amount|
          { name: "Sponsor", login: "sponsor", type: "User", monthly_amount: amount, tier_description: "" }
        end)
        allow(Sponsors).to receive_messages(
          github_one_time: github_amounts.map { |amount| sponsor.merge(monthly_amount: amount) },
          patreon:         [],
          open_collective: [],
        )
        allow(Sponsors).to receive(platform).and_return([sponsor])

        command.run

        expect(readme.read).to include(
          "[Sponsor](https://example.com/sponsor) and [many others](",
          "via [#{(platform == :patreon) ? "Patreon" : "Open Collective"}]",
          "[![Sponsor](https://example.com/logo.png)](https://example.com/sponsor)",
        )
      end
    end

    test_each([[], [0]].product([[], [0]])) do |recurring_amounts, other_amounts|
      it "rejects missing amounts across providers with recurring #{recurring_amounts} and other #{other_amounts}" do
        allow(GitHub).to receive(:sponsorships).and_return(recurring_amounts.map do |amount|
          { name: "Sponsor", login: "sponsor", type: "User", monthly_amount: amount, tier_description: "" }
        end)
        sponsorships = other_amounts.map { |amount| sponsor.merge(monthly_amount: amount) }
        allow(Sponsors).to receive_messages(
          github_one_time: sponsorships,
          patreon:         sponsorships,
          open_collective: sponsorships,
        )

        expect { command.run }.to raise_error(SystemExit)
          .and output(/No sponsorship amounts found! Ensure you have sufficient permissions!/).to_stderr
        expect(readme.read).to eq("Homebrew is generously supported by Old Sponsor.\n")
      end
    end

    it "groups recurring and one-time sponsors by platform and deduplicates names within each platform" do
      sponsor[:name] = "Shared Sponsor"
      allow(GitHub).to receive(:sponsorships).and_return([{
        name: "Shared Sponsor", login: "shared", type: "User", monthly_amount: 1000, tier_description: ""
      }])
      allow(Sponsors).to receive_messages(
        github_one_time: [sponsor, sponsor.merge(name: "Gift Sponsor")],
        open_collective: [sponsor, sponsor],
      )

      command.run
      command.run

      expect(readme.read).to eq(<<~MARKDOWN)
        Homebrew is generously supported by:

        - [Shared Sponsor](https://example.com/sponsor), [Gift Sponsor](https://example.com/sponsor) and [many others](https://github.com/sponsors/Homebrew#sponsors) via [GitHub Sponsors](https://github.com/sponsors/Homebrew).
        - [Shared Sponsor](https://example.com/sponsor) and [many others](https://opencollective.com/homebrew/transactions?kind=ADDED_FUNDS&kind=CONTRIBUTION) via [Open Collective](https://opencollective.com/homebrew).
        - [Shared Sponsor](https://example.com/sponsor) and [many others](https://www.patreon.com/homebrew) via [Patreon](https://www.patreon.com/homebrew).

        <!-- release-sponsors -->
        [![Shared Sponsor](https://github.com/shared.png?size=64)](https://github.com/shared)
        [![Shared Sponsor](https://example.com/logo.png)](https://example.com/sponsor)
        [![Gift Sponsor](https://example.com/logo.png)](https://example.com/sponsor)
        <!-- /release-sponsors -->
      MARKDOWN
    end

    test_each([:patreon, :open_collective]) do |platform|
      it "sorts #{platform} names by descending monthly contribution" do
        allow(Sponsors).to receive(platform).and_return([
          sponsor.merge(name: "Middle Sponsor", monthly_amount: 2000),
          sponsor.merge(name: "Small Sponsor"),
          sponsor.merge(name: "Largest Sponsor", monthly_amount: 3000),
        ])

        command.run

        expect(readme.read).to include(
          "[Largest Sponsor](https://example.com/sponsor), [Middle Sponsor](https://example.com/sponsor), " \
          "[Small Sponsor](https://example.com/sponsor) and [many others](",
        )
      end
    end

    test_each([:github_one_time, :open_collective, :patreon]) do |platform|
      it "puts displayed logos first on #{platform}, sorting each group by monthly contribution" do
        sponsor[:tier_descriptions] = ["Name in our README"]
        allow(Sponsors).to receive(platform).and_return([
          sponsor.merge(name: "Small Name", monthly_amount: 100),
          sponsor.merge(name: "Small Logo", monthly_amount: 20, tier_descriptions: ["Name and logo in our README"]),
          sponsor.merge(name: "Large Name", monthly_amount: 500),
          sponsor.merge(name: "Large Logo", monthly_amount: 50, tier_descriptions: ["Name and logo in our README"]),
          sponsor.merge(name: "Broken Logo", monthly_amount: 250, logo: "http://example.com/logo.png",
                        tier_descriptions: ["Name and logo in our README"]),
        ])

        command.run

        expect(readme.read).to include(
          "- [Large Logo](https://example.com/sponsor), [Small Logo](https://example.com/sponsor), " \
          "Large Name, Broken Logo, Small Name and [many others](",
        )
      end
    end

    it "sorts GitHub gifts alongside recurring sponsors using one twelfth of their amount" do
      allow(GitHub).to receive_messages(
        sponsorship_tiers: [{ monthly_amount: 50, description: "Name in our README" }],
        sponsorships:      [80, 200].map do |amount|
          { name: "Monthly #{amount}", login: "monthly#{amount}", type: "User",
            monthly_amount: amount, tier_description: "" }
        end,
      )
      allow(Sponsors).to receive(:github_one_time).and_call_original
      allow(GitHub::API).to receive(:paginate_graphql).and_yield("organization" => {
        "sponsorsActivities" => { "nodes" => [{
          "action" => "NEW_SPONSORSHIP", "currentPrivacyLevel" => "PUBLIC", "timestamp" => Date.today.iso8601,
          "sponsorsTier" => { "id" => "tier", "description" => "Name in our README",
                              "monthlyPriceInDollars" => 1200, "isOneTime" => true },
          "sponsor" => { "__typename" => "User", "login" => "gift", "name" => "Gift" }
        }], "pageInfo" => { "hasNextPage" => false } },
      })

      command.run

      expect(readme.read).to include(
        "- Monthly 200, Gift, Monthly 80 and " \
        "[many others](https://github.com/sponsors/Homebrew#sponsors) via [GitHub Sponsors]",
      )
    end

    test_each(["b.well", "J-Swift", "Josh E.", "Contoso (Europe)", "O'Brien"]) do |name|
      it "keeps ordinary punctuation readable in #{name}" do
        sponsor[:name] = name

        command.run

        expect(readme.read).to include(
          "[#{name}](https://example.com/sponsor) and [many others](https://www.patreon.com/homebrew) via [Patreon](https://www.patreon.com/homebrew)",
          "[![#{name}](https://example.com/logo.png)](https://example.com/sponsor)",
        )
      end
    end

    test_each([:patreon, :open_collective]) do |platform|
      it "escapes Markdown, HTML and newlines in #{platform} names" do
        sponsor[:name] = "A [link](https://example.com) \\ & *bold* <img>\r\nCafé’s 日本\tname\u0000"
        escaped_name = <<~'MARKDOWN'.chomp
          A \[link\](https://example.com) \\ \& \*bold\* \<img\> Café’s 日本 name
        MARKDOWN
        allow(Sponsors).to receive(:patreon).and_return([])
        allow(Sponsors).to receive(platform).and_return([sponsor])

        command.run

        expect(readme.read).to include(
          "[#{escaped_name}](https://example.com/sponsor) and [many others](",
          "[![#{escaped_name}](https://example.com/logo.png)](https://example.com/sponsor)",
        )
      end
    end

    test_each([
      "", "http://example.com", "javascript:alert(1)", "//example.com", "https:///sponsor",
      "https://[invalid", "https://example.com/a)b", "https://example.com/a(b",
      "https://example.com/<tag>", "https://example.com/a\\b", "https://example.com/a\nb",
      "https://example.com/a b"
    ].product([:logo, :url])) do |url, field|
      it "keeps name recognition without a logo for unsafe #{field} #{url.inspect}" do
        sponsor[field] = url

        command.run

        expect(readme.read).to include(
          "Sponsor and [many others](https://www.patreon.com/homebrew) via [Patreon](https://www.patreon.com/homebrew)",
          "<!-- release-sponsors -->\n<!-- /release-sponsors -->",
        )
      end
    end
  end

  test_each([false, true]) do |failure|
    it "handles provider failure #{failure} without reporting an unchanged README as a failure" do
      readme = mktmpdir/"README.md"
      stub_const("HOMEBREW_REPOSITORY", readme.dirname)
      readme.write "Homebrew is generously supported by Existing Sponsor.\n"
      command = described_class.new([])
      allow(GitHub).to receive_messages(
        sponsorship_tiers: [{ monthly_amount: 100, description: "Name in our README" }],
        sponsorships:      [{
          name: "Existing Sponsor", login: "existing", type: "User", monthly_amount: 100, tier_description: ""
        }],
      )
      allow(command).to receive(:system_command).and_return(
        instance_double(SystemCommand::Result, status: instance_double(Process::Status, success?: true)),
      )
      if failure
        allow(Sponsors).to receive(:patreon).and_raise("Patreon unavailable")
        expect { command.run }.to raise_error("Patreon unavailable")
        expect(readme.read).to eq("Homebrew is generously supported by Existing Sponsor.\n")
      else
        expect { command.run }.to output("No changes to list of sponsors.\n").to_stdout
      end
    end
  end
end
