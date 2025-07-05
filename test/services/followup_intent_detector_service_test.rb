require "test_helper"

class FollowupIntentDetectorServiceTest < ActiveSupport::TestCase
  def setup
    @character = characters(:one)
    @conversation = conversations(:one)
    @service = FollowupIntentDetectorService.new(@conversation)
  end

  test "detects character followup intent for stepping away messages" do
    # Mock the Venice API response
    mock_response = {
      choices: [{
        message: {
          content: '{"has_intent": true, "reason": "Character said they need to get something quickly"}',
        },
      }],
    }

    VeniceClient::ChatApi.any_instance.stubs(:create_chat_completion).returns(mock_response)

    result = @service.detect_character_followup_intent("Hold on, I need to grab something from the kitchen")

    assert result[:has_intent]
    assert_equal "Character said they need to get something quickly", result[:reason]
  end

  test "does not detect character followup intent for normal messages" do
    # Mock the Venice API response
    mock_response = {
      choices: [{
        message: {
          content: '{"has_intent": false, "reason": null}',
        },
      }],
    }

    VeniceClient::ChatApi.any_instance.stubs(:create_chat_completion).returns(mock_response)

    result = @service.detect_character_followup_intent("How are you doing today?")

    assert_not result[:has_intent]
    assert_nil result[:reason]
  end

  test "handles API errors gracefully" do
    VeniceClient::ChatApi.any_instance.stubs(:create_chat_completion).raises(StandardError.new("API Error"))

    result = @service.detect_character_followup_intent("I'll be right back")

    assert_not result[:has_intent]
    assert_nil result[:reason]
  end
end
