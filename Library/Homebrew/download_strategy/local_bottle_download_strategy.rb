# typed: strict
# frozen_string_literal: true

# Strategy for extracting local binary packages.
class LocalBottleDownloadStrategy < AbstractFileDownloadStrategy
  # TODO: Call `super` here
  # rubocop:disable Lint/MissingSuper
  sig { params(path: Pathname).void }
  def initialize(path)
    @cached_location = path
  end
  # rubocop:enable Lint/MissingSuper

  sig { override.void }
  def clear_cache
    # Path is used directly and not cached.
  end
end
