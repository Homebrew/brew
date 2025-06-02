# frozen_string_literal: true

module Prism
  class ParseResult
    # When we've parsed the source, we have both the syntax tree and the list of
    # comments that we found in the source. This class is responsible for
    # walking the tree and finding the nearest location to attach each comment.
    #
    # It does this by first finding the nearest locations to each comment.
    # Locations can either come from nodes directly or from location fields on
    # nodes. For example, a `ClassNode` has an overall location encompassing the
    # entire class, but it also has a location for the `class` keyword.
    #
    # Once the nearest locations are found, it determines which one to attach
    # to. If it's a trailing comment (a comment on the same line as other source
    # code), it will favor attaching to the nearest location that occurs before
    # the comment. Otherwise it will favor attaching to the nearest location
    # that is after the comment.
    class Comments
      # A target for attaching comments that is based on a specific node's
      # location.
      class NodeTarget # :nodoc:
        attr_reader :node

        def initialize(node)
          @node = node
        end

        def start_offset
          node.location.start_offset
        end

        def end_offset
          node.location.end_offset
        end

        def encloses?(comment)
          start_offset <= comment.location.start_offset &&
            comment.location.end_offset <= end_offset
        end

        def <<(comment)
          node.location.comments << comment
        end
      end

      # A target for attaching comments that is based on a location field on a
      # node. For example, the `end` token of a ClassNode.
      class LocationTarget # :nodoc:
        attr_reader :location

        def initialize(location)
          @location = location
        end

        def start_offset
          location.start_offset
        end

        def end_offset
          location.end_offset
        end

        def encloses?(comment)
          false
        end

        def <<(comment)
          location.comments << comment
        end
      end

      # The parse result that we are attaching comments to.
      attr_reader :parse_result

      # Create a new Comments object that will attach comments to the given
      # parse result.
      def initialize(parse_result)
        @parse_result = parse_result
      end

      # Attach the comments to their respective locations in the tree by
      # mutating the parse result.
      def attach!
        parse_result.comments.each do |comment|
          preceding, enclosing, following = nearest_targets(parse_result.value, comment)
          target =
            if comment.trailing?
              preceding || following || enclosing || NodeTarget.new(parse_result.value)
            else
              # If a comment exists on its own line, prefer a leading comment.
              following || preceding || enclosing || NodeTarget.new(parse_result.value)
            end

          target << comment
        end
      end

      private

      # Responsible for finding the nearest targets to the given comment within
      # the context of the given encapsulating node.
      def nearest_targets(node, comment)
        comment_start = comment.location.start_offset
        comment_end = comment.location.end_offset

        targets = []
        node.comment_targets.map do |value|
          case value
          when StatementsNode
            targets.concat(value.body.map { |node| NodeTarget.new(node) })
          when Node
            targets << NodeTarget.new(value)
          when Location
            targets << LocationTarget.new(value)
          end
        end

        targets.sort_by!(&:start_offset)
        preceding = nil
        following = nil

        left = 0
        right = targets.length

        # This is a custom binary search that finds the nearest nodes to the
        # given comment. When it finds a node that completely encapsulates the
        # comment, it recurses downward into the tree.
        while left < right
          middle = (left + right) / 2
          target = targets[middle]

          target_start = target.start_offset
          target_end = target.end_offset

          if target.encloses?(comment)
            # The comment is completely contained by this target. Abandon the
            # binary search at this level.
            return nearest_targets(target.node, comment)
          end

          if target_end <= comment_start
            # This target falls completely before the comment. Because we will
            # never consider this target or any targets before it again, this
            # target must be the closest preceding target we have encountered so
            # far.
            preceding = target
            left = middle + 1
            next
          end

          if comment_end <= target_start
            # This target falls completely after the comment. Because we will
            # never consider this target or any targets after it again, this
            # target must be the closest following target we have encountered so
            # far.
            following = target
            right = middle
            next
          end

          # This should only happen if there is a bug in this parser.
          raise "Comment location overlaps with a target location"
        end

        [preceding, NodeTarget.new(node), following]
      end
    end

    private_constant :Comments

    # Attach the list of comments to their respective locations in the tree.
    def attach_comments!
      Comments.new(self).attach!
    end
  end
end
