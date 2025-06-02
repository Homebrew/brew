# frozen_string_literal: true
##
# A horizontal rule with a weight

class RDoc::Markup::Rule < Struct.new :weight

  ##
  # Calls #accept_rule on +visitor+

  def accept visitor
    visitor.accept_rule self
  end

  def pretty_print q # :nodoc:
    q.group 2, '[rule:', ']' do
      q.pp weight
    end
  end

end
