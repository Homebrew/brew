# typed: strict
# frozen_string_literal: true

# Strategy for downloading archives without automatically extracting them.
# (Useful for downloading `.jar` files.)
#
# @api public
class NoUnzipCurlDownloadStrategy < CurlDownloadStrategy
  sig { override.params(_block: T.nilable(T.proc.void)).void }
  def stage(&_block)
    UnpackStrategy::Uncompressed.new(cached_location)
                                .extract(basename:,
                                         verbose:  verbose? && !quiet?)
    yield if block_given?
  end
end
