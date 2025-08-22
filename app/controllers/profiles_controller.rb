class ProfilesController < ApplicationController
  before_action :load_available_traits_and_styles, only: [:edit, :update]

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

  def load_available_traits_and_styles
    begin
      # Fetch traits for text and image
      text_traits = FetchTraitsJob.perform_now(Current.user, "text") || {}
      image_traits = FetchTraitsJob.perform_now(Current.user, "image") || {}

      # Build options: label by trait name, value is trait key
      @text_traits = text_traits.keys.map { |k| [k.to_s.titleize, k] }
      @image_traits = image_traits.keys.map { |k| [k.to_s.titleize, k] }

      # Determine selected trait: if current value is a model id, remap to trait key when possible
      @selected_text_trait = if Current.user.preferred_text_model.present?
        text_traits.key(Current.user.preferred_text_model) || Current.user.preferred_text_model
      else
        ""
      end
      @selected_image_trait = if Current.user.preferred_image_model.present?
        image_traits.key(Current.user.preferred_image_model) || Current.user.preferred_image_model
      else
        ""
      end

      image_styles_response = FetchImageStylesJob.perform_now(Current.user)
      @image_styles = image_styles_response.map do |style|
        if style == "Anime"
          ["#{style} (Default)", style]
        else
          [style, style]
        end
      end
      @image_styles << ["None", ""]
    rescue => e
      Rails.logger.error "Failed to fetch models from Venice API: #{e.message}"
      @text_traits = []
      @image_traits = []
      @image_styles = []
      flash.now[:alert] = "Unable to load available traits. Please try again later."
    end
  end
end
