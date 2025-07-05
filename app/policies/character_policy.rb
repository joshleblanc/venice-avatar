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
end
