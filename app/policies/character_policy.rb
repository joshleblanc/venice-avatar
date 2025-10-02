class CharacterPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.admin?
        scope.all
      else
        scope.where(user_created: true, user: user).or(scope.where(user_created: false))
      end
    end
  end

  def enhance_description?
    user.present?
  end

  def enhance_scenario?
    user.present?
  end

  def auto_generate?
    user.present?
  end
end
