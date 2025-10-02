class ProfilesController < ApplicationController
  before_action :load_available_models_and_styles, only: [:edit, :update]

  def show
    @user = Current.user
    authorize @user
    
    # Get the actual model IDs for the selected traits
    @selected_text_model_id = @user.text_model
    @selected_image_model_id = @user.image_model
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
    params.require(:user).permit(:timezone, :safe_mode, :reasoning_enabled, :preferred_image_style, :venice_key, :preferred_image_model, :preferred_text_model)
  end

  def load_available_models_and_styles
    begin
      text_models = FetchModelsJob.perform_now(Current.user, "text") || []
      image_models = FetchModelsJob.perform_now(Current.user, "image") || []

      @text_models = text_models.map { |model| [model.model_spec.name || model.id, model.id] }
      @image_models = image_models.map { |model| [model.model_spec.name || model.id, model.id] }

      p @text_models

      @selected_text_model = current_user.preferred_text_model || ""
      @selected_image_model = current_user.preferred_image_model || ""

      image_styles_response = FetchImageStylesJob.perform_now(current_user)
      @image_styles = image_styles_response.map do |style|
        [style, style]
      end
      @image_styles << ["None", ""]
    rescue => e
      Rails.logger.error "Failed to load models/styles for profile: #{e.message}"
      @text_models = []
      @image_models = []
      @image_styles = []
      flash.now[:alert] = "Unable to load available models. Please try again later."
    end
  end
end
