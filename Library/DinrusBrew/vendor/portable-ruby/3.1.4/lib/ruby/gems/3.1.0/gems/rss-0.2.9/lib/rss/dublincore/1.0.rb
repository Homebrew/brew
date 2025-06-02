# frozen_string_literal: false
require "rss/1.0"

module RSS
  RDF.install_ns(DC_PREFIX, DC_URI)

  class RDF
    class Channel; include DublinCoreModel; end
    class Image; include DublinCoreModel; end
    class Item; include DublinCoreModel; end
    class Textinput; include DublinCoreModel; end
  end
end
