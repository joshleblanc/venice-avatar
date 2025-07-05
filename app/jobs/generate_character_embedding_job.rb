class GenerateCharacterEmbeddingJob < ApplicationJob
  def perform(model)
    embedding = GenerateEmbeddingJob.perform_now("#{model.name}: #{model.description}")

    model.update(embedding: embedding)
  end
end
