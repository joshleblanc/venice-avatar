class MessagePolicy < ApplicationPolicy
    def regenerate?
        user == record.user
    end
end
