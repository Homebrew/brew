# typed: strict
# frozen_string_literal: true

require_relative "uncompressed"

module UnpackStrategy
  # Strategy for unpacking Microsoft Office documents.
  class MicrosoftOfficeXml < Uncompressed
    sig { override.returns(T::Array[String]) }
    def self.extensions
      [
        ".doc", ".docx",
        ".ppt", ".pptx",
        ".xls", ".xlsx"
      ]
    end

    sig { override.params(path: Pathname).returns(T::Boolean) }
    def self.can_extract?(path)
      return false unless Zip.can_extract?(path)

      # Check further if the ZIP is a Microsoft Office XML document.
      path.magic_number.match?(/\APK\003\004/n) &&
        path.magic_number.match?(%r{\A.{30}(\[Content_Types\]\.xml|_rels/\.rels)}n)
    end
  end
end
