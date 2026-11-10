# typed: strict
# frozen_string_literal: true

require "open3"
require "ripper"

module Utils
  # Checks that changes to vendored gem integrity rules bump VENDOR_VERSION.
  module VendorVersionCheck
    sig { params(base_source: String, current_source: String).returns(T::Boolean) }
    def self.integrity_rules_changed?(base_source:, current_source:)
      integrity_rule_tokens(base_source) != integrity_rule_tokens(current_source)
    end

    sig { params(base_source: String, current_source: String).returns(T::Boolean) }
    def self.vendor_version_bumped_for_integrity_changes?(base_source:, current_source:)
      return true unless integrity_rules_changed?(base_source:, current_source:)

      vendor_version(current_source) > vendor_version(base_source)
    end

    sig { params(source: String).returns(Integer) }
    def self.vendor_version(source)
      match = source.match(/^\s*VENDOR_VERSION = (\d+)$/)
      raise "Failed to read VENDOR_VERSION" if match.nil?

      match.captures.fetch(0).to_i
    end
    private_class_method :vendor_version

    sig { params(source: String).returns(T::Array[T::Array[String]]) }
    def self.integrity_rule_tokens(source)
      lines = source.lines
      method_start = lines.index { |line| line.match?(/^\s*def self\.gem_integrity_check_required\?/) }
      method_source = if method_start.nil?
        ""
      else
        indent = lines.fetch(method_start)[/\A\s*/]
        raise "Failed to find the indentation of the gem integrity check" if indent.nil?

        method_end = ((method_start + 1)...lines.length).find do |line_number|
          lines.fetch(line_number).match?(/\A#{Regexp.escape(indent)}end\s*\z/)
        end
        raise "Failed to find the end of the gem integrity check" if method_end.nil?

        method_lines = lines[method_start..method_end]
        raise "Failed to read the gem integrity check" if method_lines.nil?

        method_lines.join
      end

      extensions_start = lines.index { |line| line.match?(/^\s*JSON_NATIVE_EXTENSIONS\s*=/) }
      extensions_source = if extensions_start.nil?
        ""
      else
        extensions_end = (extensions_start...lines.length).find do |line_number|
          lines.fetch(line_number).include?(".freeze")
        end
        raise "Failed to find the JSON native extension list" if extensions_end.nil?

        extension_lines = lines[extensions_start..extensions_end]
        raise "Failed to read the JSON native extension list" if extension_lines.nil?

        extension_lines.join
      end

      [ruby_tokens(method_source), ruby_tokens(extensions_source)]
    end

    sig { params(source: String).returns(T::Array[String]) }
    def self.ruby_tokens(source)
      Ripper.lex(source).filter_map do |(_, type, token, _)|
        next if [
          :on_comment,
          :on_embdoc_beg,
          :on_embdoc,
          :on_embdoc_end,
          :on_ignored_nl,
          :on_nl,
          :on_sp,
        ].include?(type)

        "#{type}:#{token}"
      end
    end
    private_class_method :ruby_tokens
  end
end

if $PROGRAM_NAME == __FILE__
  base_ref = ARGV.fetch(0) { raise ArgumentError, "A base Git ref must be provided" }
  base_source, status = Open3.capture2(
    "git",
    "show",
    "#{base_ref}:Library/Homebrew/utils/gem_setup.rb",
  )
  raise "Failed to read the base gem setup" unless status.success?

  current_source = File.read("Library/Homebrew/utils/gem_setup.rb")
  unless Utils::VendorVersionCheck.vendor_version_bumped_for_integrity_changes?(
    base_source:,
    current_source:,
  )
    raise "VENDOR_VERSION must be bumped when gem integrity rules change"
  end
end
