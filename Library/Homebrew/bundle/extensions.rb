# typed: strict
# frozen_string_literal: true

require "bundle/extensions/extension"

extensions_dir = File.join(__dir__, "extensions")
# TODO: Remove this legacy load order once the dump output order no longer
# needs to match the pre-extension refactor section ordering.
legacy_order = %w[mac_app_store vscode_extension go cargo uv flatpak].freeze
extension_files = Dir.glob(File.join(extensions_dir, "*.rb")).sort_by do |file|
  basename = File.basename(file, ".rb")
  [legacy_order.index(basename) || legacy_order.length, basename]
end
extension_files.each do |file|
  basename = File.basename(file, ".rb")
  next if basename == "extension"

  require "bundle/extensions/#{basename}"
end
