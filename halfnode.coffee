bigint = require 'bigint'
binpack = require 'binpack'
crypto = require 'crypto'
util = require './util'
Buffers = require 'buffers'
_ = require 'underscore'

class OutPoint
  constructor: ->
    @hash = 0
    @n = 0

  deserialize: (b) ->
    b = new Buffers([b]) unless b.splice
    @hash = util.deser_uint256(b)
    @n = binpack.unpackUInt32(util.bufShift(b,4), 'little')

  serialize: ->
    r = []
    r.push util.ser_uint256(@hash)
    r.push binpack.packUInt32(@n, 'little')
    return Buffer.concat(r)

class TransactionIn
  constructor: ->
    @prevout = new OutPoint()
    @scriptSig = ''
    @sequence = 0

  deserialize: (b) ->
    b = new Buffers([b]) unless b.splice
    @prevout = new OutPoint()
    @prevout.deserialize(b)
    @scriptSig = util.deser_string(b)
    @sequence = binpack.unpackUInt32(util.bufShift(b,4), 'little')

  serialize: ->
    r = []
    r.push @prevout.serialize()
    r.push util.ser_string(@scriptSig)
    r.push binpack.packUInt32(@sequence, 'little')
    return Buffer.concat(r)

class TransactionOut
  constructor: ->
    @value = 0
    @scriptPubKey = ''

  deserialize: (b) ->
    b = new Buffers([b]) unless b.splice
    @value = binpack.unpackUInt64(util.bufShift(b,8), 'little')
    @scriptPubKey = util.deser_string(b)

  serialize: ->
    r = []
    r.push binpack.packUInt64(@value, 'little')
    r.push util.ser_string(@scriptPubKey)
    return Buffer.concat(r)

class Transaction
  constructor: (pos = false) ->
    @pos = pos
    @version = 1
    @time = 0
    @vin = []
    @vout = []
    @lockTime = 0
    @sha256 = null

  serialize: ->
    b = []
    b.push binpack.packUInt32(@version, 'little')
    if @pos
      b.push binpack.packUInt32(@time.toNumber(), 'little')
    b.push util.ser_vector(@vin)
    b.push util.ser_vector(@vout)
    b.push binpack.packUInt32(@lockTime, 'little')
    return Buffer.concat(b)

  deserialize: (b) ->
    b = new Buffers([b]) unless b.splice
    @version = binpack.unpackUInt32(util.bufShift(b,4), 'little')
    if @pos
      @time = binpack.unpackUInt32(util.bufShift(b,4), 'little')
    @vin = util.deser_vector(b, TransactionIn)
    @vout = util.deser_vector(b, TransactionOut)
    @lockTime = binpack.unpackUInt32(util.bufShift(b,4), 'little')
    @sha256 = null

  calc_sha256: ->
    @sha256 ?= util.dblsha(@serialize())

  is_valid: -> @calc_sha256()

class Block
  constructor: (algo = 'sha256', pos = false) ->
    @algo = algo
    @pos = pos
    @version = 1
    @prevblock = 0
    @merkleroot = 0
    @time = 0
    @bits = 0
    @nonce = 0
    @tx = []
    @sha256 = null
    @scrypt = null
    @signature = ''

  deserialize: (b) ->
    b = new Buffers([b]) unless b.splice
    @version = binpack.unpackUInt32(util.bufShift(b,4), 'little')
    @prevblock = util.deser_uint256(b)
    @merkleroot = util.deser_uint256(b)
    @time = binpack.unpackUInt32(util.bufShift(b,4), 'little')
    @bits = binpack.unpackUInt32(util.bufShift(b,4), 'little')
    @nonce = binpack.unpackUInt32(util.bufShift(b,4), 'little')
    @tx = util.deser_vector(b, Transaction)
    @signature = util.deser_string(b)

  serialize: (full = true) ->
    r = []
    r.push binpack.packUInt32(@version, 'little')
    r.push util.ser_uint256(@prevblock)
    r.push util.ser_uint256(@merkleroot)
    r.push binpack.packUInt32(@time.toNumber(), 'little')
    r.push binpack.packUInt32(@bits.toNumber(), 'little')
    r.push binpack.packUInt32(@nonce.toNumber(), 'little')
    if full
      r.push util.ser_vector(@tx)
      r.push util.ser_string(@signature) if @pos
    return Buffer.concat(r)

  calc_sha256: ->
    b = @serialize(false)
    @sha256 = util.deser_uint256(new Buffers([util.dblsha(b)]))

  calc_sha256_hex: ->
    util.pad_hex(@calc_sha256().toString(16), 32)

  calc_scrypt: ->
    b = @serialize(false)
    @scrypt = util.deser_uint256(new Buffers([util.scrypt(b)]))

  calc_scrypt_hex: ->
    util.pad_hex(@calc_scrypt().toString(16), 32)

  test: ->
    block = require "./test_#{@algo}_block"
    @version = block.version
    @prevblock = new bigint(block.previousblockhash, 16)
    @merkleroot = new bigint(block.merkleroot, 16)
    @time = new bigint(block.time)
    @bits = new bigint(block.bits, 16)
    @nonce = new bigint(block.nonce)

    @hash = new bigint(block.hash, 16)
    @["calc_#{@algo}"]()
    target = util.uint256_from_compact(@bits)

    unless (hash = @calc_sha256_hex()) == block.hash
      console.log hash, block.hash
      throw 'hash test failed'
    throw 'target test failed' unless @[@algo].lt(target)

    for tx in block.transactions
      t = new Transaction()
      t.deserialize(util.unhexlify(tx.data))
      @tx.push t
      ser = util.hexlify(t.serialize())
      throw 'test failed, txlen' unless tx.data.length == ser.length
      throw 'test failed, txdata' unless tx.data == ser

halfnode =
  OutPoint: OutPoint
  TransactionIn: TransactionIn
  TransactionOut: TransactionOut
  Transaction: Transaction
  Block: Block

module.exports = halfnode
