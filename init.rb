# Initializer where we inject the mock gateway into global variable AUTHNET_GATEWAY or setup the real client

if !Rails.env.production?
  ActiveMerchant::Billing::Base.mode = :test
end

$using_mock_auth_net_gateway = false

# Use FORCE_AUTH_NET to use the real Auth.net API in tests
# Use MOCK_AUTH_NET to use the mock Auth.net API even in development (good on a plane!)
if Rails.env.test? && !ENV.has_key?("FORCE_AUTH_NET") || ENV.has_key?("MOCK_AUTH_NET")
  MockAuthorizeNetCimGateway::LOGGER.info "Test env: using mock auth net"
  ::AUTHNET_GATEWAY = MockAuthorizeNetCimGateway.new
  $using_mock_auth_net_gateway = true

else
  ::AUTHNET_GATEWAY = ActiveMerchant::Billing::AuthorizeNetCimGateway.new(
      :login => ENV["AUTH_NET_LOGIN"],
      :password => ENV["AUTH_NET_API_TOKEN"],
      :test_requests => false
  )
end