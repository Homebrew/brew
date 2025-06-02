# frozen_string_literal: false
require_relative '../trackback'
require_relative '1.0'
require_relative '2.0'

module RSS
  module Maker
    module TrackBackModel
      def self.append_features(klass)
        super

        klass.def_other_element("#{RSS::TRACKBACK_PREFIX}_ping")
        klass.def_classed_elements("#{RSS::TRACKBACK_PREFIX}_about", "value",
                                   "TrackBackAbouts")
      end

      class TrackBackAboutsBase < Base
        def_array_element("about", nil, "TrackBackAbout")

        class TrackBackAboutBase < Base
          attr_accessor :value
          add_need_initialize_variable("value")

          alias_method(:resource, :value)
          alias_method(:resource=, :value=)
          alias_method(:content, :value)
          alias_method(:content=, :value=)

          def have_required_values?
            @value
          end

          def to_feed(feed, current)
            if current.respond_to?(:trackback_abouts) and have_required_values?
              about = current.class::TrackBackAbout.new
              setup_values(about)
              setup_other_elements(about)
              current.trackback_abouts << about
            end
          end
        end
      end
    end

    class ItemsBase
      class ItemBase; include TrackBackModel; end
    end

    makers.each do |maker|
      maker.module_eval(<<-EOC, __FILE__, __LINE__ + 1)
        class Items
          class Item
            class TrackBackAbouts < TrackBackAboutsBase
              class TrackBackAbout < TrackBackAboutBase
              end
            end
          end
        end
      EOC
    end
  end
end
