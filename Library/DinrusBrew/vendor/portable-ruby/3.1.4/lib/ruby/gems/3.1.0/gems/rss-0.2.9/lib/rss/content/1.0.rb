# frozen_string_literal: false
require 'rss/1.0'

module RSS
  RDF.install_ns(CONTENT_PREFIX, CONTENT_URI)

  class RDF
    class Item; include ContentModel; end
  end
end
