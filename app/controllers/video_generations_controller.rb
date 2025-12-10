class VideoGenerationsController < ApplicationController
  before_action :set_conversation, only: [:create, :quote]
  before_action :set_video_generation, only: [:show, :status]

  # GET /conversations/:conversation_id/video_generations/:id
  def show
    authorize @video_generation

    respond_to do |format|
      format.html { redirect_to @video_generation.conversation }
      format.json do
        render json: {
          id: @video_generation.id,
          status: @video_generation.status,
          progress: @video_generation.progress_percentage,
          estimated_time_remaining: @video_generation.estimated_time_remaining,
          video_url: @video_generation.video.attached? ? url_for(@video_generation.video) : nil,
          error: @video_generation.error
        }
      end
    end
  end

  # GET /conversations/:conversation_id/video_generations/:id/status
  def status
    authorize @video_generation

    render json: {
      id: @video_generation.id,
      status: @video_generation.status,
      progress: @video_generation.progress_percentage,
      estimated_time_remaining: @video_generation.estimated_time_remaining,
      video_url: @video_generation.video.attached? ? url_for(@video_generation.video) : nil,
      error: @video_generation.error
    }
  end

  # POST /conversations/:conversation_id/video_generations/quote
  def quote
    authorize VideoGeneration, :quote?

    service = VideoGenerationService.new(@conversation)
    result = service.quote(
      duration: video_params[:duration] || "5s",
      resolution: video_params[:resolution] || "720p"
    )

    respond_to do |format|
      format.json { render json: result }
      format.turbo_stream { render json: result }
    end
  end

  # POST /conversations/:conversation_id/video_generations
  def create
    authorize VideoGeneration

    unless @conversation.scene_image.attached?
      respond_to do |format|
        format.html { redirect_to @conversation, alert: "No scene image available to convert to video" }
        format.json { render json: { error: "No scene image available" }, status: :unprocessable_entity }
      end
      return
    end

    # Check if there's already a video in progress
    if @conversation.video_generations.in_progress.exists?
      respond_to do |format|
        format.html { redirect_to @conversation, alert: "A video is already being generated" }
        format.json { render json: { error: "Video generation already in progress" }, status: :unprocessable_entity }
      end
      return
    end

    QueueVideoJob.perform_later(
      @conversation,
      duration: video_params[:duration] || "5s",
      resolution: video_params[:resolution] || "720p"
    )

    respond_to do |format|
      format.html { redirect_to @conversation, notice: "Video generation started" }
      format.turbo_stream { head :ok }
      format.json { render json: { status: "queued" }, status: :accepted }
    end
  end

  private

  def set_conversation
    @conversation = Conversation.find(params[:conversation_id])
    authorize @conversation, :show?
  end

  def set_video_generation
    @video_generation = VideoGeneration.find(params[:id])
  end

  def video_params
    params.permit(:duration, :resolution)
  end
end
