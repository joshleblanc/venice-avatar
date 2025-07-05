class GenerateEmbeddingJob < ApplicationJob
  def perform(text)
    embedding = VeniceClient::EmbeddingsApi.new.create_embedding({
      model: "text-embedding-bge-m3",
      input: text,
      encoding_format: "float",
    })

    embedding.data.first[:embedding]
  end
end
