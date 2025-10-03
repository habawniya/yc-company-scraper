require "test_helper"

class ScraperControllerTest < ActionDispatch::IntegrationTest
  test "should get ycombinator" do
    get scraper_ycombinator_url
    assert_response :success
  end
end
