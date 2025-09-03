require "test_helper"

class FollowupIntentDetectorServiceTest < ActiveSupport::TestCase
  def setup
    @character = characters(:one)
    @conversation = conversations(:one)
    @service = FollowupIntentDetectorService.new(@conversation)
  end

  test "detects character followup intent for stepping away messages" do
    # Mock the ChatCompletionJob response
    mock_response = '{"has_intent": true, "reason": "Character said they need to get something quickly"}'

    ChatCompletionJob.stubs(:perform_now).returns(mock_response)

    result = @service.detect_character_followup_intent("Hold on, I need to grab something from the kitchen")

    assert result[:has_intent]
    assert_equal "Character said they need to get something quickly", result[:reason]
  end

  test "does not detect character followup intent for normal messages" do
    # Mock the ChatCompletionJob response
    mock_response = '{"has_intent": false, "reason": null}'

    ChatCompletionJob.stubs(:perform_now).returns(mock_response)

    result = @service.detect_character_followup_intent("How are you doing today?")

    assert_not result[:has_intent]
    assert_nil result[:reason]
  end

  test "handles API errors gracefully" do
    ChatCompletionJob.stubs(:perform_now).raises(StandardError.new("API Error"))

    result = @service.detect_character_followup_intent("I'll be right back")

    assert_not result[:has_intent]
    assert_nil result[:reason]
  end
end
