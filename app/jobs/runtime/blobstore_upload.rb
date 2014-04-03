module VCAP::CloudController
  module Jobs
    module Runtime
      class BlobstoreUpload < Struct.new(:local_path, :blobstore_key, :blobstore_name)
        def perform
          begin
            logger = Steno.logger("cc.background")
            logger.info("Uploading '#{blobstore_key}' to blobstore '#{blobstore_name}'")
            blobstore = CloudController::DependencyLocator.instance.public_send(blobstore_name)
            blobstore.cp_to_blobstore(local_path, blobstore_key)
          ensure
            FileUtils.rm_f(local_path)
          end
        end

        def job_name_in_configuration
          :blobstore_upload
        end
      end
    end
  end
end
