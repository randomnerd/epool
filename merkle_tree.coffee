util = require './util'
Buffers = require 'buffers'

class MerkleTree
  constructor: (data, detailed = false) ->
    @data = data
    @recalculate(detailed)
    @_hash_steps = null

  recalculate: (detailed = false) ->
    L = @data
    steps = []
    if detailed
      detail = []
      PreL = []
      StartL = 0
    else
      detail = null
      PreL = [null]
      StartL = 2

    Ll = L.length
    if detailed or Ll > 1
      while true
        detail.push(L) if detailed
        break if Ll == 1
        steps.push(L[1])
        L.push(L[Ll-1]) if Ll % 2
        arr = [PreL]
        for i in [StartL ... Ll] by 2
          arr.push util.dblsha(Buffer.concat([L[i], L[i+1]]))

        L = arr
        Ll = L.length

    @_steps = steps
    @detail = detail

  hash_steps: ->
    @_hash_steps = util.dblsha(@_steps) unless @_hash_steps

  withFirst: (f) ->
    steps = @_steps
    for s in steps
      f = util.dblsha(new Buffers([f, s]).toBuffer())
    return f

  merkleRoot: ->
    @withFirst(@data[0])


test = ->
  arr = [null]
  arr.push util.unhexlify(a) for a in [
    '999d2c8bb6bda0bf784d9ebeb631d711dbbbfe1bc006ea13d6ad0d6a2649a971',
    '3f92594d5a3d7b4df29d7dd7c46a0dac39a96e751ba0fc9bab5435ea5e22a19d',
    'a5633f03855f541d8e60a6340fc491d49709dc821f3acb571956a856637adcb6',
    '28d97c850eaf917a4c76c02474b05b70a197eaefb468d21c22ed110afe8ec9e0'
  ]

  mt = new MerkleTree(arr)

  a = '82293f182d5db07d08acf334a5a907012bbb9990851557ac0ec028116081bd5a'
  unless a == util.hexlify mt.withFirst(util.unhexlify('d43b669fb42cfa84695b844c0402d410213faa4f3e66cb7248f688ff19d5e5f7'))
    throw 'test failed'

test()

module.exports = MerkleTree
