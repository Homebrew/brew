# typed: strict
# frozen_string_literal: true

require "utils/sponsors"

RSpec.describe Sponsors do
  describe ".legacy_tier_descriptions" do
    test_each([99, 100, 999, 1000].product(["2026-10-29", "2026-10-30", "2026-10-31", nil])) do |amount, started_at|
      it "honours historical $#{amount} contributions started #{started_at.inspect}" do
        expected = if started_at == "2026-10-29" && amount >= 1000
          ["Name and logo in our README"]
        elsif started_at == "2026-10-29" && amount >= 100
          ["Name in our README"]
        else
          []
        end
        expect(described_class.legacy_tier_descriptions(amount, started_at)).to eq(expected)
      end
    end
  end

  describe ".github_one_time" do
    it "retains an unexpired historical gift when another gift uses the same tier" do
      allow(Date).to receive(:today).and_return(Date.new(2026, 11, 1))
      activities = ["2026-10-17", "2026-11-01"].map do |timestamp|
        {
          "action" => "NEW_SPONSORSHIP", "timestamp" => timestamp, "currentPrivacyLevel" => "PUBLIC",
          "sponsorsTier" => {
            "id" => "tier", "description" => "", "monthlyPriceInDollars" => 1000, "isOneTime" => true
          },
          "sponsor" => { "__typename" => "Organization", "login" => "sponsor", "name" => "Sponsor" }
        }
      end
      allow(GitHub::API).to receive(:paginate_graphql).and_yield("organization" => {
        "sponsorsActivities" => { "nodes" => activities, "pageInfo" => { "hasNextPage" => false } },
      })

      expect(described_class.github_one_time.flat_map { |sponsor| sponsor[:tier_descriptions] })
        .to include("Name and logo in our README")
    end

    test_each([0, 11, 12, 13].product(%w[PUBLIC PRIVATE], [false, true])) do |months_ago, privacy, refunded|
      it "handles a #{months_ago}-month-old #{privacy} donation with refund #{refunded}" do
        activity = {
          "action" => "NEW_SPONSORSHIP", "currentPrivacyLevel" => privacy,
          "timestamp" => (Date.today << months_ago).iso8601,
          "sponsorsTier" => {
            "id" => "tier", "description" => "Name and logo in our README",
            "monthlyPriceInDollars" => 12_000, "isOneTime" => true
          },
          "sponsor" => { "__typename" => "Organization", "login" => "sponsor", "name" => "Sponsor" }
        }
        nodes = if refunded
          [activity, activity.merge("action" => "REFUND", "timestamp" => Date.today.iso8601)]
        else
          [activity]
        end
        allow(GitHub::API).to receive(:paginate_graphql).with(
          a_string_including("includePrivate: false", "sponsorsActivities", "since: $since", "REFUND"),
          variables: { since: "#{Date.today << 12}T00:00:00Z" }, scopes: ["user"],
        ).and_yield("organization" => {
          "sponsorsActivities" => { "nodes" => nodes, "pageInfo" => { "hasNextPage" => false } },
        })

        expected = if months_ago < 12 && privacy == "PUBLIC" && !refunded
          [{ name: "Sponsor", url: "https://github.com/sponsor", logo: "https://github.com/sponsor.png?size=64",
             type: "Organization", monthly_amount: 1000, tier_descriptions: ["Name and logo in our README"] }]
        else
          []
        end
        expect(described_class.github_one_time).to eq(expected)
      end
    end
  end

  describe ".patreon" do
    before do
      ENV["HOMEBREW_PATREON_API_TOKEN"] = "test-token"
      allow(described_class).to receive(:fetch_response).with(
        a_string_including("/campaigns/621883?"), token: "test-token"
      ).and_return({ data: { attributes: { currency: "USD" } } }.to_json)
    end

    test_each([nil, "", " "]) do |token|
      it "explains the required token when it is #{token.inspect}" do
        ENV["HOMEBREW_PATREON_API_TOKEN"] = token

        expect { described_class.patreon }
          .to raise_error("HOMEBREW_PATREON_API_TOKEN must contain a Patreon creator access token.")
      end
    end

    test_each(
      [false, true, nil].product(%w[Paid Declined], [false, true], [false, true],
                                 ["Name and logo in our README", nil]),
    ) do |hidden, status, trial, masked, description|
      it "handles privacy #{hidden.inspect}, #{status}, trial #{trial}, " \
         "masked #{masked}, tier #{description.inspect}" do
        allow(described_class).to receive(:fetch_response).with(
          a_string_including("/members?", "image_url"), token: "test-token"
        ).and_return({
          data:     [{
            attributes:    {
              full_name: masked ? "" : "Sponsor", currently_entitled_amount_cents: 100_000,
              last_charge_status: status, patron_status: "active_patron", is_free_trial: trial
            },
            relationships: { user:                     { data: { id: "user" } },
                             currently_entitled_tiers: { data: [{ id: "retired" }] } },
          }],
          included: [
            { id: "user", type: "user", attributes: {
              hide_pledges: hidden, full_name: "Sponsor", url: "https://www.patreon.com/user",
              image_url: "https://example.com/logo.png"
            } },
            { id: "retired", type: "tier", attributes: {
              amount_cents: 100_000, description:, published: false
            } },
          ],
          links:    {},
        }.to_json)

        expected = if hidden == false && status == "Paid" && !trial && !masked
          [{ name: "Sponsor", url: "https://www.patreon.com/user", logo: "https://example.com/logo.png",
             type: "Organization", monthly_amount: 1000, tier_descriptions: [description.to_s] }]
        else
          []
        end
        expect(described_class.patreon).to eq(expected)
      end
    end
  end

  describe ".open_collective" do
    test_each(%w[ACTIVE PAID CANCELLED REFUNDED].product(%w[MONTHLY YEARLY ONETIME],
                                                         [false, true])) do |status, frequency, hidden|
      it "handles #{status} #{frequency} orders with privacy #{hidden}" do
        allow(described_class).to receive(:fetch_response).and_return({
          data: { account: { orders: {
            totalCount: 1,
            nodes:      [{
              status:, frequency:, processedAt: Date.today.to_s,
              amount: { valueInCents: 120_000, currency: "USD" },
              fromAccount: {
                name: "Sponsor", slug: "sponsor", type: "ORGANIZATION", isIncognito: hidden,
                imageUrl: "https://example.com/logo.png"
              },
              tier: { description: "Name and logo in our README", longDescription: nil }
            }],
          } } },
        }.to_json)

        expected = if !hidden && ((frequency == "MONTHLY" && status == "ACTIVE") ||
                                 (frequency == "YEARLY" && %w[ACTIVE CANCELLED].include?(status)) ||
                                 (frequency == "ONETIME" && status == "PAID"))
          [{ name: "Sponsor", url: "https://opencollective.com/sponsor", logo: "https://example.com/logo.png",
             type: "Organization", monthly_amount: (frequency == "MONTHLY") ? 1200 : 100,
             tier_descriptions: ["Name and logo in our README"] }]
        else
          []
        end
        expect(described_class.open_collective).to eq(expected)
      end
    end

    test_each(%w[sponsor github-sponsors patreon
                 11004-patreon-5c8ee772].product([11, 12])) do |slug, months_ago|
      it "handles #{slug} donations from #{months_ago} months ago across pages" do
        order = {
          status: "PAID", frequency: "ONETIME", processedAt: (Date.today << months_ago).iso8601,
          amount: { valueInCents: 300_000, currency: "USD" },
          fromAccount: { name: "Sponsor", slug:, type: "ORGANIZATION", isIncognito: false, imageUrl: "logo" }
        }
        allow(described_class).to receive(:fetch_response).and_return(
          { data: { account: { orders: { totalCount: 2,
                                         nodes:      [{ status: "CANCELLED", frequency: "MONTHLY" }] } } } }.to_json,
          { data: { account: { orders: { totalCount: 2, nodes: [order] } } } }.to_json,
        )

        expect(described_class.open_collective.map { |sponsor| sponsor[:monthly_amount] })
          .to eq((slug == "sponsor" && months_ago == 11) ? [250] : [])
      end
    end

    it "rejects partial GraphQL responses" do
      allow(described_class).to receive(:fetch_response).and_return({
        errors: [{ message: "Permission denied" }], data: { account: { orders: { totalCount: 0, nodes: [] } } }
      }.to_json)

      expect { described_class.open_collective }.to raise_error(/Could not retrieve Open Collective sponsorships/)
    end
  end
end
