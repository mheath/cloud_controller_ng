require 'spec_helper'

module VCAP::Services::SSO
  describe DashboardClientManager do
    let(:service_broker) { VCAP::CloudController::ServiceBroker.make }
    let(:manager) { DashboardClientManager.new(service_broker) }
    let(:client_manager) { double('client_manager') }

    describe '#initialize' do
      subject{ manager }

      it 'sets the service_broker' do
        manager = DashboardClientManager.new(service_broker)
        expect(manager.service_broker).to eql(service_broker)
      end

      its(:warnings) { should == [] }
      its(:has_warnings?) { should == false }
    end

    describe '#synchronize_clients_with_catalog' do
      let(:dashboard_client_attrs_1) do
        {
          'id'           => 'abcde123',
          'secret'       => 'sekret',
          'redirect_uri' => 'http://example.com'
        }
      end
      let(:dashboard_client_attrs_2) do
        {
          'id'           => 'fghijk456',
          'secret'       => 'differentsekret',
          'redirect_uri' => 'http://example.com/somethingelse'
        }
      end
      let(:catalog_service) {
        VCAP::Services::ServiceBrokers::V2::CatalogService.new(service_broker,
                               'id'               => 'f8ccf75f-4552-4143-97ea-24ccca5ad068',
                               'dashboard_client' => dashboard_client_attrs_1,
                               'name'             => 'service-1',
        )
      }
      let(:catalog_service_2) {
        VCAP::Services::ServiceBrokers::V2::CatalogService.new(service_broker,
                               'id'               => '0489055c-97b8-4754-8221-c69375ddb33b',
                               'dashboard_client' => dashboard_client_attrs_2,
                               'name'             => 'service-2',
        )
      }
      let(:catalog_service_without_dashboard_client) {
        VCAP::Services::ServiceBrokers::V2::CatalogService.new(service_broker,
                               'id'               => '4b6088af-cdc4-4ee2-8292-9fa93af32fc8',
                               'name'             => 'service-3',
        )
      }
      let(:catalog_services) { [catalog_service, catalog_service_2, catalog_service_without_dashboard_client] }
      let(:catalog) { double(:catalog, services: catalog_services) }

      before do
        allow(VCAP::Services::SSO::UAA::UaaClientManager).to receive(:new).and_return(client_manager)
        allow(client_manager).to receive(:get_clients).and_return([])
        allow(client_manager).to receive(:modify_transaction)
      end

      describe 'modifying the UAA and CCDB' do
        context 'when no dashboard sso clients present in the catalog exist in UAA' do
          before do
            allow(client_manager).to receive(:get_clients).and_return([])
          end

          it 'creates clients only for all services that specify dashboard_client' do
            expect(client_manager).to receive(:modify_transaction) do |changeset|
              expect(changeset.length).to eq 2
              expect(changeset.all? {|change| change.is_a? Commands::CreateClientCommand}).to be_true
              expect(changeset[0].client_attrs).to eq dashboard_client_attrs_1
              expect(changeset[1].client_attrs).to eq dashboard_client_attrs_2
            end

            manager.synchronize_clients_with_catalog(catalog)
          end

          it 'claims the clients' do
            expect {
              manager.synchronize_clients_with_catalog(catalog)
            }.to change { VCAP::CloudController::ServiceDashboardClient.count }.by 2

            expect(VCAP::CloudController::ServiceDashboardClient.find(uaa_id: dashboard_client_attrs_1['id'])).to_not be_nil
            expect(VCAP::CloudController::ServiceDashboardClient.find(uaa_id: dashboard_client_attrs_2['id'])).to_not be_nil
          end

          it 'returns true' do
            expect(manager.synchronize_clients_with_catalog(catalog)).to eq(true)
          end
        end

        context 'when some, but not all dashboard sso clients exist in UAA' do
          before do
            allow(client_manager).to receive(:get_clients).and_return([{'client_id' => catalog_service.dashboard_client['id']}])
          end

          context 'when the broker has already claimed a requested UAA client' do
            before do
              VCAP::CloudController::ServiceDashboardClient.new(
                uaa_id: catalog_service.dashboard_client['id'],
                service_broker: service_broker
              ).save
            end

            it 'creates the clients that do not currently exist' do
              expect(client_manager).to receive(:modify_transaction) do |changeset|
                create_commands = changeset.select { |command| command.is_a? Commands::CreateClientCommand}
                expect(create_commands.length).to eq 1
                expect(create_commands[0].client_attrs).to eq dashboard_client_attrs_2
              end

              manager.synchronize_clients_with_catalog(catalog)
            end

            it 'updates the client that is already in uaa' do
              expect(client_manager).to receive(:modify_transaction) do |changeset|
                update_commands = changeset.select { |command| command.is_a? Commands::UpdateClientCommand}
                expect(update_commands.length).to eq 1
                expect(update_commands[0].client_attrs).to eq dashboard_client_attrs_1
              end

              manager.synchronize_clients_with_catalog(catalog)
            end

            it 'claims the clients' do
              expect {
                manager.synchronize_clients_with_catalog(catalog)
              }.to change { VCAP::CloudController::ServiceDashboardClient.count }.by 1

              expect(VCAP::CloudController::ServiceDashboardClient.find(uaa_id: dashboard_client_attrs_1['id'])).to_not be_nil
              expect(VCAP::CloudController::ServiceDashboardClient.find(uaa_id: dashboard_client_attrs_2['id'])).to_not be_nil

            end

            it 'returns true' do
              expect(manager.synchronize_clients_with_catalog(catalog)).to eq(true)
            end
          end

          context 'when there is no claim but the requested client exists in UAA' do
            it 'does not create any uaa clients' do
              manager.synchronize_clients_with_catalog(catalog)

              expect(client_manager).to_not have_received(:modify_transaction)
            end

            it 'does not claim any clients for CC' do
              expect(VCAP::CloudController::ServiceDashboardClient.count).to eq(0)
              expect { manager.synchronize_clients_with_catalog(catalog) }.not_to change{ VCAP::CloudController::ServiceDashboardClient.count }
            end

            it 'returns false' do
              expect(manager.synchronize_clients_with_catalog(catalog)).to eq(false)
            end

            it 'has errors for the service' do
              manager.synchronize_clients_with_catalog(catalog)

              expect(manager.errors.for(catalog_service)).not_to be_empty
            end
          end
        end

        context 'when the UAA has clients claimed by CC that are no longer used by a service' do
          let(:unused_id) { 'no-longer-used' }
          let(:catalog) do
            double(:catalog, services: [catalog_service, catalog_service_without_dashboard_client])
          end

          before do
            allow(client_manager).to receive(:get_clients) do |ids|
              ids.map do |id|
                { 'client_id' => id }
              end
            end

            VCAP::CloudController::ServiceDashboardClient.new(
              uaa_id: unused_id,
              service_broker: service_broker
            ).save

            VCAP::CloudController::ServiceDashboardClient.new(
              uaa_id: dashboard_client_attrs_1['id'],
              service_broker: service_broker
            ).save
          end

          it 'deletes the client from the uaa' do
            expect(client_manager).to receive(:modify_transaction) do |changeset|
              delete_commands = changeset.select { |command| command.is_a? Commands::DeleteClientCommand}
              expect(delete_commands.length).to eq 1
              expect(delete_commands[0].client_id).to eq(unused_id)
            end

            manager.synchronize_clients_with_catalog(catalog)
          end

          it 'removes the claims for the deleted clients' do
            manager.synchronize_clients_with_catalog(catalog)
            expect(VCAP::CloudController::ServiceDashboardClient.find(uaa_id: unused_id)).to be_nil
          end

          it 'returns true' do
            expect(manager.synchronize_clients_with_catalog(catalog)).to be_true
          end
        end

        context 'when a different broker has already claimed the requested UAA client' do
          let(:other_broker) { double(:other_broker, id: SecureRandom.uuid)}
          let(:existing_client) do
            double(:client,
              uaa_id: dashboard_client_attrs_1['id'],
              service_broker: other_broker)
          end

          before do
            allow(VCAP::CloudController::ServiceDashboardClient).to receive(:find_client_by_uaa_id).with(
              dashboard_client_attrs_1['id']
            ).and_return(existing_client)

            allow(VCAP::CloudController::ServiceDashboardClient).to receive(:find_client_by_uaa_id).with(
              dashboard_client_attrs_2['id']
            ).and_return(nil)
          end

          it 'populates errors on the manager' do
            manager.synchronize_clients_with_catalog(catalog)
            expect(manager.errors).not_to be_empty
          end

          it 'returns false' do
            expect(manager.synchronize_clients_with_catalog(catalog)).to eq(false)
          end
        end
      end

      describe 'exception handling' do
        context 'when getting UAA clients raises an error' do
          before do
            error = VCAP::Services::SSO::UAA::UaaError.new('my test error')
            expect(client_manager).to receive(:get_clients).and_raise(error)
          end

          it 'raises a ServiceBrokerDashboardClientFailure error' do
            expect{ manager.synchronize_clients_with_catalog(catalog) }.to raise_error(VCAP::Errors::ApiError) do |err|
              expect(err.name).to eq('ServiceBrokerDashboardClientFailure')
              expect(err.message).to eq('my test error')
            end
          end
        end

        context 'when modifying UAA clients fails' do
          let(:unused_id) { 'no-longer-used' }

          before do
            allow(client_manager).to receive(:get_clients).and_return([{'client_id' => unused_id}])
            allow(client_manager).to receive(:modify_transaction).and_raise(VCAP::Services::SSO::UAA::UaaError.new('error message'))

            VCAP::CloudController::ServiceDashboardClient.new(
              uaa_id: unused_id,
              service_broker: service_broker
            ).save
          end

          it 'does not add new claims' do
            manager.synchronize_clients_with_catalog(catalog) rescue nil

            dashboard_client = VCAP::CloudController::ServiceDashboardClient.find(uaa_id: dashboard_client_attrs_1['id'])
            expect(dashboard_client).to be_nil
          end

          it 'does not delete existing claims' do
            manager.synchronize_clients_with_catalog(catalog) rescue nil

            dashboard_client = VCAP::CloudController::ServiceDashboardClient.find(uaa_id: unused_id)
            expect(dashboard_client).to_not be_nil
          end

          it 'does not modify any of the claims' do
            VCAP::CloudController::ServiceDashboardClient.new(
              uaa_id: dashboard_client_attrs_2['id'],
              service_broker: nil
            ).save

            manager.synchronize_clients_with_catalog(catalog) rescue nil

            dashboard_client = VCAP::CloudController::ServiceDashboardClient.find(uaa_id: dashboard_client_attrs_2['id'])
            expect(dashboard_client.service_broker).to be_nil
          end

          it 'raises a ServiceBrokerDashboardClientFailure error' do
            expect{ manager.synchronize_clients_with_catalog(catalog) }.to raise_error(VCAP::Errors::ApiError) do |err|
              expect(err.name).to eq('ServiceBrokerDashboardClientFailure')
              expect(err.message).to eq('error message')
            end
          end
        end

        context 'when claiming the client for the broker fails' do
          before do
            allow(VCAP::CloudController::ServiceDashboardClient).to receive(:claim_client_for_broker).and_raise
          end

          it 'does not modify the UAA client' do
            manager.synchronize_clients_with_catalog(catalog) rescue nil
            expect(client_manager).to_not have_received(:modify_transaction)
          end
        end
      end

      context 'when the cloud controller is not configured to modify sso_client' do
        before do
          allow(VCAP::CloudController::Config.config).to receive(:[]).with(anything).and_call_original
          allow(VCAP::CloudController::Config.config).to receive(:[]).with(:uaa_client_name).and_return nil
          allow(VCAP::CloudController::Config.config).to receive(:[]).with(:uaa_client_secret).and_return nil
          allow(client_manager).to receive(:modify_transaction)
        end

        it 'does not create/update/delete any clients' do
          manager.synchronize_clients_with_catalog(catalog)
          expect(client_manager).not_to have_received(:modify_transaction)
        end

        it 'returns true' do
          expect(manager.synchronize_clients_with_catalog(catalog)).to be_true
        end

        context 'and the catalog requested dashboard clients' do
          it 'adds a warning' do
            manager.synchronize_clients_with_catalog(catalog)

            expect(manager.has_warnings?).to be_true
            expect(manager.warnings).to include('Warning: This broker includes configuration for a dashboard client. Auto-creation of OAuth2 clients has been disabled in this Cloud Foundry instance. The broker catalog has been updated but its dashboard client configuration will be ignored.')
          end
        end

        context 'and the catalog did not request dashboard clients' do
          let(:catalog) { double(:catalog, services: [catalog_service_without_dashboard_client]) }

          it 'does not add a warning' do
            manager.synchronize_clients_with_catalog(catalog)

            expect(manager.has_warnings?).to be_false
          end
        end
      end
    end

    describe '#remove_clients_for_broker' do
      let(:client_to_delete_1) { 'client-to-delete-1' }
      let(:client_to_delete_2) { 'client-to-delete-2' }

      before do
        allow(VCAP::Services::SSO::UAA::UaaClientManager).to receive(:new).and_return(client_manager)
        allow(client_manager).to receive(:modify_transaction)

        VCAP::CloudController::ServiceDashboardClient.new(
          uaa_id: client_to_delete_1,
          service_broker: service_broker
        ).save

        VCAP::CloudController::ServiceDashboardClient.new(
          uaa_id: client_to_delete_2,
          service_broker: service_broker
        ).save

        allow(client_manager).to receive(:get_clients).and_return(
          [
            {'client_id' => client_to_delete_1},
            {'client_id' => client_to_delete_2}
          ])
      end

      it 'deletes all clients for the service broker in UAA' do
        expect(client_manager).to receive(:modify_transaction) do |changeset|
          delete_commands = changeset.select { |command| command.is_a? Commands::DeleteClientCommand}
          expect(changeset.length).to eq(2)
          expect(delete_commands.length).to eq(2)
          expect(delete_commands[0].client_attrs['id']).to eq(client_to_delete_1)
          expect(delete_commands[1].client_attrs['id']).to eq(client_to_delete_2)
        end

        manager.remove_clients_for_broker
      end

      it 'deletes the claims for the service broker in CC' do
        expect(VCAP::CloudController::ServiceDashboardClient.find_clients_claimed_by_broker(service_broker).count).to eq(2)

        manager.remove_clients_for_broker

        expect(VCAP::CloudController::ServiceDashboardClient.find_clients_claimed_by_broker(service_broker).count).to eq(0)
      end

      context 'when deleting UAA clients fails' do
        before do
          error = VCAP::Services::SSO::UAA::UaaError.new('error message')
          allow(client_manager).to receive(:modify_transaction).and_raise(error)
        end

        it 'raises a ServiceBrokerDashboardClientFailure error' do
          expect{ manager.remove_clients_for_broker }.to raise_error(VCAP::Errors::ApiError) do |err|
            expect(err.name).to eq('ServiceBrokerDashboardClientFailure')
            expect(err.message).to eq('error message')
          end
        end

        it 'does not delete any clients claimed in CC' do
          expect(VCAP::CloudController::ServiceDashboardClient.find_clients_claimed_by_broker(service_broker).count).to eq(2)

          manager.remove_clients_for_broker rescue nil

          expect(VCAP::CloudController::ServiceDashboardClient.find_clients_claimed_by_broker(service_broker).count).to eq(2)
        end

      end

      context 'when getting UAA clients raises an error' do
        before do
          error = VCAP::Services::SSO::UAA::UaaError.new('my test error')
          expect(client_manager).to receive(:get_clients).and_raise(error)
        end

        it 'raises a ServiceBrokerDashboardClientFailure error' do
          expect{ manager.remove_clients_for_broker }.to raise_error(VCAP::Errors::ApiError) do |err|
            expect(err.name).to eq('ServiceBrokerDashboardClientFailure')
            expect(err.message).to eq('my test error')
          end
        end
      end

      context 'when removing CC claims raises an exception' do
        before do
          allow(VCAP::CloudController::ServiceDashboardClient).to receive(:remove_claim_on_client).and_raise("test error")
        end

        it 'reraises the error' do
          expect { manager.remove_clients_for_broker }.to raise_error("test error")
        end

        it 'does not delete the UAA clients' do
          manager.remove_clients_for_broker rescue nil
          expect(client_manager).to_not have_received(:modify_transaction)
        end
      end

      context 'when the cloud controller is not configured to modify sso_client' do
        before do
          allow(VCAP::CloudController::Config.config).to receive(:[]).with(anything).and_call_original
          allow(VCAP::CloudController::Config.config).to receive(:[]).with(:uaa_client_name).and_return nil
          allow(VCAP::CloudController::Config.config).to receive(:[]).with(:uaa_client_secret).and_return nil
        end

        it 'does not delete any clients in UAA' do
          manager.remove_clients_for_broker
          expect(client_manager).not_to have_received(:modify_transaction)
        end

        it 'does not delete any clients claimed in CC' do
          expect(VCAP::CloudController::ServiceDashboardClient.find_clients_claimed_by_broker(service_broker).count).to eq(2)

          manager.remove_clients_for_broker rescue nil

          expect(VCAP::CloudController::ServiceDashboardClient.find_clients_claimed_by_broker(service_broker).count).to eq(2)
        end
      end
    end
  end
end
