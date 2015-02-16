# Mockerize

Mockerize is a mock authorize.net customer information management (CIM) for Rails. It is based on the active-merchant
(http://activemerchant.org) authorize.net CIM gateway. It use Redis as a data store to simulate the authorize.net
CIM service.


## Dependencies

1. Redis

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'Mockerize'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install Mockerize

## Usage

### Development

To use the mock server in development mode, add

```ruby
ENV['MOCK_AUTH_NET'] = 'true'
```

to your development.rb environment file.

### Test

To use the auth.ent servers in test mode, add

```ruby
  ENV['FORCE_AUTH_NET'] = 'true'
```

to your test.rb environment file.

## Attribution

Original idea: http://engineering.harrys.com/2014/04/15/mock-authorize.net-gateway.html

## Contributing

1. Fork it ( https://github.com/drmaj/Mockerize/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
