class ProfilesController < ApplicationController
  before_action :load_available_models, only: [:edit, :update]

  def show
    @user = Current.user
  end

  def edit
    @user = Current.user
  end

  def update
    @user = Current.user

    if @user.update(user_params)
      redirect_to profile_path, notice: "Profile updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:timezone, :preferred_image_model, :preferred_text_model)
  end

  def load_available_models
    begin
      models_api = VeniceClient::ModelsApi.new

      # Fetch text models
      text_models_response = models_api.list_models(type: "text")
      @text_models = text_models_response.data.map do |model|
        if model[:id] == "venice-uncensored"
          ["#{model[:model_spec][:name]} (Default)", model[:id]]
        else
          [model[:model_spec][:name], model[:id]]
        end
      end

      # Fetch image models
      image_models_response = models_api.list_models(type: "image")
      @image_models = image_models_response.data.map do |model|
        if model[:id] == "flux-dev-uncensored-11"
          ["#{model[:model_spec][:name]} (Default)", model[:id]]
        else
          [model[:model_spec][:name], model[:id]]
        end
      end
    rescue => e
      Rails.logger.error "Failed to fetch models from Venice API: #{e.message}"
      @text_models = []
      @image_models = []
      flash.now[:alert] = "Unable to load available models. Please try again later."
    end
  end
end
