class CharacterSchedulesController < ApplicationController
  before_action :set_character
  before_action :set_schedule, only: [:show, :edit, :update, :destroy, :toggle]
  
  def index
    authorize CharacterSchedule
    @schedules = @character.character_schedules.order(:priority, :name)
  end
  
  def show
    authorize @schedule
  end
  
  def new
    @schedule = @character.character_schedules.build
    authorize @schedule
  end
  
  def create
    @schedule = @character.character_schedules.build(schedule_params)
    authorize @schedule
    
    if @schedule.save
      redirect_to character_character_schedules_path(@character), 
                  notice: 'Character schedule was successfully created.'
    else
      render :new
    end
  end
  
  def edit
    authorize @schedule
  end
  
  def update
    authorize @schedule
    
    if @schedule.update(schedule_params)
      redirect_to character_character_schedules_path(@character), 
                  notice: 'Character schedule was successfully updated.'
    else
      render :edit
    end
  end
  
  def destroy
    authorize @schedule
    @schedule.destroy
    redirect_to character_character_schedules_path(@character), 
                notice: 'Character schedule was successfully deleted.'
  end
  
  def toggle
    authorize @schedule
    @schedule.update(active: !@schedule.active)
    redirect_to character_character_schedules_path(@character), 
                notice: "Schedule #{@schedule.active? ? 'activated' : 'deactivated'}."
  end
  
  private
  
  def set_character
    @character = Character.find(params[:character_id])
    authorize @character
  end
  
  def set_schedule
    @schedule = @character.character_schedules.find(params[:id])
  end
  
  def schedule_params
    params.require(:character_schedule).permit(
      :name, :description, :schedule_type, :priority, :active,
      trigger_conditions: {}
    )
  end
end