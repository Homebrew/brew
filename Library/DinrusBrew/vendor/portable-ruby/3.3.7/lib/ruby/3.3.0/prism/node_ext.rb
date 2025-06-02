# frozen_string_literal: true

# Here we are reopening the prism module to provide methods on nodes that aren't
# templated and are meant as convenience methods.
module Prism
  module RegularExpressionOptions # :nodoc:
    # Returns a numeric value that represents the flags that were used to create
    # the regular expression.
    def options
      o = flags & (RegularExpressionFlags::IGNORE_CASE | RegularExpressionFlags::EXTENDED | RegularExpressionFlags::MULTI_LINE)
      o |= Regexp::FIXEDENCODING if flags.anybits?(RegularExpressionFlags::EUC_JP | RegularExpressionFlags::WINDOWS_31J | RegularExpressionFlags::UTF_8)
      o |= Regexp::NOENCODING if flags.anybits?(RegularExpressionFlags::ASCII_8BIT)
      o
    end
  end

  class InterpolatedMatchLastLineNode < Node
    include RegularExpressionOptions
  end

  class InterpolatedRegularExpressionNode < Node
    include RegularExpressionOptions
  end

  class MatchLastLineNode < Node
    include RegularExpressionOptions
  end

  class RegularExpressionNode < Node
    include RegularExpressionOptions
  end

  private_constant :RegularExpressionOptions

  module HeredocQuery # :nodoc:
    # Returns true if this node was represented as a heredoc in the source code.
    def heredoc?
      opening&.start_with?("<<")
    end
  end

  class InterpolatedStringNode < Node
    include HeredocQuery
  end

  class InterpolatedXStringNode < Node
    include HeredocQuery
  end

  class StringNode < Node
    include HeredocQuery
  end

  class XStringNode < Node
    include HeredocQuery
  end

  private_constant :HeredocQuery

  class FloatNode < Node
    # Returns the value of the node as a Ruby Float.
    def value
      Float(slice)
    end
  end

  class ImaginaryNode < Node
    # Returns the value of the node as a Ruby Complex.
    def value
      Complex(0, numeric.value)
    end
  end

  class IntegerNode < Node
    # Returns the value of the node as a Ruby Integer.
    def value
      Integer(slice)
    end
  end

  class RationalNode < Node
    # Returns the value of the node as a Ruby Rational.
    def value
      Rational(slice.chomp("r"))
    end
  end

  class ConstantReadNode < Node
    # Returns the list of parts for the full name of this constant.
    # For example: [:Foo]
    def full_name_parts
      [name]
    end

    # Returns the full name of this constant. For example: "Foo"
    def full_name
      name.name
    end
  end

  class ConstantPathNode < Node
    # An error class raised when dynamic parts are found while computing a
    # constant path's full name. For example:
    # Foo::Bar::Baz -> does not raise because all parts of the constant path are
    # simple constants
    # var::Bar::Baz -> raises because the first part of the constant path is a
    # local variable
    class DynamicPartsInConstantPathError < StandardError; end

    # Returns the list of parts for the full name of this constant path.
    # For example: [:Foo, :Bar]
    def full_name_parts
      parts = [child.name]
      current = parent

      while current.is_a?(ConstantPathNode)
        parts.unshift(current.child.name)
        current = current.parent
      end

      unless current.is_a?(ConstantReadNode)
        raise DynamicPartsInConstantPathError, "Constant path contains dynamic parts. Cannot compute full name"
      end

      parts.unshift(current&.name || :"")
    end

    # Returns the full name of this constant path. For example: "Foo::Bar"
    def full_name
      full_name_parts.join("::")
    end
  end

  class ConstantPathTargetNode < Node
    # Returns the list of parts for the full name of this constant path.
    # For example: [:Foo, :Bar]
    def full_name_parts
      (parent&.full_name_parts || [:""]).push(child.name)
    end

    # Returns the full name of this constant path. For example: "Foo::Bar"
    def full_name
      full_name_parts.join("::")
    end
  end

  class ParametersNode < Node
    # Mirrors the Method#parameters method.
    def signature
      names = []

      requireds.each do |param|
        names << (param.is_a?(MultiTargetNode) ? [:req] : [:req, param.name])
      end

      optionals.each { |param| names << [:opt, param.name] }
      names << [:rest, rest.name || :*] if rest

      posts.each do |param|
        names << (param.is_a?(MultiTargetNode) ? [:req] : [:req, param.name])
      end

      # Regardless of the order in which the keywords were defined, the required
      # keywords always come first followed by the optional keywords.
      keyopt = []
      keywords.each do |param|
        if param.is_a?(OptionalKeywordParameterNode)
          keyopt << param
        else
          names << [:keyreq, param.name]
        end
      end

      keyopt.each { |param| names << [:key, param.name] }

      case keyword_rest
      when ForwardingParameterNode
        names.concat([[:rest, :*], [:keyrest, :**], [:block, :&]])
      when KeywordRestParameterNode
        names << [:keyrest, keyword_rest.name || :**]
      when NoKeywordsParameterNode
        names << [:nokey]
      end

      names << [:block, block.name || :&] if block
      names
    end
  end
end
