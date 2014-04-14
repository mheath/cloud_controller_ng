module VCAP::Services::ServiceBrokers
  class NullClient
    def unbind(_)
      {}
    end

    def deprovision(_)
      {}
    end
  end
end
