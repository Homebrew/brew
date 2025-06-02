# frozen_string_literal: true
module Psych
  module JSON
    module YAMLEvents # :nodoc:
      def start_document version, tag_directives, implicit
        super(version, tag_directives, !streaming?)
      end

      def end_document implicit_end = !streaming?
        super(implicit_end)
      end

      def start_mapping anchor, tag, implicit, style
        super(anchor, nil, true, Nodes::Mapping::FLOW)
      end

      def start_sequence anchor, tag, implicit, style
        super(anchor, nil, true, Nodes::Sequence::FLOW)
      end

      def scalar value, anchor, tag, plain, quoted, style
        if "tag:yaml.org,2002:null" == tag
          super('null', nil, nil, true, false, Nodes::Scalar::PLAIN)
        else
          super
        end
      end
    end
  end
end
