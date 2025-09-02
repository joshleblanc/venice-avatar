ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "mocha/minitest"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

class ActionDispatch::IntegrationTest
  def sign_in_as(user)
    session = user.sessions.create!(user_agent: "Test", ip_address: "127.0.0.1")
    # Use the Rails message verifier to sign the cookie like the app does
    verifier = Rails.application.message_verifier("signed cookie")
    cookies[:session_id] = verifier.generate(session.id)
    Current.session = session
  end
end
