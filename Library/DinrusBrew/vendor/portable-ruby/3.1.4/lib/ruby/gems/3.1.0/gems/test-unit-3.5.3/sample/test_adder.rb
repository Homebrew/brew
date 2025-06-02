# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit'
require_relative 'adder'

class TestAdder < Test::Unit::TestCase
  def setup
    @adder = Adder.new(5)
  end

  def test_add
    assert_equal(7, @adder.add(2), "Should have added correctly")
  end

  def teardown
    @adder = nil
  end
end
