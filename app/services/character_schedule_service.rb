class CharacterScheduleService
  def self.create_default_schedules_for_character(character)
    return if character.character_schedules.exists?
    
    schedules = []
    
    # Morning greeting (daily at 9 AM)
    schedules << {
      name: "Morning Greeting",
      description: "Send a good morning message",
      schedule_type: "daily",
      trigger_conditions: {
        times: ["09:00"]
      },
      priority: 7
    }
    
    # Evening check-in (daily at 7 PM)
    schedules << {
      name: "Evening Check-in",
      description: "Check in during evening hours",
      schedule_type: "daily", 
      trigger_conditions: {
        times: ["19:00"]
      },
      priority: 6
    }
    
    # Weekend greeting (Saturday and Sunday mornings)
    schedules << {
      name: "Weekend Greeting",
      description: "Special weekend greeting",
      schedule_type: "weekly",
      trigger_conditions: {
        days: ["saturday", "sunday"],
        times: ["10:00"]
      },
      priority: 8
    }
    
    # Random check-ins (low probability throughout the day)
    schedules << {
      name: "Random Check-in",
      description: "Spontaneous conversation starter",
      schedule_type: "random",
      trigger_conditions: {
        probability: 0.1 # 10% chance when checked
      },
      priority: 3
    }
    
    # Inactivity response (after 2 hours of silence)
    schedules << {
      name: "Inactivity Follow-up",
      description: "Reach out after periods of inactivity",
      schedule_type: "contextual",
      trigger_conditions: {
        inactivity_minutes: 120
      },
      priority: 5
    }
    
    # Create the schedules
    schedules.each do |schedule_attrs|
      character.character_schedules.create!(schedule_attrs)
    end
    
    Rails.logger.info "Created #{schedules.count} default schedules for character #{character.name}"
  end
  
  def self.create_personality_based_schedules(character)
    # This method could analyze the character's description/personality
    # and create more targeted schedules based on their traits
    
    description = character.description&.downcase || ""
    
    # Example: if character is described as energetic, add more frequent check-ins
    if description.include?("energetic") || description.include?("active") || description.include?("outgoing")
      character.character_schedules.create!(
        name: "Energetic Check-in",
        description: "Frequent check-ins for energetic personality",
        schedule_type: "random",
        trigger_conditions: {
          probability: 0.2 # Higher probability for energetic characters
        },
        priority: 6
      )
    end
    
    # Example: if character is described as caring/nurturing, add evening check-ins
    if description.include?("caring") || description.include?("nurturing") || description.include?("supportive")
      character.character_schedules.create!(
        name: "Caring Check-in",
        description: "Caring evening check-in",
        schedule_type: "daily",
        trigger_conditions: {
          times: ["20:00", "21:00"]
        },
        priority: 7
      )
    end
    
    # Example: if character is described as professional, add work-hour greetings
    if description.include?("professional") || description.include?("business") || description.include?("work")
      character.character_schedules.create!(
        name: "Professional Greeting",
        description: "Work hours greeting",
        schedule_type: "weekly",
        trigger_conditions: {
          days: ["monday", "tuesday", "wednesday", "thursday", "friday"],
          times: ["08:30", "13:00"] # Start of work day and lunch time
        },
        priority: 6
      )
    end
  end
end