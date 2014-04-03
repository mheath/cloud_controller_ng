require "jobs/runtime/app_bits_packer"
require "jobs/runtime/app_events_cleanup"
require "jobs/runtime/app_usage_events_cleanup"
require "jobs/runtime/blobstore_delete"
require "jobs/runtime/blobstore_upload"
require "jobs/runtime/buildpack_installer"
require "jobs/runtime/droplet_deletion"
require "jobs/runtime/droplet_upload"
require "jobs/runtime/events_cleanup"
require "jobs/runtime/model_deletion"
require "jobs/runtime/legacy_jobs"
require "jobs/enqueuer"
require "jobs/exception_catching_job"
require "jobs/request_job"
require "jobs/timeout_job"

class LocalQueue < Struct.new(:config)
  def to_s
    "cc-#{config[:name]}-#{config[:index]}"
  end
end
