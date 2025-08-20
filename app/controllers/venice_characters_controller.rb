class VeniceCharactersController < ApplicationController
  # GET /venice_characters
  def index
    authorize Character
    @venice_characters = policy_scope(Character.where(user_created: false).order(:name))
  end
end

