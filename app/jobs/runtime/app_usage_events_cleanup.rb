require "repositories/runtime/app_usage_event_repository"

module VCAP::CloudController
  module Jobs
    module Runtime
      class AppUsageEventsCleanup < Struct.new(:cutoff_age_in_days)
        def perform
          logger = Steno.logger("cc.background")
          logger.info("Cleaning up old AppUsageEvent rows")


          repository = Repositories::Runtime::AppUsageEventRepository.new
          deleted_count = repository.delete_events_create_before(cutoff_time)

          logger.info("Cleaned up #{deleted_count} AppUsageEvent rows")
        end

        def job_name_in_configuration
          :app_usage_events_cleanup
        end

        private

        def cutoff_time
          Time.now - cutoff_age_in_days.days
        end
      end
    end
  end
end
