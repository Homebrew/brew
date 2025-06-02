# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit'
require_relative 'subtracter'

class TestSubtracter < Test::Unit::TestCase
  def setup
    @subtracter = Subtracter.new(5)
  end

  def test_subtract
    assert_equal(3, @subtracter.subtract(2), "Should have subtracted correctly")
  end

  def teardown
    @subtracter = nil
  end
end
