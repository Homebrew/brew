# typed: true
# frozen_string_literal: true

# Helper for checking if a file is considered a metadata file.
module Metafiles
  LICENSES = Set.new(%w[copying copyright license licence]).freeze
  # {https://github.com/github/markup#markups}
  EXTENSIONS = Set.new(%w[
    .adoc .asc .asciidoc .creole .html .markdown .md .mdown .mediawiki .mkdn
    .org .pod .rdoc .rst .rtf .textile .txt .wiki
  ]).freeze
  BASENAMES = Set.new(%w[about authors changelog changes history news notes notice readme todo]).freeze

  module_function

  def list?(file)
    return false if %w[.DS_Store INSTALL_RECEIPT.json].include?(file)

    !copy?(file)
  end

  def copy?(file)
    file = file.downcase
    return true if LICENSES.include? file.split(/\.|-/).first

    ext  = File.extname(file)
    file = File.basename(file, ext) if EXTENSIONS.include?(ext)
    BASENAMES.include?(file)
  end
end
