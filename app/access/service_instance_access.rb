module VCAP::CloudController
  class ServiceInstanceAccess < BaseAccess
    def create?(service_instance)
      return super if super
      return false if service_instance.in_suspended_org?
      service_instance.space.developers.include?(context.user)
    end

    def update?(service_instance)
      create?(service_instance)
    end

    def delete?(service_instance)
      create?(service_instance)
    end
  end

  class ManagedServiceInstanceAccess < ServiceInstanceAccess
  end

  class UserProvidedServiceInstanceAccess < ServiceInstanceAccess
  end
end
