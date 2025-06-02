# frozen_string_literal: false
require_relative "../atom"

module RSS
  module Atom
    Feed.install_ns(DC_PREFIX, DC_URI)

    class Feed
      include DublinCoreModel
      class Entry; include DublinCoreModel; end
    end

    class Entry
      include DublinCoreModel
    end
  end
end
