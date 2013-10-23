BlockTemplate = require './block_template'
binpack = require 'binpack'
bignum = require 'bignum'
util = require './util'
Buffers = require 'buffers'

class JobIdGenerator
  constructor: -> @counter = 0
  getNewId: ->
    @counter = 0 if @counter % 0xFFFF == 0
    @counter++
    @counter.toString(16)

class ExtranonceCounter
  constructor: (instanceId = 31) ->
    if instanceId < 0 or instanceId > 31
      throw 'Instance id should be 0-31'

    @counter = instanceId << 27
    @size = 4

  getNew: ->
    @counter++
    binpack.packUInt32(@counter, 'big')

  getSize: -> @size

class TemplateRegistry
  constructor: (algo, pos, sharelogger, cb, rpc, onTemplateCB, onBlockCB) ->
    @algo = algo
    @pos = pos
    @sharelogger = sharelogger
    @jobgen = new JobIdGenerator()
    @prevhashes = {}
    @jobs = []

    @extranonceCounter = new ExtranonceCounter()

    @extranonce2_size = 4
    @coinbaser = cb

    @rpc = rpc
    @onBlockCB = onBlockCB
    @onTemplateCB = onTemplateCB
    @lastBlock = null
    @updateInProgress = false
    @lastUpdate = null
    @lasthash = null
    @updateBlock()

  getNewExtranonce1: -> @extranonceCounter.getNew()
  getLastBroadcastArgs: -> @lastBlock?.broadcast_args
  addTemplate: (block, blockHeight) ->
    prevhash = block.prevhash_hex
    if @prevhashes[prevhash]
      newBlock = false
    else
      newBlock = true
      @prevhashes[prevhash] = []

    @prevhashes[prevhash].push block
    @jobs[block.job_id] = block
    @lastBlock = block
    for ph, b in @prevhashes
      @prevhashes[ph] = undefined unless ph == prevhash

    console.log "New template for", prevhash

    @onTemplateCB(newBlock)

  updateBlock: ->
    return if @updateInProgress
    @updateInProgress = true
    @rpc.call('getblocktemplate', [{}]).then(
      ((d) => @_updateBlock(d)),
      ((e) => @_updateBlockFail(e))
    )

  _updateBlockFail: (msg) ->
    console.log(msg)
    @updateInProgress = false

  _updateBlock: (data) ->
    return @updateInProgress = false if @lasthash  == data.previousblockhash
    @lasthash = data.previousblockhash

    start = +new Date()

    try
      template = new BlockTemplate(@algo, @pos, @coinbaser, @jobgen.getNewId())

      template.fill_from_rpc(data)
      @jobs = []
      @addTemplate(template, data.height)

      console.log('Update finished, %s sec, %s txes',
        (new Date() - start)/1000, template.tx.length)
    catch e
      console.log e, e.stack
    finally
      @updateInProgress = false
    return data

  diff2target: (diff) ->
    switch @algo.toLowerCase()
      when 'scrypt'
        d1 = '0000ffff00000000000000000000000000000000000000000000000000000000'
      when 'sha256'
        d1 = '00000000ffff0000000000000000000000000000000000000000000000000000'
    diff1 = new bignum(d1, 16)
    diff1.div(diff)

  getJob: (jobId) ->
    return unless j = @jobs[jobId]

    unless @prevhashes[j.prevhash_hex]
      console.log('Prevhash of job %s is unknown', jobId)
      return

    unless j in @prevhashes[j.prevhash_hex]
      console.log('Job %s is unknown', jobId)

    return j

  submitShare: (defer, jobId, workerName, session, extranonce1_bin, extranonce2, time, nonce, diff) ->
    try
      share =
        time: new Date()
        username: workerName
        diff: 0
        diff_target: diff
        accepted: false
        upstream: false

      if extranonce2.length != @extranonce2_size * 2
        share.rejectReason = "Incorrect size of extranonce2. Expected \
          #{@extranonce2_size*2} chars, got #{extranonce2.length}"
        defer.reject(reason)
        return @sharelogger.logShare(share)

      job = @getJob(jobId)

      unless job
        share.rejectReason = "Job #{jobId} not found"
        defer.reject(share.rejectReason)
        return @sharelogger.logShare(share)

      unless time.length == 8
        share.rejectReason = 'Incorrect size of ntime. Expected 8 chars'
        defer.reject(share.rejectReason)
        return @sharelogger.logShare(share)

      unless job.checkTime(parseInt(time, 16))
        share.rejectReason = 'Ntime out of range'
        defer.reject(share.rejectReason)
        return @sharelogger.logShare(share)

      unless nonce.length == 8
        share.rejectReason = 'Ntime out of range'
        defer.reject(share.rejectReason)
        return @sharelogger.logShare(share)

      unless job.registerSubmit(extranonce1_bin, extranonce2, time, nonce)
        console.log('Duplicate from %s, (%s, %s, %s, %s)',
          worker_name, util.hexlify(extranonce1_bin), extranonce2, time, nonce)
        share.rejectReason = 'Duplicate share'
        defer.reject(share.rejectReason)
        return @sharelogger.logShare(share)

      extranonce2_bin = util.unhexlify(extranonce2)
      time_bin = util.unhexlify(time)
      nonce_bin = util.unhexlify(nonce)

      coinbase_bin = job.serializeCoinbase(extranonce1_bin, extranonce2_bin)
      coinbase_hash = util.dblsha(coinbase_bin)

      merkleroot_bin = job.merkletree.withFirst(coinbase_hash)
      merkleroot_int = util.deser_uint256(new Buffers([merkleroot_bin]))

      header_bin = job.serializeHeader(merkleroot_int, time_bin, nonce_bin)

      switch @algo.toLowerCase()
        when 'scrypt'
          hash_bin = util.scrypt(util.reverse_bin(header_bin, 4))
        when 'sha256'
          hash_bin = util.dblsha(util.reverse_bin(header_bin, 4))
      hash_int = util.deser_uint256(new Buffers([hash_bin]))
      hash_hex = hash_int.toString(16)
      share.hash = util.pad_hex(hash_hex)

      header_hex = util.hexlify(header_bin)

      target_user = @diff2target(diff)
      share.diff = @diff2target(hash_int).toNumber()

      if hash_int.gt(target_user)
        share.rejectReason = 'Share is above target'
        defer.reject(share.rejectReason)
        return @sharelogger.logShare(share)

      defer.resolve([true])
      share.accepted = true

      if hash_int.le(job.target)
        console.log('Block candidate: %s', util.pad_hex(hash_hex))

        try
          job.finalize(merkleroot_int, extranonce1_bin, extranonce2_bin,
            new bignum(time, 16), new bignum(nonce, 16))

          if @pos
            share.block_hash = share.hash
          else
            share.block_hash = job.calc_sha256_hex()

          unless job.isValid()
            console.log('Final job validation failed!')

          serialized = util.hexlify(job.serialize())
          @submitBlock(share, serialized)
        catch e
          console.log e
          console.dir e.stack

      else
        @sharelogger.logShare(share)
    catch e
      console.log e, e.stack

  submitBlock: (share, block_hex) ->
    checkBlock = (block_hash) =>
      @rpc.call('getblock', [block_hash]).then(
        ((r) => checkTX(r)),
        ((e) => @sharelogger.logShare(share))
      )

    checkTX = (block) =>
      @rpc.call('gettransaction', [block.tx[0]]).then(
        ((r) => @sharelogger.logBlock(share, block)),
        ((e) => @sharelogger.logShare(share))
      )

    logShare = (result) =>
      if result
        share.upstreamReason = result
        @sharelogger.logShare(share)
      else
        checkBlock(share.block_hash)

    tryGBT = (e) =>
      @rpc.call('getblocktemplate', [{mode: 'submit', data: block_hex}]).then(
        ((r) => logShare(r)),
        ((e) => logShare(e))
      )

    @rpc.call('submitblock', [block_hex]).then(
      ((r) => logShare(r)),
      ((e) => tryGBT(e))
    )

module.exports = TemplateRegistry
