# frozen_string_literal: true

class VideoGenerationPolicy < ApplicationPolicy
  def show?
    record.conversation.user == user || user.admin?
  end

  def create?
    user.present? && user.venice_key_valid?
  end

  def quote?
    create?
  end

  def status?
    show?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin?
        scope.all
      else
        scope.joins(:conversation).where(conversations: { user_id: user.id })
      end
    end
  end
end
