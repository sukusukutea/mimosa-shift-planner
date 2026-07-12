require "test_helper"

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  test "should redirect index when not signed in" do
    get dashboard_url
    assert_redirected_to new_user_session_url
  end
end
