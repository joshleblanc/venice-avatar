class GenerateCharacterEmbeddingJob < ApplicationJob
  def perform(model, user)
    embedding = GenerateEmbeddingJob.perform_now(user, "#{model.name}: #{model.description}")

    model.update(embedding: embedding)
  end
end
