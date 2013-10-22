stratum = require 'stratum'
TemplateRegistry = require './template_registry'
Coinbaser = require './coinbaser'
Subscription = require './subscription'
ShareLogger = require './sharelogger'

class Pool
  constructor: (config) ->
    @subs = {}
    @config = config
    @varDiff = config.varDiff
    @varDiffSharesPerMin = config.varDiffSharesPerMin
    @varDiffMax = config.varDiffMax
    @varDiffWindow = config.varDiffWindow
    @server = stratum.Server.create
      settings:
        hostname: config.hostname
        toobusy: config.toobusy
        host: config.stratumHost
        port: config.stratumPort
    @server.on 'mining', (r,d,c) => @onMining(r,d,c)

    @daemon = stratum.Daemon.create
      name: config.coinName
      host: config.coinHost
      port: config.coinPort
      user: config.coinUser
      password: config.coinPass

    @sharelogger = new ShareLogger(config.algo, config.sharelogger, @daemon)
    @coinbaser = new Coinbaser(@daemon, config.address)
    @registry = new TemplateRegistry(config.algo, config.pos, @sharelogger, @coinbaser, @daemon,
      ((n) => @onTemplate(n)),
      ((p,h) => @onBlock(p,h))
    )

    if @config.merkleUpdateInterval
      setInterval (=> @registry.updateBlock()), @config.merkleUpdateInterval

  onTemplate: (newBlock) ->
    cleanJobs = newBlock
    args = @registry.getLastBroadcastArgs()
    args[args.length-1] = cleanJobs

    @server.broadcast('notify', args).then(
      ((total) -> console.log('Broadcasted new work to %s clients', total) ),
      ((err) -> console.log('Cant broadcast: %s', err) )
    )

  onBlock: (share, block) -> true

  onMining: (req, def, client) ->
    switch req.method
      when 'update_block'
        unless @config.rpcPass == req.params[0]
          def.resolve([false])
          return

        def.resolve([true])
        @registry.updateBlock()
      when 'subscribe'
        @onSubscribe(client, req.params, def)
      when 'submit'
        @onSubmit(@subs[client.id], req.params, def)
      when 'authorize'
        @onAuthorize(client, req.params, def)

  onSubscribe: (client, params, def) ->
    if client.subscription
      def.reject([-2, "This connection is already subscribed for such event.", null])

    sub = new Subscription(client, params, @registry, @config.difficulty)
    @subs[sub.id] = sub
    def.resolve(sub.start())
    setTimeout (=>
      client.notify(@registry.getLastBroadcastArgs())
    ), 200

  onAuthorize: (client, params, def) ->
    [user, pass] = params

    auth = true # FIXME

    client.authorized = auth
    def.resolve([auth])
    console.log("Miner authorized: %s", user)

  onSubmit: (sub, params, def) ->
    [workerName, jobId, extranonce2, ntime, nonce] = params
    @registry.submitShare(
      def, jobId, workerName, sub.session,
      sub.extranonce1_bin, extranonce2, ntime, nonce,
      sub.diff
    )
    sub.updateDiff(@config.difficulty, @varDiffMax,
      @varDiffSharesPerMin, @varDiffWindow)

  start: ->
    @server.listen().then (msg) ->
      console.log msg

module.exports = Pool
