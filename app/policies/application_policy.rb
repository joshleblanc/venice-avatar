# frozen_string_literal: true

class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?
    user.present?
  end

  def show?
    record.user == user || user.admin?
  end

  def create?
    user.present?
  end

  def new?
    create?
  end

  def update?
    user.admin? || record.user == user
  end

  def edit?
    update?
  end

  def destroy?
    user.admin? || record.user == user
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      if user.admin?
        scope.all
      else
        scope.where(user: user)
      end
    end

    private

    attr_reader :user, :scope
  end
end
