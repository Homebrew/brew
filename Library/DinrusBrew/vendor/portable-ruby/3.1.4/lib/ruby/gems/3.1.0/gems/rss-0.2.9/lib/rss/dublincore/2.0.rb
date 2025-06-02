# frozen_string_literal: false
require "rss/2.0"

module RSS
  Rss.install_ns(DC_PREFIX, DC_URI)

  class Rss
    class Channel
      include DublinCoreModel
      class Item; include DublinCoreModel; end
    end
  end
end
