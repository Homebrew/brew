# nested test case example.
require 'test/unit'

class UserTest < Test::Unit::TestCase
  def setup
    @user = "me"
  end

  def test_full_name
    assert_equal("me", @user)
  end

  class ProfileTest < UserTest
    setup
    def setup_profile
      @user += ": profile"
    end

    def test_has_profile
      assert_match(/: profile/, @user)
    end
  end
end
