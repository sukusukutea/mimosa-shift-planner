require "test_helper"

class BaseWeekdayRequirementsControllerTest < ActionDispatch::IntegrationTest
  test "should redirect show when not signed in" do
    get base_weekday_requirements_show_url
    assert_redirected_to new_user_session_url
  end

  test "should redirect edit when not signed in" do
    get base_weekday_requirements_edit_url
    assert_redirected_to new_user_session_url
  end
end
