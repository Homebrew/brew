# typed: strict
# frozen_string_literal: true

require "utils/curl"
require "utils/github"
require "date"
require "uri"

# Read sponsor entitlements for the Homebrew README.
module Sponsors
  BENEFIT_MONTHS = 12
  LEGACY_TIERS_RETIRED_ON = Date.new(2026, 10, 30).freeze
  LEGACY_NAME_AMOUNT = 100
  LEGACY_LOGO_AMOUNT = 1000

  Record = T.type_alias do
    {
      name: String, url: String, logo: String, type: String,
      monthly_amount: Integer, tier_descriptions: T::Array[String]
    }
  end

  sig { params(amount: Integer, started_at: T.nilable(String)).returns(T::Array[String]) }
  def self.legacy_tier_descriptions(amount, started_at)
    return [] if started_at.blank? || Date.parse(started_at) >= LEGACY_TIERS_RETIRED_ON

    if amount >= LEGACY_LOGO_AMOUNT
      ["Name and logo in our README"]
    elsif amount >= LEGACY_NAME_AMOUNT
      ["Name in our README"]
    else
      []
    end
  end

  sig { returns(T::Array[Record]) }
  def self.github_one_time
    query = <<~GRAPHQL
      query($since: DateTime!, $after: String) {
        organization(login: "Homebrew") {
          sponsorsActivities(first: 100, after: $after, since: $since, includePrivate: false,
                             actions: [NEW_SPONSORSHIP, REFUND]) {
            pageInfo { hasNextPage endCursor }
            nodes {
              action timestamp currentPrivacyLevel
              sponsorsTier { id description monthlyPriceInDollars isOneTime }
              sponsor {
                __typename
                ... on User { login name }
                ... on Organization { login name }
              }
            }
          }
        }
      }
    GRAPHQL
    activities = []
    GitHub::API.paginate_graphql(query, variables: { since: "#{Date.today << BENEFIT_MONTHS}T00:00:00Z" },
                                        scopes:    ["user"]) do |result|
      page = result.fetch("organization").fetch("sponsorsActivities")
      activities.concat(page.fetch("nodes").compact)
      page.fetch("pageInfo")
    end

    activities.group_by { |activity| [activity.dig("sponsor", "login"), activity.dig("sponsorsTier", "id")] }
              .values.flat_map do |events|
      # A refund invalidates earlier gifts at this tier until another gift is made.
      refunded_at = events.filter_map { |event| event["timestamp"] if event["action"] == "REFUND" }.max
      events.filter_map do |activity|
        next if activity["action"] != "NEW_SPONSORSHIP" || activity["currentPrivacyLevel"] != "PUBLIC"
        next if activity["timestamp"].blank? || (Date.parse(activity["timestamp"]) >> BENEFIT_MONTHS) <= Date.today
        next if refunded_at && activity["timestamp"] <= refunded_at

        tier = activity["sponsorsTier"]
        sponsor = activity["sponsor"]
        next if !tier || !tier["isOneTime"] || !sponsor

        amount = tier.fetch("monthlyPriceInDollars")
        {
          name: sponsor["name"].presence || sponsor.fetch("login"), url: "https://github.com/#{sponsor.fetch("login")}",
          logo: "https://github.com/#{sponsor.fetch("login")}.png?size=64", type: sponsor.fetch("__typename"),
          monthly_amount: amount / BENEFIT_MONTHS,
          tier_descriptions: ([tier.fetch("description")] +
                              legacy_tier_descriptions(amount, activity["timestamp"])).uniq
        }
      end
    end
  end

  sig { returns(T::Array[Record]) }
  def self.patreon
    token = ENV.fetch("HOMEBREW_PATREON_API_TOKEN", "")
    raise "HOMEBREW_PATREON_API_TOKEN must contain a Patreon creator access token." if token.blank?

    campaign_url = "https://www.patreon.com/api/oauth2/v2/campaigns/621883"
    campaign = JSON.parse(fetch_response("#{campaign_url}?fields%5Bcampaign%5D=currency", token:))
    raise "Expected the Homebrew Patreon campaign currency to be USD." if
      campaign.fetch("data").fetch("attributes").fetch("currency") != "USD"

    parameters = {
      "include"        => "currently_entitled_tiers,user",
      "fields[member]" => "full_name,currently_entitled_amount_cents,last_charge_status,is_free_trial," \
                          "pledge_relationship_start",
      "fields[tier]"   => "amount_cents,description",
      "fields[user]"   => "full_name,hide_pledges,url,image_url",
      "page[count]"    => "1000",
    }
    sponsors = []
    loop do
      result = JSON.parse(fetch_response("#{campaign_url}/members?#{URI.encode_www_form(parameters)}", token:))
      included = result.fetch("included", []).to_h do |resource|
        [[resource.fetch("type"), resource.fetch("id")], resource]
      end
      sponsors.concat(result.fetch("data").filter_map do |member|
        attributes = member.fetch("attributes")
        next if attributes["last_charge_status"] != "Paid" || attributes["is_free_trial"] ||
                attributes["full_name"].blank?

        user = included.dig(["user", member.dig("relationships", "user", "data", "id")], "attributes")
        next if !user || user["hide_pledges"] != false || user["full_name"].blank? || user["url"].blank?

        amount = attributes.fetch("currently_entitled_amount_cents").to_i
        next unless amount.positive?

        descriptions = member.fetch("relationships").fetch("currently_entitled_tiers").fetch("data").map do |tier|
          included.fetch(["tier", tier.fetch("id")]).fetch("attributes")["description"].to_s
        end
        {
          name: user.fetch("full_name"), url: user.fetch("url"), logo: user["image_url"].to_s,
          type: descriptions.join("\n").match?(/\bindividuals only\b/i) ? "User" : "Organization",
          monthly_amount: amount / 100,
          tier_descriptions: (descriptions +
                              legacy_tier_descriptions(amount / 100, attributes["pledge_relationship_start"])).uniq
        }
      end)
      cursor = result.dig("meta", "pagination", "cursors", "next")
      break if cursor.blank?

      parameters["page[cursor]"] = cursor
    end
    sponsors
  end

  sig { returns(T::Array[Record]) }
  def self.open_collective
    sponsors = []
    offset = 0
    loop do
      query = <<~GRAPHQL
        query {
          account(slug: "homebrew") {
            orders(limit: 100, offset: #{offset}) {
              totalCount
              nodes {
                status frequency createdAt processedAt lastChargedAt
                amount { valueInCents currency }
                fromAccount { name slug type isIncognito imageUrl(height: 64) }
                tier { description longDescription }
              }
            }
          }
        }
      GRAPHQL
      result = JSON.parse(fetch_response("https://api.opencollective.com/graphql/v2?#{URI.encode_www_form(query:)}"))
      raise "Could not retrieve Open Collective sponsorships: #{result.fetch("errors")}" if result["errors"].present?

      orders = result.fetch("data").fetch("account").fetch("orders")
      sponsors.concat(orders.fetch("nodes").filter_map do |order|
        frequency = order.fetch("frequency")
        case frequency
        when "MONTHLY"
          next if order["status"] != "ACTIVE"
        when "YEARLY", "ONETIME"
          if frequency == "YEARLY"
            next if order["status"] != "ACTIVE" && order["status"] != "CANCELLED"
          elsif order["status"] != "PAID"
            next
          end
          paid_at = order["lastChargedAt"] || order["processedAt"]
          next if paid_at.blank? || (Date.parse(paid_at) >> BENEFIT_MONTHS) <= Date.today
        else
          next
        end

        account = order["fromAccount"]
        next if !account || account["isIncognito"] != false || account["name"].blank?

        slug = account.fetch("slug")
        # These accounts transfer donations collected on the other platforms.
        next if %w[github-sponsors patreon 11004-patreon-5c8ee772].include?(slug)

        amount = order.fetch("amount")
        raise "Expected Open Collective sponsorship amounts in USD." if amount.fetch("currency") != "USD"

        amount_in_dollars = amount.fetch("valueInCents").to_i / 100
        {
          name: account.fetch("name"), url: "https://opencollective.com/#{slug}", logo: account["imageUrl"].to_s,
          type: (account["type"] == "INDIVIDUAL") ? "User" : "Organization",
          monthly_amount: amount_in_dollars / ((frequency == "MONTHLY") ? 1 : BENEFIT_MONTHS),
          tier_descriptions: ([order.dig("tier", "description"), order.dig("tier", "longDescription")].compact +
                              legacy_tier_descriptions(
                                amount_in_dollars / ((frequency == "YEARLY") ? BENEFIT_MONTHS : 1),
                                (frequency == "ONETIME") ? order["processedAt"] : order["createdAt"],
                              )).uniq
        }
      end)
      offset += orders.fetch("nodes").length
      break if offset >= orders.fetch("totalCount")

      raise "Open Collective returned an incomplete sponsorship list." if orders.fetch("nodes").empty?
    end
    sponsors
  end

  sig { params(url: String, token: T.nilable(String)).returns(String) }
  def self.fetch_response(url, token: nil)
    headers = ["--header", "Content-Type: application/json"]
    headers += ["--header", "Authorization: Bearer #{token}"] if token
    response = Utils::Curl.curl_output(url, "--fail", *headers, secrets: [token].compact)
    raise "Could not retrieve sponsorships from #{URI(url).host}." unless response.status.success?

    response.stdout
  end
end
