ShareLogger = require('../../sharelogger')
async = require 'async'
_ = require 'underscore'
Pusher = require('pusher')
pg = require('pg')
class CoinExNewShareLogger extends ShareLogger
  constructor: (params, rpc) ->
    @connected = false
    @rpc = rpc
    @params = params
    @db = null
    @connected = false
    @currId = params.currencyId
    @flushInterval = params.flushInterval || 60
    @poolFee = 0
    @stats = {}
    @lastFlush = null
    @pusher = new Pusher
      appId:  params.pusherAppId
      key:    params.pusherKey
      secret: params.pusherSecret

    dbString = "postgres://#{params.dbUser}:#{params.dbPass}@#{params.dbHost}:#{params.dbPort || 5432}/#{params.dbName}"
    @db = new pg.Client(dbString)
    @connect()

  connect: ->
    @db.connect (err) =>
      if err
        @connected = false
        console.log('pg connection error', err)
      else
        @connected = true
        @db.query "set timezone='UTC'"
        console.log('pg connected')

  logShare: (share) -> true
  logBlock: (block) -> @saveBlock(block)
  logStats: (name, stats) ->
    @stats[name] = stats
    @flush()

  flush: (force = false) ->
    @lastFlush ||= new Date()
    return @connect() unless @connected
    return unless force || (new Date() - @lastFlush) / 1000 >= @flushInterval

    try
      @saveStats()
      @lastFlush = new Date()
    catch e
      console.log 'flush', e, e.stack

  getWorkerId: (name, cb) ->
    q = "select id from workers where name = $1"
    @db.query q, [name], (err, rows) =>
      console.log 'getWorkerId error', err if err
      cb(rows.rows[0]?.id)

  getUserId: (wrkId, cb) ->
    q = "select user_id from workers where id = $1"
    @db.query q, [wrkId], (err, rows) =>
      console.log 'getUserId error', err if err
      cb(rows.rows[0]?.user_id)

  getUserIdByWrkName: (wrkName, cb) ->
    @getWorkerId wrkName, (id) => @getUserId id, cb

  getWorkerStatId: (wrkId, cb) ->
    return cb(null) unless wrkId
    q = "select id from worker_stats where currency_id = $1 and worker_id = $2 and switchpool = 'f'"
    @db.query q, [@currId, wrkId], (err, rows) =>
      console.log 'getWorkerStatId error', err if err
      return cb(null) if err
      return cb(id, wrkId) if id = rows.rows[0]?.id
      q = "insert into worker_stats (worker_id, currency_id, created_at, updated_at) values ($1, $2, now(), now())"
      @db.query q, [wrkId, @currId], (err, rows) =>
        console.log 'getWorkerStatId2 error', err if err
        @getWorkerStatId(wrkId, cb)

  getWorkerStatIdByName: (name, cb) ->
    @getWorkerId name, (id) => @getWorkerStatId id, cb

  updStat: (data, cb) ->
    [worker, stats] = data
    @getWorkerStatIdByName worker, (id, wrkId) =>
      q = "update worker_stats set hashrate = $1, accepted = $2, rejected = $3, blocks = $4, diff = $5, updated_at = now() where id = $6"
      @db.query q, [
        stats.hashrate,
        stats.accepted,
        stats.rejected,
        stats.blocks,
        stats.diff,
        id
      ], (err, rows) =>
        console.log 'updStat error', err if err
        cb(null, id)
        @getUserId wrkId, (userId) =>
          @pusher.trigger "private-worker-stats-#{userId}", "u",
            id:       id
            diff:     stats.diff
            blocks:   stats.blocks
            accepted: stats.accepted
            rejected: stats.rejected
            hashrate: stats.hashrate
            worker_id:   wrkId
            currency_id: @currId
            updated_at: new Date().toISOString()

  resetHrates: ->
    q = "update worker_stats set hashrate = 0 where currency_id = $1 and switchpool = 'f'"
    @db.query q, [@currId], (err, rows) ->
      console.log 'resetHrates error', err if err
      true

  updatePoolHrate: ->
    q = "select sum(hashrate) as hashrate from worker_stats where currency_id = $1 and updated_at > current_timestamp - interval '5' minute"
    @db.query q, [@currId], (err, rows) =>
      console.log 'updatePoolHrate error', err if err
      return unless hashrate = rows.rows[0]?.hashrate
      q = "update currencies set hashrate = $1, updated_at = now() where id = $2"
      @db.query q, [hashrate, @currId]
      @pusher.trigger 'currencies', 'uu', {id: @currId, fields: {hashrate: hashrate}}

  saveStats: ->
    @resetHrates()
    async.map _.pairs(@stats), ((d,c)=> @updStat(d, c)), (err, statIds) =>
      @updatePoolHrate()
      @stats = {}

  getBlockStats: (txid, cb) ->
    retStats = (data) =>
      details = data?.details?[0]
      return cb('No details on tx') unless details
      stats =
        cat:    details.category
        conf:   data.confirmations
        reward: details.amount * Math.pow(10, 8)

      cb(null, stats)

    @rpc.call('gettransaction', [txid]).then(
      ((r) => retStats(r))
      ((e) => console.log e, cb(e))
    )

  getBlockFinder: (worker, cb) ->
    q = "select users.nickname as name, users.id as id from workers inner join users on users.id = workers.user_id where workers.name = $1"
    @db.query q, [worker], (err, rows) ->
      console.log('getBlockFinder', err) if err
      return cb(err) if err
      cb(null, {name: rows.rows[0].name, id: rows.rows[0]?.id})

  getPoolFee: (cb) ->
    q = "select mining_fee from currencies where id = $1"
    @db.query q, [@currId], (err, rows) ->
      console.log('getPoolFee', err) if err
      return cb(err) if err
      cb(null, rows.rows[0].mining_fee)

  updateLastBlockAt: ->
    q = "update currencies set last_block_at = now(), updated_at = now() where id = $1"
    @db.query q, [@currId]
    @pusher.trigger 'currencies', 'uu',
      id: @currId
      fields:
        last_block_at: new Date().toISOString()

  pushBlock: (block) ->
    q = "select id from blocks where txid = $1"
    @db.query q, [block.txid], (err, rows) =>
      return console.log('pushBlock', err) if err
      block?.id = rows.rows[0]?.id
      @pusher.trigger "blocks-#{@currId}", 'c', block
      @createBlockPayouts(block)

  saveBlock: (block) ->
    async.series [
      ((cb) => @getPoolFee(cb))
      ((cb) => @getBlockStats(block.txid, cb))
      ((cb) => @getBlockFinder(block.finder, cb))
    ], (e, ret) =>
      [fee, stats, finder] = ret
      return unless stats.reward

      b =
        category:       stats.cat
        paid:           0
        diff:           block.diff
        txid:           block.txid
        stats:          block.rewards
        finder:         finder.name
        number:         block.height
        reward:         stats.reward
        user_id:        finder?.id
        time_spent:     Math.round(block.timeSpent)
        created_at:     new Date().toISOString()
        updated_at:     new Date().toISOString()
        currency_id:    @currId
        confirmations:  stats.conf
      console.log block

      q = "insert into blocks (category, paid, diff, txid, finder, number,
                               reward, user_id, time_spent, currency_id,
                               confirmations, created_at, updated_at) values
                               ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, now(), now())"

      @db.query q, [
        b.category, b.paid, b.diff, b.txid,
        b.finder, b.number, b.reward, b.user_id,
        b.time_spent, b.currency_id, b.confirmations
      ], (err, rows) =>
        return console.log('saveBlock', err, rows) if err
        @updateLastBlockAt()
        @pushBlock(b)
        return if block.category == 'orphan'

  createBlockPayouts: (block) ->
    amounts = {}
    setAmount = (data, cb) =>
      [user, figure] = data
      @getUserIdByWrkName user, (user_id) =>
        amounts[user_id] ||= 0
        amounts[user_id] += figure
        cb(null, true)

    async.map _.pairs(block.stats), setAmount, =>
      for user_id, amount of amounts
        continue unless amount > 0
        bp =
          amount: amount
          user_id: user_id
          block_id: block?.id
          created_at: new Date().toISOString()
          updated_at: new Date().toISOString()

        q = 'insert into block_payouts (user_id, block_id, amount, created_at, updated_at)
             values ($1, $2, $3, now(), now())'
        @db.query q, [bp.user_id, bp.block_id, bp.amount], (err, rows) =>
          return console.log('createBlockPayouts', err) if err
          @pushBlockPayout(bp)

  pushBlockPayout: (bp) ->
    try
      q = 'select id from block_payouts where user_id = $1 and block_id = $2'
      @db.query q, [bp.user_id, bp.block_id], (err, rows) =>
        return console.log('pushBlockPayout', err) if err
        bp?.id = rows.rows[0]?.id
        @pusher.trigger "private-blockpayouts-#{bp.user_id}", 'c', bp
    catch e
      console.log('pushBlockPayout', e)

module.exports = CoinExNewShareLogger
