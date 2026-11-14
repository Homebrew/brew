# typed: strict
# frozen_string_literal: true

module Homebrew
  module DevCmd
    class Contributions
      # CSV and Markdown views of collected maintainer activity.
      module Reporting
        extend T::Helpers

        requires_ancestor { Contributions }

        private

        sig {
          params(
            results:                T::Hash[String, T::Hash[String, T::Hash[Symbol, Integer]]],
            grand_totals:           T::Hash[String, T::Hash[Symbol, Integer]],
            user_names:             T::Hash[String, String],
            lead_maintainers:       T::Hash[String, T::Boolean],
            maintainer_since_dates: T::Hash[String, T.nilable(String)],
            from:                   String,
            to:                     String,
          ).returns(String)
        }
        def generate_maintainer_report_csv(results, grand_totals, user_names, lead_maintainers,
                                           maintainer_since_dates, from, to)
          require "csv"

          exempt_usernames = (args.maintainer_exempt || []).map do |username|
            MAINTAINER_USER_RENAMES.fetch(username.downcase, username).downcase
          end.uniq
          unmatched_exempt = exempt_usernames - results.keys.map(&:downcase)
          if unmatched_exempt.present?
            opoo "Exempt usernames not listed in this maintainer report: #{Utils::Text.to_sentence(unmatched_exempt)}."
          end

          period_end = Date.iso8601(to)
          repository_totals = results.to_h do |user, repositories|
            [user.downcase, repositories.transform_values do |counts|
              contribution_count(counts.slice(*MAINTAINER_CONTRIBUTION_TYPES))
            end]
          end
          capped_users = results.filter_map do |user, repositories|
            capped = repositories.values.any? do |counts|
              counts.fetch(:reviews_skipped, 0).positive? || counts.fetch(:merges_skipped, 0).positive? ||
                counts.fetch(:unverified_merges, 0).positive? ||
                counts.slice(*MAINTAINER_CONTRIBUTION_TYPES).values.any? { |count| count >= MAX_CONTRIBUTIONS }
            end
            user.downcase if capped
          end
          activity_end = activity_period_end(period_end)
          activity_start = activity_end.prev_month(ACTIVITY_PERIOD_MONTHS).iso8601
          activity = maintainer_activity_report(activity_start, activity_end.iso8601,
                                                current_report: [from, to, repository_totals, capped_users]) || {}
          previous_reports = previous_maintainer_reports(activity_start)
          # Activity-based recommendations require previous-period data.
          include_potential_role = (activity.present? && previous_reports.present?) || args.maintainer_exempt.present?
          rows = results.sort_by do |user, _|
            qualifying_total = contribution_count(grand_totals.fetch(user).slice(*MAINTAINER_CONTRIBUTION_TYPES))
            [-qualifying_total, user.downcase]
          end
          rows.map! do |user, user_repositories|
            grand_total = grand_totals.fetch(user)
            qualifying_total = contribution_count(grand_total.slice(*MAINTAINER_CONTRIBUTION_TYPES))
            maintainer_since = maintainer_since_dates.fetch(user)
            maintainer_since_date = Date.iso8601(maintainer_since) if maintainer_since
            lead_maintainer = lead_maintainers.key?(user.downcase)
            role = lead_maintainer ? "Lead Maintainer" : "Maintainer"
            user_activity = activity[user.downcase]
            potential_role = if user_activity
              potential_maintainer_role(user, role, maintainer_since_date, period_end, user_activity,
                                        previous_reports)
            end

            exempt = exempt_usernames.include?(user.downcase)
            if exempt && (potential_role == "None" || (potential_role.nil? && role == "Maintainer"))
              potential_role = "Maintainer"
            end

            capped = capped_users.include?(user.downcase)

            [
              user,
              user_names.fetch(user),
              maintainer_since,
              maintainer_since_date ? [(period_end - maintainer_since_date).to_i, 0].max : nil,
              *PRIMARY_REPOS.flat_map do |repository|
                counts = user_repositories.fetch(repository)
                [*counts.values_at(*MAINTAINER_CONTRIBUTION_TYPES),
                 repository_totals.fetch(user.downcase).fetch(repository)]
              end,
              qualifying_total,
              user_activity&.fetch(0),
              user_activity&.fetch(1),
              exempt,
              capped,
              role,
              *(include_potential_role ? [potential_role] : []),
            ]
          end
          CSV.generate do |csv|
            csv << [
              "username", "name", "since", "tenure days",
              *PRIMARY_REPOS.flat_map do |repository|
                repository = repository_name(repository)
                [
                  "#{repository} merged", (repository == "brew") ? "brew first approvals" : "#{repository} approvals",
                  "#{repository} issues closed", "#{repository} total"
                ]
              end,
              "total", "maintainer met", "lead met", "maintainer exempt", "capped", "role",
              *(include_potential_role ? ["potential new role"] : [])
            ]
            rows.each { |row| csv << row }
          end
        end

        sig { params(csv: String, from: String, to: String).returns(String) }
        def generate_maintainer_report_summary(csv, from, to)
          require "csv"

          rows = CSV.parse(csv, headers: true).filter_map { |row| row.to_h if row.is_a?(CSV::Row) }
          repository_totals = rows.to_h do |row|
            [row.fetch("username").downcase, PRIMARY_REPOS.to_h do |repository|
              [repository, Integer(row.fetch("#{repository_name(repository)} total"))]
            end]
          end
          capped_users = rows.filter_map { |row| row.fetch("username").downcase if row["capped"] == "true" }
          current_report = [from, to, repository_totals, capped_users]
          period_end = Date.iso8601(to)
          activity_end = activity_period_end(period_end)
          activity_start = activity_end.prev_month(ACTIVITY_PERIOD_MONTHS)
          summary = [
            "## Maintainer contribution summary",
            "",
            "Contribution counts cover #{summary_period(Date.iso8601(from), period_end)}.",
            "",
            "### Latest completed quarter: #{summary_period(activity_start, activity_end)}",
            "",
            *maintainer_activity_summary(
              rows, maintainer_activity_totals(activity_start.iso8601, activity_end.iso8601, current_report:)
            ),
          ]
          if activity_end < period_end
            summary += [
              "",
              "### Current quarter: #{summary_period(activity_end, activity_end.next_month(ACTIVITY_PERIOD_MONTHS))}",
              "",
              "Progress through #{period_end.prev_day.iso8601}; the quarter is still in progress.",
              "",
              *maintainer_activity_summary(rows,
                                           maintainer_activity_totals(activity_end.iso8601, to, current_report:)),
            ]
          end
          summary += [
            "",
            "Maintainer activity requires #{MAINTAINER_ACTIVITY_THRESHOLD} meaningful maintainer contributions per " \
            "quarter. Lead activity requires at least #{LEAD_REPOSITORY_ACTIVITY_THRESHOLD} in " \
            "#{LEAD_ACTIVITY_REPOSITORIES} repositories. Counts in `capped` rows are lower bounds. " \
            "Exemptions retain Maintainer status but don't waive Lead Maintainer requirements. " \
            "Role changes also consider the other " \
            "[governance criteria](https://docs.brew.sh/Homebrew-Governance).",
          ]
          "#{summary.join("\n")}\n"
        end

        sig {
          params(
            rows:   T::Array[T::Hash[String, T.nilable(String)]],
            totals: T.nilable(T::Hash[String, [T::Hash[String, Integer], T::Boolean]]),
          ).returns(T::Array[String])
        }
        def maintainer_activity_summary(rows, totals)
          return ["Activity is unknown without contiguous reports for this period."] if totals.nil?

          maintainer_activity = []
          lead_activity = []
          exempt = []
          table = []
          rows.each do |row|
            username = row.fetch("username").to_s
            user_totals, capped = totals[username.downcase]
            maintainer_met, lead_met = activity_met(user_totals.values) if user_totals
            # An exemption only changes the outcome for Maintainers below the threshold.
            maintainer_exempt = row["maintainer exempt"] == "true" && !maintainer_met
            if maintainer_exempt
              exempt << username
            else
              maintainer_activity << maintainer_met
            end
            lead_maintainer = row["role"] == "Lead Maintainer"
            lead_activity << lead_met if lead_maintainer
            maintainer_below = !maintainer_exempt && !maintainer_met
            lead_below = lead_maintainer && !lead_met
            next if !maintainer_below && !lead_below

            cells = if user_totals
              gaps = []
              if maintainer_below
                gaps << "#{MAINTAINER_ACTIVITY_THRESHOLD - user_totals.values.sum} more for Maintainer activity"
              end
              if lead_below
                below = user_totals.filter_map do |repository, total|
                  next if total >= LEAD_REPOSITORY_ACTIVITY_THRESHOLD

                  "#{repository_name(repository)}: #{LEAD_REPOSITORY_ACTIVITY_THRESHOLD - total} more"
                end
                needed = LEAD_ACTIVITY_REPOSITORIES - (user_totals.length - below.length)
                gaps << "Lead: reach #{LEAD_REPOSITORY_ACTIVITY_THRESHOLD} in #{needed} more " \
                        "#{Utils.pluralize("repositor", needed, plural: "ies", singular: "y")} (#{below.join(", ")})"
              end
              gaps << "capped counts are lower bounds" if capped
              [*user_totals.values, user_totals.values.sum, gaps.join("; ")]
            else
              [*Array.new(PRIMARY_REPOS.length + 1, "unknown"), "Incomplete history"]
            end
            table << "| #{[username, *cells].join(" | ")} |"
          end

          summary = [
            "- Maintainer activity: **#{maintainer_activity.count(true)}/#{maintainer_activity.length} met**; " \
            "#{maintainer_activity.count(nil)} unknown#{"; exempt: #{exempt.join(", ")}" if exempt.any?}.",
          ]
          unless lead_activity.empty?
            summary << "- Lead activity (Lead Maintainers): **#{lead_activity.count(true)}/#{lead_activity.length} " \
                       "met**; #{lead_activity.count(nil)} unknown."
          end
          return summary if table.empty?

          repositories = PRIMARY_REPOS.map { |repository| repository_name(repository).capitalize }
          summary + [
            "",
            "| Maintainer | #{repositories.join(" | ")} | Total | Numerical gap |",
            "| --- |#{" ---: |" * (repositories.length + 1)} --- |",
            *table,
          ]
        end

        sig { params(totals: T::Hash[String, T::Hash[Symbol, Integer]]).returns(String) }
        def generate_csv(totals)
          require "csv"

          CSV.generate do |csv|
            csv << %w[username repo authored merged PRs reviews coauthored total]

            totals.sort_by { |_, counts| -contribution_count(counts.slice(*QUALIFYING_CONTRIBUTION_TYPES)) }
                  .each do |user, total|
              csv << grand_total_row(user, total)
            end
          end
        end

        sig { params(user: String, grand_total: T::Hash[Symbol, Integer]).returns(T::Array[T.any(String, T.nilable(Integer))]) }
        def grand_total_row(user, grand_total)
          grand_totals = grand_total.slice(*CONTRIBUTION_TYPES.keys).values
          qualifying_total = contribution_count(grand_total.slice(*QUALIFYING_CONTRIBUTION_TYPES))
          [user, "all", *grand_totals, qualifying_total]
        end

        sig { params(repository: String).returns(String) }
        def repository_name(repository)
          repository.delete_prefix("Homebrew/").delete_prefix("homebrew-")
        end

        sig { params(from: Date, to: Date).returns(String) }
        def summary_period(from, to)
          "#{from.iso8601} through #{to.prev_day.iso8601}"
        end
      end
    end
  end
end
