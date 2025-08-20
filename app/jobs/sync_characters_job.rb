class SyncCharactersJob < ApplicationJob
  queue_as :default

  def perform(*args)
    VeniceClient::CharactersApi.new.list_characters.data.each do |data|
      begin
        character = Character.find_or_initialize_by(slug: data.slug)
        character.assign_attributes(
          adult: data.adult,
          external_created_at: data.created_at,
          description: data.description,
          name: data.name,
          share_url: data.share_url,
          stats: data.stats,
          external_updated_at: data.updated_at,
          web_enabled: data.web_enabled,
          tag_list: data.tags,
        )
        character.save! if character.changed?
      rescue => e
        p "Failed to import character: #{e.message} - #{data}"
      end
    end
  end
end
