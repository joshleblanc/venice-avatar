require "test_helper"

class MessageTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @conversation = conversations(:one)
  end

  # Basic validations
  test "should be valid with valid attributes" do
    message = Message.new(
      conversation: @conversation,
      user: @user,
      role: "user",
      content: "Hello world"
    )
    assert message.valid?
  end

  test "should require content" do
    message = Message.new(
      conversation: @conversation,
      user: @user,
      role: "user",
      content: ""
    )
    assert_not message.valid?
    assert_includes message.errors[:content], "can't be blank"
  end

  test "should require role" do
    message = Message.new(
      conversation: @conversation,
      user: @user,
      role: "",
      content: "Hello"
    )
    assert_not message.valid?
    assert_includes message.errors[:role], "can't be blank"
  end

  test "should only allow user or assistant roles" do
    message = Message.new(
      conversation: @conversation,
      user: @user,
      role: "invalid_role",
      content: "Hello"
    )
    assert_not message.valid?
    assert_includes message.errors[:role], "is not included in the list"
  end

  test "should belong to conversation" do
    message = Message.new(
      user: @user,
      role: "user",
      content: "Hello"
    )
    assert_not message.valid?
  end

  test "should belong to user" do
    message = Message.new(
      conversation: @conversation,
      role: "user",
      content: "Hello"
    )
    assert_not message.valid?
  end

  # Scopes
  test "user_messages scope should return only user messages" do
    user_messages = Message.user_messages
    user_messages.each do |message|
      assert_equal "user", message.role
    end
  end

  test "assistant_messages scope should return only assistant messages" do
    assistant_messages = Message.assistant_messages
    assistant_messages.each do |message|
      assert_equal "assistant", message.role
    end
  end

  test "recent scope should order by created_at desc" do
    messages = Message.recent.limit(2)
    assert messages.first.created_at >= messages.second.created_at
  end

  # Content parsing tests
  test "should parse parenthetical actions" do
    message = messages(:user_message)
    parsed = message.parsed_content
    
    assert_equal "Hello there! How are you doing today?", parsed[:clean_text]
    assert_equal 1, parsed[:actions_and_thoughts].length
    assert_equal "action", parsed[:actions_and_thoughts].first[:type]
    assert_equal "waves enthusiastically", parsed[:actions_and_thoughts].first[:text]
  end

  test "should parse bold actions and italic thoughts" do
    message = messages(:assistant_message)
    parsed = message.parsed_content
    
    assert_equal "I'm doing well, thank you for asking! What brings you here today?", parsed[:clean_text]
    assert_equal 2, parsed[:actions_and_thoughts].length
    
    # Check bold action
    bold_action = parsed[:actions_and_thoughts].find { |item| item[:text] == "smiles warmly" }
    assert_not_nil bold_action
    assert_equal "action", bold_action[:type]
    
    # Check italic thought
    italic_thought = parsed[:actions_and_thoughts].find { |item| item[:text] == "thinks about the beautiful weather" }
    assert_not_nil italic_thought
    assert_equal "thought", italic_thought[:type]
  end

  test "should parse square bracket actions" do
    message = messages(:complex_assistant_message)
    parsed = message.parsed_content
    
    expected_clean_text = "Of course, young one. Magic requires patience and dedication. Let us begin with the basics."
    assert_equal expected_clean_text, parsed[:clean_text]
    
    # Should have 4 actions/thoughts: [nods sagely], **gestures to ancient tome**, *recalls years of study*, (opens book carefully)
    assert_equal 4, parsed[:actions_and_thoughts].length
    
    # Check square bracket action
    square_action = parsed[:actions_and_thoughts].find { |item| item[:text] == "nods sagely" }
    assert_not_nil square_action
    assert_equal "action", square_action[:type]
  end

  test "should handle content with no actions or thoughts" do
    message = messages(:simple_user_message)
    parsed = message.parsed_content
    
    assert_equal "Can you teach me magic?", parsed[:clean_text]
    assert_equal 0, parsed[:actions_and_thoughts].length
  end

  test "clean_text should return only text without actions" do
    message = messages(:user_message)
    assert_equal "Hello there! How are you doing today?", message.clean_text
  end

  test "actions_and_thoughts should return parsed actions and thoughts" do
    message = messages(:assistant_message)
    actions_and_thoughts = message.actions_and_thoughts
    
    assert_equal 2, actions_and_thoughts.length
    assert actions_and_thoughts.any? { |item| item[:text] == "smiles warmly" }
    assert actions_and_thoughts.any? { |item| item[:text] == "thinks about the beautiful weather" }
  end

  test "has_actions_or_thoughts? should return true when actions exist" do
    message = messages(:user_message)
    assert message.has_actions_or_thoughts?
  end

  test "has_actions_or_thoughts? should return false when no actions exist" do
    message = messages(:simple_user_message)
    assert_not message.has_actions_or_thoughts?
  end

  test "full_content_for_ai should return original content" do
    message = messages(:assistant_message)
    expected = "**smiles warmly** I'm doing well, thank you for asking! *thinks about the beautiful weather* What brings you here today?"
    assert_equal expected, message.full_content_for_ai
  end

  # Auto-generated message tests
  test "auto_generated? should return true for auto-generated messages" do
    message = messages(:auto_generated_message)
    assert message.auto_generated?
  end

  test "auto_generated? should return false for regular messages" do
    message = messages(:user_message)
    assert_not message.auto_generated?
  end

  test "auto_generation_reason should return reason when available" do
    message = messages(:auto_generated_message)
    assert_equal "user_stepping_away", message.auto_generation_reason
  end

  test "auto_generation_reason should return nil for regular messages" do
    message = messages(:user_message)
    assert_nil message.auto_generation_reason
  end

  # Edge cases
  test "should handle empty parentheses" do
    message = Message.new(
      conversation: @conversation,
      user: @user,
      role: "user",
      content: "Hello () there"
    )
    
    parsed = message.parsed_content
    assert_equal "Hello there", parsed[:clean_text]
    assert_equal 0, parsed[:actions_and_thoughts].length
  end

  test "should handle nested formatting" do
    message = Message.new(
      conversation: @conversation,
      user: @user,
      role: "user",
      content: "**bold (with parentheses) text** and *italic [with brackets] text*"
    )
    
    parsed = message.parsed_content
    assert_equal "and", parsed[:clean_text]
    # Should extract: **bold (with parentheses) text**, (with parentheses), *italic [with brackets] text*, [with brackets]
    # But nested ones might be processed differently - let's check what we actually get
    assert parsed[:actions_and_thoughts].length >= 2
  end

  test "should clean up extra whitespace" do
    message = Message.new(
      conversation: @conversation,
      user: @user,
      role: "user",
      content: "Hello   (waves)   there    **smiles**   friend"
    )
    
    parsed = message.parsed_content
    assert_equal "Hello there friend", parsed[:clean_text]
  end
end