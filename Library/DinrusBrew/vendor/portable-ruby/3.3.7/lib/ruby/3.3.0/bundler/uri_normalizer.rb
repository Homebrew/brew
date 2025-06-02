# frozen_string_literal: true

module Bundler
  module URINormalizer
    module_function

    # Normalizes uri to a consistent version, either with or without trailing
    # slash.
    #
    # TODO: Currently gem sources are locked with a trailing slash, while git
    # sources are locked without a trailing slash. This should be normalized but
    # the inconsistency is there for now to avoid changing all lockfiles
    # including GIT sources. We could normalize this on the next major.
    #
    def normalize_suffix(uri, trailing_slash: true)
      if trailing_slash
        uri.end_with?("/") ? uri : "#{uri}/"
      else
        uri.end_with?("/") ? uri.delete_suffix("/") : uri
      end
    end
  end
end
