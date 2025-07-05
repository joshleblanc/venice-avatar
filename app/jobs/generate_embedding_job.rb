class GenerateEmbeddingJob < ApplicationJob
  def perform(user, text)
    return unless user.venice_key.present?

    client = VeniceClient::EmbeddingsApi.new
    client.api_client.config.access_token = user.venice_key

    embedding = client.create_embedding({
      model: "text-embedding-bge-m3",
      input: text,
      encoding_format: "float",
    })

    embedding.data.first[:embedding]
  end
end
