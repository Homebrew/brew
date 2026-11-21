# typed: strict
# frozen_string_literal: true

require "json"
require "utils/tty"
require "vulns/scanner"
require "vulns/vulnerability"

module Homebrew
  module Vulns
    module Output
      DEFAULT_MAX_SUMMARY = 60

      sig {
        params(
          results:      Scanner::Results,
          max_summary:  Integer,
          list_skipped: T::Boolean,
          io:           T.any(IO, StringIO),
        ).void
      }
      def self.text(results, max_summary: DEFAULT_MAX_SUMMARY, list_skipped: false, io: $stdout)
        checked_packages = Utils.pluralize("package", results.checked, include_count: true)
        io.puts "Checking #{checked_packages} for vulnerabilities..."
        if results.skipped.positive?
          skipped_packages = Utils.pluralize("package", results.skipped, include_count: true)
          msg = "(#{skipped_packages} skipped - no supported source URL)"
          if list_skipped && results.skipped_formulae.any?
            io.puts "#{msg}:"
            results.skipped_formulae.sort.each { |f| io.puts "  #{sanitize(f)}" }
          else
            io.puts msg
          end
        end
        io.puts

        open = results.findings.select { |f| f.open.any? }
        patched = results.findings.select { |f| f.patched.any? }

        if open.empty?
          io.puts patched.empty? ? "No vulnerabilities found." : "No open vulnerabilities found."
          patched_summary(patched, io:)
          return
        end

        total = 0
        open.sort_by { |f| -f.open.map(&:severity_level).max }.each do |f|
          io.puts "#{sanitize(f.name)} (#{sanitize(f.version)})"
          f.open.sort_by { |v| -v.severity_level }.each do |v|
            total += 1
            line = "  #{sanitize(v.id)} (#{colorize_severity(v.severity, v.severity_display)})"
            summary = v.summary
            if summary
              summary_text = truncate(sanitize(summary), max_summary)
              line += " - #{summary_text}"
            end
            io.puts line
            if v.fixed_versions.any?
              fixed_versions = v.fixed_versions.map { |s| sanitize(s) }.join(", ")
              io.puts "    Fixed in: #{fixed_versions}"
            end
          end
          io.puts
        end

        vulnerabilities = Utils.pluralize("vulnerabilit", total, plural: "ies", singular: "y",
include_count: true)
        packages = Utils.pluralize("package", open.size, include_count: true)
        io.puts "Found #{vulnerabilities} in #{packages}"
        patched_summary(patched, io:)
      end

      sig { params(results: Scanner::Results, unscanned_formulae: T::Hash[String, String], io: T.any(IO, StringIO)).void }
      def self.json(results, unscanned_formulae: {}, io: $stdout)
        data = {
          findings:              results.findings.map do |f|
            {
              formula:         f.name,
              version:         f.version,
              tag:             f.tag,
              repo_url:        f.repo_url,
              vulnerabilities: f.open.map { |v| vuln_json(v) },
              patched:         f.patched.map { |v| vuln_json(v) },
            }
          end,
          skipped_formulae:      results.skipped_formulae,
          checked:               results.checked,
          complete:              results.skipped_formulae.empty? &&
                                 results.outdated_without_sbom.empty? && unscanned_formulae.empty?,
          outdated_without_sbom: results.outdated_without_sbom,
          unscanned_formulae:,
        }
        io.puts JSON.pretty_generate(data)
      end

      sig { params(vuln: Vulnerability).returns(T::Hash[Symbol, T.untyped]) }
      private_class_method def self.vuln_json(vuln)
        {
          id:             vuln.id,
          severity:       vuln.severity_display,
          summary:        vuln.summary,
          aliases:        vuln.aliases,
          fixed_versions: vuln.fixed_versions,
        }
      end

      sig { params(patched: T::Array[Scanner::Finding], io: T.any(IO, StringIO)).void }
      private_class_method def self.patched_summary(patched, io:)
        return if patched.empty?

        total = patched.sum { |f| f.patched.size }
        io.puts
        io.puts "#{total} resolved by formula patches (not counted; pass --no-ignore-patches to include):"
        patched.sort_by(&:name).each do |f|
          patched_versions = f.patched.map { |v| sanitize(v.id) }.join(", ")
          io.puts "  #{sanitize(f.name)}: #{patched_versions}"
        end
      end

      sig { params(text: String, max: Integer).returns(String) }
      private_class_method def self.truncate(text, max)
        return text if max <= 0 || text.length <= max

        "#{text.slice(0, max)}..."
      end

      OSC_7BIT = /\e\][^\a\e]*(?:\a|\e\\)/
      OSC_8BIT = /\u{009d}[^\a\u{009c}]*(?:\a|\u{009c})/
      CSI_7BIT = %r{\e\[[0-?]*[ -/]*[@-~]}
      CSI_8BIT = %r{\u{009b}[0-?]*[ -/]*[@-~]}
      private_constant :OSC_7BIT, :OSC_8BIT, :CSI_7BIT, :CSI_8BIT

      sig { params(text: T.untyped).returns(String) }
      private_class_method def self.sanitize(text)
        text.to_s
            .gsub(OSC_7BIT, "")
            .gsub(OSC_8BIT, "")
            .gsub(CSI_7BIT, "")
            .gsub(CSI_8BIT, "")
            .delete("\e\b\r\a\u{0080}-\u{009f}")
      end

      sig { params(severity: T.nilable(Symbol), display: String).returns(String) }
      private_class_method def self.colorize_severity(severity, display)
        case severity
        when :critical then "#{Tty.bold}#{Tty.red}#{display}#{Tty.reset}"
        when :high then "#{Tty.red}#{display}#{Tty.reset}"
        when :medium then "#{Tty.yellow}#{display}#{Tty.reset}"
        when :low then "#{Tty.green}#{display}#{Tty.reset}"
        else display
        end
      end
    end
  end
end
