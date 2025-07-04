namespace :context_analyzer do
  desc "Set up the AI context analyzer character for visual novel state tracking"
  task setup: :environment do
    puts "Setting up AI Context Analyzer character..."

    character = ContextAnalyzerCharacterService.ensure_context_analyzer_exists

    if character
      puts "✅ Context Analyzer character created successfully!"
      puts "   Name: #{character.name}"
      puts "   Slug: #{character.slug}"
      puts "   ID: #{character.id}"
    else
      puts "❌ Failed to create Context Analyzer character"
      exit 1
    end
  end

  desc "Verify the context analyzer character exists and is properly configured"
  task verify: :environment do
    character = ContextAnalyzerCharacterService.get_context_analyzer_character

    if character
      puts "✅ Context Analyzer character found:"
      puts "   Name: #{character.name}"
      puts "   Slug: #{character.slug}"
      puts "   Created: #{character.created_at}"
      puts "   Description length: #{character.description.length} characters"
    else
      puts "❌ Context Analyzer character not found"
      puts "Run 'rails context_analyzer:setup' to create it"
      exit 1
    end
  end
end
