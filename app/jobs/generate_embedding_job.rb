class GenerateEmbeddingJob < ApplicationJob
  # Accepts an Account
  def perform(account, text)
    client = account.api_client
    return unless client

    api = VeniceClient::EmbeddingsApi.new(client)

    embedding = api.create_embedding({
      model: "text-embedding-bge-m3",
      input: text,
      encoding_format: "float",
    })

    embedding.data.first.embedding
  end
end
