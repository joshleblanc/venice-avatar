class CharacterSchedule < ApplicationRecord
  belongs_to :character
  
  validates :schedule_type, presence: true, inclusion: { in: %w[daily weekly random contextual] }
  validates :trigger_conditions, presence: true
  validates :priority, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 10 }
  
  scope :active, -> { where(active: true) }
  scope :by_priority, -> { order(priority: :desc) }
  
  # Schedule types:
  # - daily: triggers at specific times each day
  # - weekly: triggers on specific days/times
  # - random: triggers randomly within time windows
  # - contextual: triggers based on conversation context/inactivity
  
  def should_trigger?(conversation)
    return false unless active?
    return false if conversation.character_away?
    return false if conversation.generating_reply?
    
    case schedule_type
    when 'daily'
      check_daily_trigger(conversation)
    when 'weekly'
      check_weekly_trigger(conversation)
    when 'random'
      check_random_trigger(conversation)
    when 'contextual'
      check_contextual_trigger(conversation)
    else
      false
    end
  end
  
  def generate_initiative_message(conversation)
    context = build_context(conversation)
    
    prompt = <<~PROMPT
      You are #{character.name} and you want to initiate a conversation based on your personality and current context.
      
      Your personality: #{character.description}
      Schedule context: #{description}
      Current conversation context: #{context}
      
      Generate a natural, character-appropriate message to start or continue the conversation.
      The message should feel organic and match your personality.
      Keep it conversational and engaging (1-2 sentences).
      
      Generate ONLY the message content, no quotes or extra text:
    PROMPT
    
    begin
      ChatCompletionJob.perform_now(
        conversation.user, 
        [{ role: "user", content: prompt }], 
        { temperature: 0.8 }, 
        conversation.user.text_model
      )
    rescue => e
      Rails.logger.error "Failed to generate initiative message: #{e.message}"
      fallback_message
    end
  end
  
  private
  
  def check_daily_trigger(conversation)
    return false unless trigger_conditions['times']
    
    current_time = Time.current
    trigger_times = trigger_conditions['times']
    
    trigger_times.any? do |time_str|
      trigger_time = Time.parse(time_str)
      time_matches?(current_time, trigger_time) && 
        !recently_triggered?(conversation, 1.hour)
    end
  end
  
  def check_weekly_trigger(conversation)
    return false unless trigger_conditions['days'] && trigger_conditions['times']
    
    current_time = Time.current
    current_day = current_time.strftime('%A').downcase
    
    return false unless trigger_conditions['days'].include?(current_day)
    
    trigger_conditions['times'].any? do |time_str|
      trigger_time = Time.parse(time_str)
      time_matches?(current_time, trigger_time) && 
        !recently_triggered?(conversation, 1.day)
    end
  end
  
  def check_random_trigger(conversation)
    return false unless trigger_conditions['probability']
    return false if recently_triggered?(conversation, 30.minutes)
    
    probability = trigger_conditions['probability'].to_f
    rand < probability
  end
  
  def check_contextual_trigger(conversation)
    return false unless trigger_conditions['inactivity_minutes']
    
    inactivity_threshold = trigger_conditions['inactivity_minutes'].minutes.ago
    last_message = conversation.messages.order(:created_at).last
    
    return false unless last_message
    return false if last_message.role == 'assistant' # Don't trigger if character just spoke
    
    last_message.created_at < inactivity_threshold && 
      !recently_triggered?(conversation, inactivity_threshold)
  end
  
  def time_matches?(current_time, trigger_time)
    # Allow 5-minute window for trigger times
    time_diff = (current_time.hour * 60 + current_time.min) - 
                (trigger_time.hour * 60 + trigger_time.min)
    time_diff.abs <= 5
  end
  
  def recently_triggered?(conversation, threshold)
    conversation.messages
               .where(role: 'assistant')
               .where("metadata->>'initiative_schedule_id' = ?", id.to_s)
               .where('created_at > ?', threshold)
               .exists?
  end
  
  def build_context(conversation)
    recent_messages = conversation.messages.order(:created_at).last(3)
    if recent_messages.any?
      recent_messages.map { |msg| "#{msg.role}: #{msg.content}" }.join("\n")
    else
      "No recent messages"
    end
  end
  
  def fallback_message
    case schedule_type
    when 'daily'
      "Good morning! How are you doing today?"
    when 'weekly'
      "Hey! How has your week been going?"
    when 'random'
      "Just thinking about you! What's on your mind?"
    when 'contextual'
      "I noticed you've been quiet. Everything okay?"
    else
      "Hey there! What's up?"
    end
  end
end