class ConversationPolicy < ApplicationPolicy
  def regenerate_scene?
    update?
  end
end
