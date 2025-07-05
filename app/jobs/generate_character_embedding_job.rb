class GenerateCharacterEmbeddingJob < ApplicationJob
  def perform(model)
    embedding = GenerateEmbeddingJob.perform_now(model.user, "#{model.name}: #{model.description}")

    model.update(embedding: embedding)
  end
end
