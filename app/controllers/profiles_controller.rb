class ProfilesController < ApplicationController
  before_action :load_available_models, only: [:edit, :update]

  def show
    @user = Current.user
    authorize @user
  end

  def edit
    @user = Current.user
    authorize @user
  end

  def update
    @user = Current.user
    authorize @user

    adj_params = if user_params[:venice_key].blank?
        user_params.without(:venice_key)
      else
        user_params
      end

    if @user.update(adj_params)
      redirect_to profile_path, notice: "Profile updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:timezone, :safe_mode, :preferred_image_style, :venice_key, :preferred_image_model, :preferred_text_model)
  end

  def load_available_models
    begin
      # Fetch text models
      text_models_response = FetchModelsJob.perform_now(Current.user, "text")
      @text_models = text_models_response.map do |model|
        if model.id == "venice-uncensored"
          ["#{model.model_spec.name} (Default)", model.id]
        else
          [model.model_spec.name, model.id]
        end
      end

      # Fetch image models
      image_models_response = FetchModelsJob.perform_now(Current.user, "image")
      @image_models = image_models_response.map do |model|
        if model.id == "hidream"
          ["#{model.model_spec.name} (Default)", model.id]
        else
          [model.model_spec.name, model.id]
        end
      end

      image_styles_response = FetchImageStylesJob.perform_now(Current.user)
      @image_styles = image_styles_response.map do |style|
        if style == "Anime"
          ["#{style} (Default)", style]
        else
          [style, style]
        end
      end
    rescue => e
      Rails.logger.error "Failed to fetch models from Venice API: #{e.message}"
      @text_models = []
      @image_models = []
      @image_styles = []
      flash.now[:alert] = "Unable to load available models. Please try again later."
    end
  end
end
