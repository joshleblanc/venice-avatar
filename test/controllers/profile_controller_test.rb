require "test_helper"

class ProfileControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "should get show" do
    get profile_url
    assert_response :success
  end

  test "should get edit" do
    get edit_profile_url
    assert_response :success
  end

  test "should update profile" do
    # Skip venice_key validation for this test
    User.any_instance.stubs(:venice_key_must_be_valid).returns(true)
    
    patch profile_url, params: { user: { timezone: "UTC", safe_mode: true } }
    assert_response :redirect
  end
end
