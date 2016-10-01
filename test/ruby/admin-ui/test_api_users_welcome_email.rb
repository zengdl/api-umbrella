require "test_helper"

class TestAdminUiApiUsersWelcomeEmail < Minitest::Capybara::Test
  include Capybara::Screenshot::MiniTestPlugin
  include ApiUmbrellaTests::AdminAuth
  include ApiUmbrellaTests::Setup

  def setup
    setup_server

    response = Typhoeus.delete("http://127.0.0.1:13103/api/v1/messages")
    assert_equal(200, response.code, response.body)
  end

  def test_no_email_by_default
    admin_login
    visit "/admin/#/api_users/new"

    fill_in "E-mail", :with => "example@example.com"
    fill_in "First Name", :with => "John"
    fill_in "Last Name", :with => "Doe"
    check "User agrees to the terms and conditions"
    click_button("Save")
    assert_content("Successfully saved the user")

    wait_for_delayed_jobs
    response = Typhoeus.get("http://127.0.0.1:13103/api/v1/messages")
    assert_equal(200, response.code, response.body)
    data = MultiJson.load(response.body)
    assert_equal(0, data.length)
  end

  def test_email_when_explicitly_requested
    admin_login
    visit "/admin/#/api_users/new"

    fill_in "E-mail", :with => "example@example.com"
    fill_in "First Name", :with => "John"
    fill_in "Last Name", :with => "Doe"
    check "User agrees to the terms and conditions"
    check "Send user welcome e-mail with API key information"
    click_button("Save")
    assert_content("Successfully saved the user")

    wait_for_delayed_jobs
    response = Typhoeus.get("http://127.0.0.1:13103/api/v1/messages")
    assert_equal(200, response.code, response.body)
    data = MultiJson.load(response.body)
    assert_equal(1, data.length)
  end

  private

  def wait_for_delayed_jobs
    db = Mongoid.client(:default)
    start_time = Time.now
    loop do
      if(db[:delayed_backend_mongoid_jobs].count == 0)
        break
      end

      if(Time.now - start_time > 10)
        raise "Background job was not processed within expected time. Is delayed_job running?"
      end

      sleep 0.1
    end
  end
end
