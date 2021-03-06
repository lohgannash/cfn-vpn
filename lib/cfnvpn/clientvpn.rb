require 'aws-sdk-ec2'
require 'cfnvpn/log'
require 'netaddr'

module CfnVpn
  class ClientVpn
    include CfnVpn::Log

    def initialize(name,region)
      @client = Aws::EC2::Client.new(region: region)
      @name = name
    end

    def get_endpoint()
      resp = @client.describe_client_vpn_endpoints({
        filters: [{ name: "tag:cfnvpn:name", values: [@name] }]
      })
      if resp.client_vpn_endpoints.empty?
        Log.logger.error "unable to find endpoint with tag Key: cfnvpn:name with Value: #{@name}"
        raise "Unable to find client vpn"
      end
      return resp.client_vpn_endpoints.first
    end

    def get_endpoint_id()
      return get_endpoint().client_vpn_endpoint_id
    end

    def get_dns_servers()
      return get_endpoint().dns_servers
    end

    def get_config(endpoint_id)
      resp = @client.export_client_vpn_client_configuration({
        client_vpn_endpoint_id: endpoint_id
      })
      return resp.client_configuration
    end

    def get_rekove_list(endpoint_id)
      resp = @client.export_client_vpn_client_certificate_revocation_list({
        client_vpn_endpoint_id: endpoint_id
      })
      return resp.certificate_revocation_list
    end

    def put_revoke_list(endpoint_id,revoke_list)
      list = File.read(revoke_list)
      @client.import_client_vpn_client_certificate_revocation_list({
        client_vpn_endpoint_id: endpoint_id,
        certificate_revocation_list: list
      })
    end

    def get_sessions(endpoint_id)
      params = {
        client_vpn_endpoint_id: endpoint_id,
        max_results: 20
      }
      resp = @client.describe_client_vpn_connections(params)
      return resp.connections
    end

    def kill_session(endpoint_id, connection_id)
      @client.terminate_client_vpn_connections({
        client_vpn_endpoint_id: endpoint_id,
        connection_id: connection_id
      })
    end

    def get_target_networks(endpoint_id)
      resp = @client.describe_client_vpn_target_networks({
        client_vpn_endpoint_id: endpoint_id
      })
      return resp.client_vpn_target_networks.first
    end

    def add_route(cidr,description)
      endpoint_id = get_endpoint_id()
      subnet_id = get_target_networks(endpoint_id).target_network_id

      @client.create_client_vpn_route({
        client_vpn_endpoint_id: endpoint_id,
        destination_cidr_block: cidr,
        target_vpc_subnet_id: subnet_id,
        description: description
      })

      resp = @client.authorize_client_vpn_ingress({
        client_vpn_endpoint_id: endpoint_id,
        target_network_cidr: cidr,
        authorize_all_groups: true,
        description: description
      })

      return resp.status
    end

    def del_route(cidr)
      endpoint_id = get_endpoint_id()
      subnet_id = get_target_networks(endpoint_id).target_network_id

      revoke = @client.revoke_client_vpn_ingress({
        revoke_all_groups: true,
        client_vpn_endpoint_id: endpoint_id,
        target_network_cidr: cidr
      })

      route = @client.delete_client_vpn_route({
        client_vpn_endpoint_id: endpoint_id,
        target_vpc_subnet_id: subnet_id,
        destination_cidr_block: cidr
      })

      return route.status, revoke.status
    end

    def get_routes()
      endpoint_id = get_endpoint_id()
      resp = @client.describe_client_vpn_routes({
        client_vpn_endpoint_id: endpoint_id,
        max_results: 20
      })
      return resp.routes
    end

    def route_exists?(cidr)
      routes = get_routes()
      resp = routes.select { |route| route if route.destination_cidr == cidr }
      return resp.any?
    end

    def get_routes()
      endpoint_id = get_endpoint_id()
      resp = @client.describe_client_vpn_routes({
        client_vpn_endpoint_id: endpoint_id,
        max_results: 20
      })
      return resp.routes
    end

    def get_route_with_mask()
      routes = get_routes()
      routes
        .select { |r| r if r.destination_cidr != '0.0.0.0/0' }
        .collect { |r| { route: r.destination_cidr.split('/').first, mask: NetAddr::CIDR.create(r.destination_cidr).wildcard_mask }}
    end

    def valid_cidr?(cidr)
      return !(cidr =~ /^([0-9]{1,3}\.){3}[0-9]{1,3}(\/([0-9]|[1-2][0-9]|3[0-2]))?$/).nil?
    end

  end
end
