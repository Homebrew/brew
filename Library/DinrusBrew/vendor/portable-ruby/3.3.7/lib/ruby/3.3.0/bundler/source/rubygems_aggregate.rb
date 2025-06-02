# frozen_string_literal: true

module Bundler
  class Source
    class RubygemsAggregate
      attr_reader :source_map, :sources

      def initialize(sources, source_map)
        @sources = sources
        @source_map = source_map

        @index = build_index
      end

      def specs
        @index
      end

      def identifier
        to_s
      end

      def to_s
        "any of the sources"
      end

      private

      def build_index
        Index.build do |idx|
          dependency_names = source_map.pinned_spec_names

          sources.all_sources.each do |source|
            source.dependency_names = dependency_names - source_map.pinned_spec_names(source)
            idx.add_source source.specs
            dependency_names.concat(source.unmet_deps).uniq!
          end

          double_check_for_index(idx, dependency_names)
        end
      end

      # Suppose the gem Foo depends on the gem Bar.  Foo exists in Source A.  Bar has some versions that exist in both
      # sources A and B.  At this point, the API request will have found all the versions of Bar in source A,
      # but will not have found any versions of Bar from source B, which is a problem if the requested version
      # of Foo specifically depends on a version of Bar that is only found in source B. This ensures that for
      # each spec we found, we add all possible versions from all sources to the index.
      def double_check_for_index(idx, dependency_names)
        pinned_names = source_map.pinned_spec_names

        names = :names # do this so we only have to traverse to get dependency_names from the index once
        unmet_dependency_names = lambda do
          return names unless names == :names
          new_names = sources.all_sources.map(&:dependency_names_to_double_check)
          return names = nil if new_names.compact!
          names = new_names.flatten(1).concat(dependency_names)
          names.uniq!
          names -= pinned_names
          names
        end

        sources.all_sources.each do |source|
          source.double_check_for(unmet_dependency_names)
        end
      end
    end
  end
end
