# typed: strict
# frozen_string_literal: true

# Helper for checking if a file is considered a metadata file.
module Metafiles
  LICENSES = T.let(Set.new(%w[copying copyright license licence]).freeze, T::Set[String])
  # {https://github.com/github/markup#markups}
  EXTENSIONS = T.let(Set.new(%w[
    .adoc .asc .asciidoc .creole .html .markdown .md .mdown .mediawiki .mkdn
    .org .pod .rdoc .rst .rtf .textile .txt .wiki
  ]).freeze, T::Set[String])
  BASENAMES = T.let(Set.new(%w[
    about authors changelog changes history news notes notice readme todo
  ]).freeze, T::Set[String])

  module_function

  sig { params(file: String).returns(T::Boolean) }
  def list?(file)
    return false if %w[.DS_Store INSTALL_RECEIPT.json].include?(file)

    !copy?(file)
  end

  sig { params(file: String).returns(T::Boolean) }
  def copy?(file)
    file = file.downcase
    license = file.split(/\.|-/).first
    return false unless license
    return true if LICENSES.include?(license)

    ext  = File.extname(file)
    file = File.basename(file, ext) if EXTENSIONS.include?(ext)
    BASENAMES.include?(file)
  end
end
