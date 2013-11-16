bignum = require 'bignum'
util = require './util'
halfnode = require './halfnode'
CoinbaseTX = require './coinbase_tx'
Coinbaser = require './coinbaser'
MerkleTree = require './merkle_tree'
_ = require 'underscore'
binpack = require 'binpack'

class BlockTemplate extends halfnode.Block
  constructor: (algo, pos, txMsg, coinbaser, job_id) ->
    super(algo, pos, txMsg)
    @job_id = job_id
    @coinbaser = coinbaser
    @timedelta = 0
    @curtime = 0
    @target = 0
    @merkletree = 0
    @broadcast_args = []
    @submits = []

  fill_from_rpc: (data, cbExtras = '/stratumPool/') ->
    @txhashes = [null]
    for t in data.transactions
      @txhashes.push util.ser_uint256(new bignum(t.hash, 16))

    try
      coinbase = new CoinbaseTX(@coinbaser, data.coinbasevalue, data.coinbaseaux.flags, data.height, cbExtras, @algo, @pos, txMsg, data.curtime)
    catch e
      console.log e, e.stack

    @height = data.height
    @version = data.version
    @prevblock = new bignum(data.previousblockhash, 16)
    @bits = new bignum(data.bits, 16)
    @curtime = data.curtime
    @timedelta = @curtime - util.unixtime()
    @merkletree = new MerkleTree(@txhashes)
    @target = util.uint256_from_compact(@bits)
    @tx = [ coinbase ]
    for tx in data.transactions
      t = new halfnode.Transaction(@pos, @algo, @txMsg)
      t.deserialize(util.unhexlify(tx.data))
      @tx.push t

    @prevhash_bin = util.unhexlify(util.reverse_hash(data.previousblockhash))
    @prevhash_hex = data.previousblockhash
    @broadcast_args = @build_broadcast_args()

  registerSubmit: (extranonce1, extranonce2, ntime, nonce) ->
    t = [extranonce1, extranonce2, ntime, nonce]
    unless _.include @submits, t
      @submits.push t
      return true
    return false

  build_broadcast_args: ->
    prevhash = util.hexlify(@prevhash_bin)
    coinb1 = util.hexlify(@tx[0]._serialized[0])
    coinb2 = util.hexlify(@tx[0]._serialized[1])
    merkle_branch = []
    merkle_branch.push(util.hexlify(x)) for x in @merkletree._steps
    version = util.hexlify(binpack.packUInt32(@version, 'big'))
    bits = util.hexlify(binpack.packUInt32(@bits.toNumber(), 'big'))
    time = util.hexlify(binpack.packUInt32(@curtime, 'big'))
    clean_jobs = true

    return [
      @job_id,
      prevhash,
      coinb1,
      coinb2,
      merkle_branch,
      version,
      bits,
      time,
      clean_jobs
    ]

  serializeCoinbase: (en1, en2) ->
    [part1, part2] = @tx[0]._serialized
    Buffer.concat([part1, en1, en2, part2])

  checkTime: (time) ->
    return false if time < @curtime
    return false if time > (util.unixtime() + 7200)
    return true

  serializeHeader: (merkleroot_int, time_bin, nonce_bin) ->
    r = []
    r.push binpack.packUInt32(@version, 'big')
    r.push @prevhash_bin
    r.push util.ser_uint256(merkleroot_int, true)
    r.push time_bin
    r.push binpack.packUInt32(@bits.toNumber(), 'big')
    r.push nonce_bin
    Buffer.concat(r)

  finalize: (merkleroot_int, extranonce1_bin, extranonce2_bin, time, nonce) ->
    @merkleroot = merkleroot_int
    @time = time
    @nonce = nonce
    @tx[0].setExtraNonce(Buffer.concat([extranonce1_bin, extranonce2_bin]))
    @sha256 = null
    @scrypt = null

  isValid: -> true # FIXME

module.exports = BlockTemplate
