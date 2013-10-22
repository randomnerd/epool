binpack = require 'binpack'
bignum = require 'bignum'
halfnode = require './halfnode'
coinbaser = require './coinbaser'
util = require './util'
Buffers = require 'buffers'

class CoinbaseTX extends halfnode.Transaction
  constructor: (coinbaser, value, flags, height, data, pos = false, time) ->
    super(pos)

    @time = time

    extranonce_ph = util.unhexlify('f000000ff111111f')
    extranonce_size = 8

    tx_in = new halfnode.TransactionIn()
    tx_in.prevout.hash = 0
    tx_in.prevout.n = Math.pow(2, 32) - 1
    tx_in._scriptSig_template = []

    b = []
    b.push util.ser_number(height)
    b.push util.unhexlify(flags)
    b.push util.ser_number(util.unixtime())
    b.push new Buffer([extranonce_size])
    tx_in._scriptSig_template.push Buffer.concat(b)

    tx_in._scriptSig_template.push util.ser_string(coinbaser.get_coinbase_data() + data)
    tx_in.scriptSig = Buffer.concat([tx_in._scriptSig_template[0], extranonce_ph, tx_in._scriptSig_template[1]])

    tx_out = new halfnode.TransactionOut()
    tx_out.value = value
    tx_out.scriptPubKey = coinbaser.get_script_pubkey(pos)
    @vin.push tx_in
    @vout.push tx_out

    b = util.hexlify(@serialize())
    [part1, part2] = b.split('f000000ff111111f')
    @_serialized = [util.unhexlify(part1), util.unhexlify(part2)]

  setExtraNonce: (extranonce) ->
    [part1, part2] = @vin[0]._scriptSig_template
    @vin[0].scriptSig = Buffer.concat([part1, extranonce, part2])

module.exports = CoinbaseTX
