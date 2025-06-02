# frozen_string_literal: true

##
# A set which represents the installed gems. Respects
# all the normal settings that control where to look
# for installed gems.

class Gem::Resolver::CurrentSet < Gem::Resolver::Set
  def find_all(req)
    req.dependency.matching_specs
  end
end
