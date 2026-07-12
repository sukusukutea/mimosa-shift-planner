require "test_helper"

class StaffsControllerTest < ActionDispatch::IntegrationTest
  test "should redirect index when not signed in" do
    get staffs_url
    assert_redirected_to new_user_session_url
  end

  test "should redirect new when not signed in" do
    get new_staff_url
    assert_redirected_to new_user_session_url
  end
end

