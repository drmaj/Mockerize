# Class that will mock out functionality of the AuthNet test sandbox for their CIM API.

require 'active_merchant'
# TODO: Setup null_logger for optional logging
# require 'null_logger'

class MockAuthorizeNetCimGateway < ActiveMerchant::Billing::AuthorizeNetCimGateway

  # attr_accessor :logger
  # private :logger=, :logger

  ## Special Numbers
  FAILURE_CREDIT_CARD_NUMBER = "4222222222222"      # If this card is entered, we will reject the payment.
  EXCEPTION_CREDIT_CARD_NUMBER = "4041378749540103" # if this card is entered, payments will throw exceptions
  UNVOIDABLE_TRANSACTION_ID = "98712498798247"      # If this transaction is voided, it will fail

  ## Redis key prefixes
  CUSTOMER_PREFIX = "mockcim__customer__"
  TRANSACTION_PREFIX = "mockcim__transaction__"

  def initialize(options = {})
    # self.logger = options[:logger] || Nulllogger.instance
    @redis_url = ENV["REDISCLOUD_URL"] || ENV["REDISTOGO_URL"] || "localhost:6379"
  end

  def redis
    if @redis.nil?
      if @redis_url.start_with?("redis://")
        # logger.debug "New Redis from redis://"
        @redis = Redis.new(url: @redis_url)
      else
        # logger.debug "New Redis from host/port"
        host, port = @redis_url.split(":")
        @redis = Redis.new(host: host, port: port)
      end
    else
      # Force reconnect to deal with after-fork errors
      #@redis.client.reconnect
    end
    return @redis
  end


  def reset
    # logger.debug "MOCK: reset MockAuthNetCimGateway"
    keys =  redis.keys("#{CUSTOMER_PREFIX}*")
    if !keys.empty?
      ret = redis.del(keys)
      # logger.debug("Deleted #{ret} customers")
    end
    keys = redis.keys("#{TRANSACTION_PREFIX}*")
    if !keys.empty?
      ret = redis.del(keys)
      # logger.debug("Deleted #{ret} transactions")
    end
  end

  # CIM API call
  def create_customer_profile(options)
    # logger.debug "MOCK: create_customer_profile #{options[:profile]}"
    # Copied 'requires' from base class
    requires!(options, :profile)
    requires!(options[:profile], :email) unless options[:profile][:merchant_customer_id] || options[:profile][:description]
    requires!(options[:profile], :description) unless options[:profile][:email] || options[:profile][:merchant_customer_id]
    requires!(options[:profile], :merchant_customer_id) unless options[:profile][:description] || options[:profile][:email]

    customer_profile_id = generate_profile_id
    email = options[:profile][:email]

    # Check for duplicate emails
    if !get_customer_by_email(email).nil?
      puts "Found duplicate:"
      puts get_customer_by_email(email).inspect
      return ActiveMerchant::Billing::Response.new(false, "duplicate record", {})
    end

    profile = {
        "customer_profile_id" => customer_profile_id,
        "email" => options[:profile][:email],
        "payment_profiles" => {}
    }
    set_customer(profile)
    message = "Customer profile created."
    return ActiveMerchant::Billing::Response.new(true, message, profile)
  end

  # CIM API call
  def get_customer_profile(options)
    requires!(options, :customer_profile_id)
    id = options[:customer_profile_id]
    # logger.debug "MOCK: get_customer_profile: #{id}"
    customer = get_customer(options[:customer_profile_id])

    # Authnet returns either a hash (if only one profile) or an array of profiles.
    # Yeah, I'm not fond of that either.
    payment_profiles = nil
    if customer["payment_profiles"].keys.length == 1
      key = customer["payment_profiles"].keys[0]
      # logger.debug "MOCK: found single payment profile: #{key}"
      payment_profiles = mask_cc(customer["payment_profiles"][key])
      payment_profiles["customer_payment_profile_id"] = key
    elsif customer["payment_profiles"].keys.length > 1
      # logger.debug "MOCK: found multiple (#{customer["payment_profiles"].keys.length}) payment profiles"
      payment_profiles = []
      customer["payment_profiles"].each do |this_id, profile|
        profile["customer_payment_profile_id"] = this_id
        payment_profiles << mask_cc(profile)
      end
    end

    response = {
        "profile" => {}
    }
    if !payment_profiles.nil?
      response = {
          "profile" => {
              "email" => customer["email"],
              "payment_profiles" => payment_profiles
          }
      }
    end
    return ActiveMerchant::Billing::Response.new(true, "", response)
  end

  # CIM API call
  def update_customer_profile(options)
    requires!(options, :profile)
    requires!(options[:profile], :customer_profile_id)
    customer_id = options[:profile][:customer_profile_id]
    # logger.debug "MOCK update_customer_profile: #{customer_id}"
    customer = get_customer(customer_id)
    if customer.nil?
      return ActiveMerchant::Billing::Response.new(false, "customer not found", {})
    end

    # logger.debug "Trying to update customer profile with #{options[:profile]}"
    customer["email"] = options[:profile][:email]
    set_customer(customer)
    return ActiveMerchant::Billing::Response.new(true, "Customer profile updated.", customer)
  end

  # CIM API call
  def delete_customer_profile(options)
    requires!(options, :customer_profile_id)
    key = "#{CUSTOMER_PREFIX}#{options[:customer_profile_id]}"
    if redis.exists(key)
      redis.del(key)
      return ActiveMerchant::Billing::Response.new(true, "", {})
    else
      return ActiveMerchant::Billing::Response.new(false, "notfound", {})
    end
  end

  # CIM API call
  def create_customer_payment_profile(options)
    # logger.debug "MOCK: create_customer_payment_profile: #{options.inspect}"
    requires!(options, :customer_profile_id)
    requires!(options, :payment_profile)
    requires!(options[:payment_profile], :payment)

    payment_profile_id = generate_profile_id
    begin
      set_payment_profile(options[:customer_profile_id], payment_profile_id, options[:payment_profile])
      response = {
          "customer_payment_profile_id" => payment_profile_id
      }
      return ActiveMerchant::Billing::Response.new(true, "", response)
    rescue Exception => e
      return ActiveMerchant::Billing::Response.new(false,"#{e}", {})
    end
  end

  # CIM API call
  def update_customer_payment_profile(options)
    requires!(options, :customer_profile_id, :payment_profile)
    requires!(options[:payment_profile], :customer_payment_profile_id)
    profile_id = options[:payment_profile][:customer_payment_profile_id].to_s
    # logger.debug "MOCK: update_customer_payment_profile: #{profile_id}"
    payment_profile = options[:payment_profile]
    begin
      set_payment_profile(options[:customer_profile_id], profile_id, payment_profile)
      response = {
          "customer_payment_profile_id" => profile_id
      }
      return ActiveMerchant::Billing::Response.new(true, "", response)
    rescue Exception => e
      # logger.error "Exception updating billing profile: #{e}"
      return ActiveMerchant::Billing::Response.new(false, "#{e}", {})
    end
  end

  # CIM API call
  def delete_customer_payment_profile(options)
    requires!(options, :customer_profile_id)
    requires!(options, :customer_payment_profile_id)
    payment_profile_id = options[:customer_payment_profile_id].to_s
    # logger.debug "MOCK: delete customer payment profile #{payment_profile_id}"
    customer = get_customer(options[:customer_profile_id])
    if !customer["payment_profiles"].has_key?(payment_profile_id)
      return ActiveMerchant::Billing::Response.new(false, "Not found", {})
    end

    customer["payment_profiles"].delete(payment_profile_id)
    set_customer(customer)
    return ActiveMerchant::Billing::Response.new(true, "Successful.", {})

  end

  # CIM API call
  def create_customer_profile_transaction(options)
    requires!(options, :transaction)
    requires!(options[:transaction], :type)
    case options[:transaction][:type]
      when :void
        return void_transaction(options)
      when :refund
        return refund_transaction(options)
      when :prior_auth_capture
        return prior_auth_capture(options)
      else
        return auth_capture(options)
    end
  end

  # Method for inspecting the mock
  def get_transaction_by_invoice_number(invoice_number)
    redis.keys("#{TRANSACTION_PREFIX}*").each do |key|
      transaction = JSON.parse(redis.get(key))
      if transaction["invoice_number"] == invoice_number
        return transaction
      end
    end
    return nil
  end

  def get_customer_by_email(email)
    redis.keys("#{CUSTOMER_PREFIX}*").each do |key|
      customer = JSON.parse(redis.get(key))
      if customer["email"] == email
        return customer
      end
    end
    return nil
  end

  # Method for getting transaction by transaction id. Only used for testing.

  def get_transaction_by_id(transaction_id)
    return get_transaction(transaction_id)
  end

  private
  # Implement ':void' in customer profile transaction
  def void_transaction(options)
    requires!(options[:transaction], :trans_id)
    id = options[:transaction][:trans_id]
    # logger.debug "MOCK: voiding transaction #{id}"

    # Verify that transaction exists and is not already voided
    if id == UNVOIDABLE_TRANSACTION_ID
      return ActiveMerchant::Billing::Response.new(false, "Forced void failure", {})
    end

    transaction = get_transaction(id)
    # Verify that transaction exists and is not already voided
    if transaction.nil?
      return ActiveMerchant::Billing::Response.new(false, "Transaction not found", {})
    end

    if transaction["void"] == true
      return ActiveMerchant::Billing::Response.new(true, "This transaction has already been voided", {})
    end

    transaction["void"] = true
    return ActiveMerchant::Billing::Response.new(true, "This transaction has been voided.", {})
  end

  # Handle ':refund' in customer profile transaction (not used in our unit tests)
  def refund_transaction(options)
    requires!(options[:transaction], :trans_id) && (
    (options[:transaction][:customer_profile_id] && options[:transaction][:customer_payment_profile_id]) ||
        options[:transaction][:credit_card_number_masked] ||
        (options[:transaction][:bank_routing_number_masked] && options[:transaction][:bank_account_number_masked])
    )
    # We don't use this in unit tests, because you can only refund after settlement
    raise "Refunds not implemented"
  end

  # Handle ':prior_auth_capture' in customer profile transaction (not used in our unit tests)
  def prior_auth_capture(options)
    # We don't use this, sorry
    raise "Prior auth capture not implemented"
  end

  # Handle ':auth_capture' in customer profile transaction i.e. actually charge user
  def auth_capture(options)
    requires!(options[:transaction], :amount, :customer_profile_id, :customer_payment_profile_id)
    customer_profile_id = options[:transaction][:customer_profile_id]
    payment_profile_id = options[:transaction][:customer_payment_profile_id].to_s
    amount = options[:transaction][:amount]
    if options[:transaction][:order] != nil
      invoice_number = options[:transaction][:order][:invoice_number]
      purchase_order_number = options[:transaction][:order][:purchase_order_number]
    else
      invoice_number = ''
      purchase_order_number = ''
    end

    # logger.debug "MOCK auth_capture transaction for $#{amount}"

    # Check that customer exists
    customer = get_customer(customer_profile_id)
    if customer.nil?
      return ActiveMerchant::Billing::Response.new(false, "Customer not found", {})
    end

    # Check that billing profile exists
    payment_profile = customer["payment_profiles"][payment_profile_id]
    if payment_profile.nil?
      return ActiveMerchant::Billing::Response.new(false, "Payment profile not found #{payment_profile_id}", {})
    end

    if payment_profile["payment"]["credit_card"]["card_number"] == FAILURE_CREDIT_CARD_NUMBER
      # logger.debug "MOCK: failure cc number detected: returning error"
      return ActiveMerchant::Billing::Response.new(false, "Forced test failure", {})
    end


    # Save transaction
    transaction_id = generate_profile_id
    approval_code = generate_profile_id
    transaction = {
        "id" => transaction_id,
        "amount" => amount,
        "customer_profile_id" => customer_profile_id,
        "customer_payment_profile_id" => payment_profile_id,
        "invoice_number" => invoice_number,
        "purchase_order_number" => purchase_order_number,
        "void" => false,
        "approval_code" => approval_code
    }
    set_transaction(transaction_id, transaction)

    if payment_profile["payment"]["credit_card"]["card_number"] == EXCEPTION_CREDIT_CARD_NUMBER
      # logger.debug "MOCK: exception cc number detected: throwing exception"
      raise Exception.new("FORCED EXCEPTION IN AUTH NET MOCK")
    end

    params = {
        "direct_response" => {
            "transaction_id" => transaction_id,
            "approval_code" => approval_code,
            "raw" => "Andy wuz ere"
        }
    }

    return ActiveMerchant::Billing::Response.new(true, "", params)
  end

  # Helper method for finding customers in fake gateway store
  def get_customer(customer_id)
    customer = redis.get("#{CUSTOMER_PREFIX}#{customer_id}")
    if !customer.nil?
      customer = JSON.parse(customer)
    end
    return customer
  end

  def set_customer(customer)
    redis.set("#{CUSTOMER_PREFIX}#{customer["customer_profile_id"]}", customer.to_json)
  end

  def get_transaction(transaction_id)
    transaction = redis.get("#{TRANSACTION_PREFIX}#{transaction_id}")
    if !transaction.nil?
      transaction = JSON.parse(transaction)
    end
    return transaction
  end

  def set_transaction(transaction_id, transaction)
    redis.set("#{TRANSACTION_PREFIX}#{transaction_id}", transaction.to_json)
  end

  def find_transaction_by_invoice_number(invoice_number)
  end

  # Helper method for storing payment profiles
  def set_payment_profile(customer_id, payment_profile_id, payment_profile)
    customer = get_customer(customer_id)
    payment_profile = payment_profile.with_indifferent_access
    # logger.debug "Setting payment profile #{payment_profile_id}: #{payment_profile.inspect}"
    if customer["payment_profiles"].has_key?(payment_profile_id)
      customer["payment_profiles"][payment_profile_id] = update_payment_profile(
          customer["payment_profiles"][payment_profile_id],
          payment_profile)
    else

      customer["payment_profiles"].each do |payment_id|
        if payment_id != nil && payment_id[1]["payment"]["credit_card"]["card_number"] == payment_profile["payment"]["credit_card"].number
          raise "A duplicate customer payment profile already exists."
        end
      end

      if payment_profile.has_key?("payment")
        payment_profile["payment"]["credit_card"] = cc_to_hash(payment_profile["payment"]["credit_card"])
      end
      customer["payment_profiles"][payment_profile_id] = payment_profile
    end
    set_customer(customer)
  end

  # Helper method for selectively updating payment profiles
  def update_payment_profile(existing_profile, new_profile)
    profile = {}
    if new_profile.has_key?("bill_to")
      profile["bill_to"] = new_profile["bill_to"]
    elsif existing_profile.has_key?("bill_to")
      profile["bill_to"] = existing_profile["bill_to"]
    end

    # If the user included the credit card, we'll set it
    if new_profile.has_key?("payment")
      new_profile["payment"]["credit_card"] = cc_to_hash(new_profile["payment"]["credit_card"])
      profile["payment"] = new_profile["payment"]
      new_number =  new_profile["payment"]["credit_card"]["card_number"]
      existing_number = existing_profile["payment"]["credit_card"]["card_number"]
      # But if the user send a masked credit card, we'll check it's correct, then keep the existing one.
      if new_number[0] == "X"
        # logger.debug "Found blanked CC"
        if existing_number[-4..-1] != new_number[-4..-1]
          raise "does not match the original value"
        end
        profile["payment"]["credit_card"]["card_number"] = existing_number
      end
    elsif existing_profile.has_key?("payment")
      profile["payment"] = existing_profile["payment"]
    end
    return profile
  end

  # Convert a ActiveMervchant credit card object to a hash (which is what we store and return)
  def cc_to_hash(credit_card)
    if credit_card.is_a?(Hash)
      return credit_card
    end
    if credit_card.nil?
      return nil
    end
    # logger.debug "Converting CC to hash: #{credit_card.inspect}"
    hash = {
        "card_number" => credit_card.number,
        "expiration_date" => credit_card.year.to_s + credit_card.month.to_s
    }
    return hash
  end

  # When returning the credit card, we mask the number and expiration
  def mask_cc(payment_profile)
    payment_profile = payment_profile.with_indifferent_access
    masked = payment_profile.deep_dup
    if masked["payment"].nil?
      return masked
    end
    cc = cc_to_hash(masked["payment"]["credit_card"])
    if !cc.nil?
      masked["payment"]["credit_card"] = {
          "card_number" => "XXXX" + cc["card_number"][-4..-1],
          "expiration_date" => "XXXX" }
    end
    return masked
  end

  # Generate realistic-looking auth.net customer profile ids
  def generate_profile_id(length=9)
    num = SecureRandom.random_number(10**length - 1)
    return (num + 1).to_s
  end

end