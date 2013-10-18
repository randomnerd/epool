bigint = require 'bigint'
util = require './util'
halfnode = require './halfnode'
CoinbaseTX = require './coinbase_tx'
Coinbaser = require './coinbaser'
MerkleTree = require './merkle_tree'
_ = require 'underscore'
binpack = require 'binpack'

class BlockTemplate extends halfnode.Block
  constructor: (algo, pos, coinbaser, job_id) ->
    super(algo, pos)
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
      @txhashes.push util.ser_uint256(new bigint(t.hash, 16))

    mt = new MerkleTree(@txhashes)
    try
      coinbase = new CoinbaseTX(@coinbaser, data.coinbasevalue, data.coinbaseaux.flags, data.height, cbExtras, @pos)
    catch e
      console.dir e.stack

    @height = data.height
    @version = data.version
    @prevBlock = new bigint(data.previousblockhash, 16)
    @bits = new bigint(data.bits, 16)
    @curtime = data.curtime
    @timedelta = @curtime - util.unixtime()
    @merkletree = mt
    @target = util.uint256_from_compact(@bits)
    @vtx = [ coinbase ]
    console.log data.transactions.length, 'transactions to deserialize'
    i = 1
    for tx in data.transactions
      t = new halfnode.Transaction(@pos)
      console.log new Date(), 'deserialize tx', i
      t.deserialize(util.unhexlify(tx.data))
      @vtx.push t
      i++
    console.log 'deserialized transactions'

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
    coinb1 = util.hexlify(@vtx[0]._serialized[0])
    coinb2 = util.hexlify(@vtx[0]._serialized[1])
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
    [part1, part2] = @vtx[0]._serialized
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
    @hashMerkleRoot = merkleroot_int
    @time = time
    @nonce = nonce
    @vtx[0].setExtraNonce(Buffer.concat([extranonce1_bin, extranonce2_bin]))
    @sha256 = null
    @scrypt = null

  isValid: -> true # FIXME

module.exports = BlockTemplate
