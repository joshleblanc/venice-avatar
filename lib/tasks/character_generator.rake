namespace :characters do
  desc "Generate a random character automatically"
  task auto_generate: :environment do
    puts "Generating a random character..."
    
    generator = AutoCharacterGeneratorService.new
    character = generator.generate_character
    
    if character
      puts "✅ Successfully generated character: #{character.name}"
      puts "   Description: #{character.description}"
      puts "   Slug: #{character.slug}"
      puts "   Personality generation job queued..."
      puts "   View at: http://localhost:3000/characters/#{character.slug}"
    else
      puts "❌ Failed to generate character"
      exit 1
    end
  end
  
  desc "Generate multiple random characters"
  task :auto_generate_multiple, [:count] => :environment do |t, args|
    count = (args[:count] || 3).to_i
    puts "Generating #{count} random characters..."
    
    generated = 0
    failed = 0
    
    count.times do |i|
      print "Generating character #{i + 1}/#{count}... "
      
      generator = AutoCharacterGeneratorService.new
      character = generator.generate_character
      
      if character
        puts "✅ #{character.name}"
        generated += 1
      else
        puts "❌ Failed"
        failed += 1
      end
      
      # Small delay to avoid overwhelming the API
      sleep(1) if i < count - 1
    end
    
    puts "\n📊 Results:"
    puts "   Generated: #{generated}"
    puts "   Failed: #{failed}"
    puts "   Total: #{count}"
  end
end
