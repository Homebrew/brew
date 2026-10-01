# typed: strict
# frozen_string_literal: true

require "embedded_patch"
require "data_patch"
require "external_patch"
require "string_patch"
require "local_patch"
require "utils/path"
require "sandbox"

# Helper module for creating patches.
module Patch
  CVE_PATTERN = /CVE-?(\d{4})-(\d{4,})/i
  GHSA_PATTERN = /\AGHSA(-[23456789cfghjmpqrvwx]{4}){3}\z/
  OSV_PATTERN = /\AOSV-\d{4}-\d+\z/
  # CycloneDX `pedigree.patches.type` values applicable to source diffs.
  # `monkey` is omitted: it describes runtime modification, which `patch do` cannot express.
  # Keep in sync with `PATCH_TYPES` in `Library/Homebrew/rubocops/patches.rb`.
  TYPES = T.let({
    unofficial:  "A patch that has not been developed by the upstream maintainers " \
                 "(e.g. a Homebrew- or distribution-specific build fix).",
    backport:    "A patch that takes code from a newer version of the software and " \
                 "applies it to the older version Homebrew ships (e.g. an unreleased " \
                 "upstream security fix).",
    cherry_pick: "A patch created by selectively applying upstream commits that are " \
                 "not strictly from a newer release (e.g. a fix from a maintenance branch).",
  }.freeze, T::Hash[Symbol, String])

  sig { params(strings: String).returns(T::Array[String]) }
  def self.extract_cves(*strings)
    strings.flat_map { |s| s.scan(CVE_PATTERN) }
           .map { |year, id| "CVE-#{year}-#{id}" }
           .uniq
  end

  sig { params(id: String).returns(String) }
  def self.resolves_type(id)
    return "security" if id.match?(/\ACVE-\d{4}-\d{4,}\z/) || id.match?(GHSA_PATTERN) || id.match?(OSV_PATTERN)

    "defect"
  end

  # Reject patch target paths (absolute or `..`-traversing) that escape the staged source tree.
  sig { params(text: String, strip: T.any(Symbol, String), base: Pathname).void }
  def self.ensure_targets_within!(text, strip:, base:)
    # `patch` writes nothing for empty input.
    return if text.blank?

    # Resolve targets with `patch --dry-run` so containment matches what `patch`
    # actually writes, covering `Index:`/`====` and non-selected context headers.
    output = Sandbox.capture("patch", args: ["-g", "0", "-f", "-#{strip}", "--dry-run"],
                                      input: text, read_paths: [base], chdir: base,
                                      env: { "LC_ALL" => "C", "LANG" => "C", "QUOTING_STYLE" => "literal" },
                                      must_succeed: false, print_stderr: false).merged_output

    # No output means `patch` named nothing, not that it will write nothing, so
    # fail closed. An ed-format patch reports nothing at all and lands here.
    raise "Unsupported patch format: no target paths to verify." if output.blank?

    output.each_line do |line|
      # `patch` names a target for a hunk it applies and a reject file it writes.
      line = line.chomp
      named = line[/\A(?:patching|checking) (?:file|symbolic link) (.+)\z/, 1] ||
              line[/hunks? ignored while patching (.+)\z/, 1]
      next if named.nil?

      # GNU patch appends the source it read, so a rename, copy or read names two
      # paths. A filename may contain that text, so check every reading of it.
      suffixed = named.match(/\A(.+) \((?:already )?(?:renamed|copied|read) from (.+)\)\z/)
      targets = [named, *suffixed&.captures].uniq

      targets.each do |target|
        message = "Patch target path escapes the staged source tree: #{target}"

        # Reject rather than resolve: `Pathname#/` collapses a `..` after a
        # symlinked directory before anything below can resolve it.
        target_path = Pathname(target)
        raise message if target_path.absolute? || target_path.each_filename.include?("..")

        Utils::Path.ensure_child_of!(base, base/target, message:)
      end
    end
  end

  sig { params(text: String, strip: T.any(Symbol, String), base: Pathname).void }
  def self.apply(text, strip:, base:)
    ensure_targets_within!(text, strip:, base:)
    Sandbox.capture("patch", args: ["-g", "0", "-f", "-#{strip}"], input: text,
                             write_paths: [base], chdir: base, print_stdout: true)
  end

  sig {
    params(
      strip: T.any(Symbol, String),
      src:   T.nilable(T.any(Symbol, String)),
      block: T.nilable(T.proc.bind(Resource::Patch).void),
    ).returns(T.any(EmbeddedPatch, ExternalPatch))
  }
  def self.create(strip, src, &block)
    case strip
    when :DATA
      DATAPatch.new(:p1)
    when String
      StringPatch.new(:p1, strip)
    when Symbol
      case src
      when :DATA
        DATAPatch.new(strip)
      when String
        StringPatch.new(strip, src)
      else
        external_patch = ExternalPatch.new(strip, &block)
        resource = external_patch.resource
        if (file = resource.file)
          raise ArgumentError, "Patch cannot have both `file` and `url`." if resource.url.present?
          raise ArgumentError, "Patch cannot use `sha256` with `file`." if resource.checksum
          raise ArgumentError, "Patch cannot use `apply` with `file`." if resource.patch_files.present?

          LocalPatch.new(strip, file, resource.directory, resolves: resource.resolves, type: resource.type)
        else
          external_patch
        end
      end
    end
  end
end
