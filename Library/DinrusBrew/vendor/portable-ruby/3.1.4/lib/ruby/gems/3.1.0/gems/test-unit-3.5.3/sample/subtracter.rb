# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

class Subtracter
  def initialize(number)
    @number = number
  end
  def subtract(number)
    @number - number
  end
end
