module VCAP::CloudController
  class SecurityGroupStagingDefaultsController < RestController::ModelController
    def self.model
      SecurityGroup
    end

    def self.path
      "#{ROUTE_PREFIX}/config/staging_security_groups"
    end

    def self.not_found_exception(guid)
      Errors::ApiError.new_from_details("SecurityGroupStagingDefaultInvalid", guid)
    end

    define_attributes do
      attribute :security_group_guid, String
    end

    define_messages

    get path, :enumerate

    put path_guid, :update
    def update(guid)
      obj = find_guid_and_validate_access(:update, guid)

      model.db.transaction(savepoint: true) do
        obj.lock!
        obj.update_from_hash({"staging_default" => true})
      end

      [
          HTTP::OK,
          object_renderer.render_json(self.class, obj, @opts)
      ]
    end

    delete path_guid, :delete
    def delete(guid)
      obj = find_guid_and_validate_access(:delete, guid)

      model.db.transaction(savepoint: true) do
        obj.lock!
        obj.update_from_hash({"staging_default" => false})
      end

      [
          HTTP::NO_CONTENT
      ]
    end

    def read(_)
      raise Errors::ApiError.new_from_details("NotAuthorized") unless roles.admin?
      super
    end

    def enumerate
      raise Errors::ApiError.new_from_details("NotAuthorized") unless roles.admin?
      super
    end

    private

    def filter_dataset(dataset)
      dataset.filter(staging_default: true)
    end
  end
end