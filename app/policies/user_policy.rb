class UserPolicy < ApplicationPolicy
  def index
    false
  end

  def update?
    user.admin? || record == user
  end

  def new?
    true
  end

  def create?
    true
  end

  def destroy?
    user.admin? || record == user
  end

  def show?
    user.admin? || record == user
  end
end
