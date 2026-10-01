# typed: strict
# frozen_string_literal: true

# Strategy for downloading files from PyPI.
#
# @api public
class PyPIDownloadStrategy < CurlDownloadStrategy
  sig { override.returns(Time) }
  def source_modified_time
    last_modified = cached_location.mtime if cached_location.exist?
    source_modified_time = super
    return source_modified_time if last_modified.nil? || source_modified_time > last_modified

    last_modified
  end
end
