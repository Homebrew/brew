# frozen_string_literal: true

module RBS
  module Annotate
    class Annotations
      class Skip
        attr_reader :annotation, :skip_children

        def initialize(annotation:, skip_children:)
          @annotation = annotation
          @skip_children = skip_children
        end

        def hash
          self.class.hash ^ annotation.hash ^ skip_children.hash
        end

        def ==(other)
          other.is_a?(Skip) &&
            other.skip_children == skip_children &&
            other.annotation == annotation
        end

        alias eql? ==
      end

      class Source
        attr_reader :annotation
        attr_reader :include_source, :skip_source

        def initialize(annotation:, include: nil, skip: nil)
          @annotation = annotation
          @include_source = include
          @skip_source = skip
        end

        def hash
          self.class.hash ^ annotation.hash ^ include_source.hash ^ skip_source.hash
        end

        def ==(other)
          other.is_a?(Source) &&
            other.annotation == annotation &&
            other.include_source == include_source &&
            other.skip_source == skip_source
        end

        alias eql? ==
      end

      class Copy
        attr_reader :annotation, :source

        def initialize(annotation:, source:)
          @annotation = annotation
          @source = source
        end

        def type_name
          name, _ = partition
          name
        end

        def method_name
          _, m = partition
          if m
            m[1]
          end
        end

        def singleton?
          _, m = partition
          if m
            m[0]
          else
            false
          end
        end

        def hash
          self.class.hash ^ annotation.hash ^ source.hash
        end

        def ==(other)
          other.is_a?(Copy) &&
            other.annotation == annotation &&
            other.source == source
        end

        alias eql? ==

        def partition
          case
          when match = source.match(/(?<constant_name>[^#]+)#(?<method_name>.+)/)
            [
              TypeName(match[:constant_name] || raise),
              [
                false,
                (match[:method_name] or raise).to_sym
              ]
            ]
          when match = source.match(/(?<constant_name>[^#]+)\.(?<method_name>.+)/)
            [
              TypeName(match[:constant_name] || raise),
              [
                true,
                (match[:method_name] or raise).to_sym
              ]
            ]
          else
            [
              TypeName(source),
              nil
            ]
          end
        end
      end

      def self.parse(annotation)
        string = annotation.string

        case
        when match = string.match(/\Aannotate:rdoc:skip(:all)?\Z/)
          Skip.new(
            annotation: annotation,
            skip_children: string.end_with?(":all")
          )
        when match = string.match(/\Aannotate:rdoc:source:from=(?<path>.+)\Z/)
          Source.new(
            annotation: annotation,
            include: (match[:path] or raise).strip
          )
        when match = string.match(/\Aannotate:rdoc:source:skip=(?<path>.+)\Z/)
          Source.new(
            annotation: annotation,
            skip: (match[:path] or raise).strip
          )
        when match = string.match(/\Aannotate:rdoc:copy:(?<name>.+)\Z/)
          Copy.new(
            annotation: annotation,
            source: (match[:name] or raise).strip
          )
        end
      end

      attr_reader :items

      def initialize(items)
        @items = items
      end

      def skip?
        items.any? {|a| a.is_a?(Skip) }
      end

      def skip_all?
        items.any? {|a| a.is_a?(Skip) && a.skip_children }
      end

      def copy_annotation
        _ = items.find {|a| a.is_a?(Copy) }
      end

      def test_path(path)
        # @type var source_items: Array[Source]
        source_items = _ = items.select {|item| item.is_a?(Source) }

        return true if source_items.empty?

        result = source_items[0].include_source == nil

        items.each do |a|
          if a.is_a?(Source)
            if pat = a.include_source
              if test_path_string(pat, path)
                result = true
              end
            end

            if pat = a.skip_source
              if test_path_string(pat, path)
                result = false
              end
            end
          end
        end

        result
      end

      def test_path_string(pattern, string)
        return true if pattern == string
        return true if string.start_with?(pattern + File::SEPARATOR)

        false
      end
    end
  end
end
