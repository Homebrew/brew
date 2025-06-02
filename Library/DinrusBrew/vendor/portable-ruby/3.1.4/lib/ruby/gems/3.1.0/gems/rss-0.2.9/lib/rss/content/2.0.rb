# frozen_string_literal: false
require "rss/2.0"

module RSS
  Rss.install_ns(CONTENT_PREFIX, CONTENT_URI)

  class Rss
    class Channel
      class Item; include ContentModel; end
    end
  end
end
