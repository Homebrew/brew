# typed: strict
# frozen_string_literal: true

raise "#{__FILE__} must not be loaded via `require`." if $PROGRAM_NAME != __FILE__

require_relative "global"
require "json"
require "sandbox"

# Keep diagnostics out of the structured result stream.
result_output = $stdout
$stdout = $stderr
require "formula"
payload = JSON.parse($stdin.read)
result = case ARGV.fetch(0)
when "extract"
  require "unpack_strategy"
  path = Pathname(payload.fetch("path"))
  if payload.fetch("strategy") == "UnpackStrategy::Fossil"
    # Fossil may create SQLite journals beside the repository while extracting it.
    FileUtils.cp(path, HOMEBREW_TEMP/"repository.fossil")
    path = HOMEBREW_TEMP/"repository.fossil"
  end
  strategy = if payload.fetch("move")
    UnpackStrategy::Directory.new(path, move: true)
  else
    UnpackStrategy.from_name(payload.fetch("strategy")).new(
      path, ref_type: payload["ref_type"]&.to_sym, ref: payload["ref"], merge_xattrs: payload.fetch("merge_xattrs")
    )
  end
  strategy.extract(to: Pathname(payload.fetch("to")), basename: payload["basename"],
                   verbose: payload.fetch("verbose"))
  nil
when "relocate", "relocate_prefix", "fix_linkage"
  require "keg"
  keg = Keg.new(Pathname(payload.fetch("path")))
  files = payload["files"]&.map { |file| Pathname(file) }
  case ARGV.fetch(0)
  when "relocate_prefix"
    keg.relocate_build_prefix(Keg.new(Pathname(payload.fetch("keg"))), payload.fetch("old_prefix"),
                              payload.fetch("new_prefix"), files:).map(&:to_s)
  when "relocate"
    keg.replace_placeholders_with_locations(files,
                                            skip_linkage:  payload.fetch("skip_linkage"),
                                            linkage_files: payload["linkage_files"]&.map { |file| Pathname(file) })
    keg.require_relocation?
  when "fix_linkage"
    keg.fix_dynamic_linkage
    keg.require_relocation?
  end
else
  raise ArgumentError, "Unknown sandbox operation: #{ARGV.fetch(0)}"
end
result_output.write(JSON.generate(result))
