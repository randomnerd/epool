util = require './util'
class SimpleCoinbaser
  constructor: (rpc, address) ->
    @address = address
    @rpc = rpc

  get_script_pubkey: (pos = false) ->
    if pos
      util.script_to_pubkey(@address)
    else
      util.script_to_address(@address)
  get_coinbase_data: -> new Buffer('')

module.exports = SimpleCoinbaser
