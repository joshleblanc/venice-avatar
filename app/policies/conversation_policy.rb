class ConversationPolicy < ApplicationPolicy
  def regenerate_scene?
    update?
  end

  def image_style?
    update?
  end
end
