binpack = require 'binpack'
crypto = require 'crypto'
Buffers = require 'buffers'
bignum = require 'bignum'
scrypt = require 'litecoin-scrypt'
base58 = require './base58'
util =
  divmod: (n, div) ->
    a = Math.floor(n / div)
    [a, n - a * div]

  b58decode: (v, len) ->
    n = base58.decode(v)
    util.unhexlify(n.toString(16))

  num2bin: (n) ->
    util.unhexlify(new bignum(n).toString(16))

  address_to_pubkeyhash: (addr) ->
    addr = util.b58decode(addr)
    return unless addr
    ver = addr[0]
    cksumA = addr[-4..]
    cksumB = util.dblsha(addr[..-5])[..3]
    return unless util.buf2string(cksumA) == util.buf2string(cksumB)
    return [ver, addr[1..-5]]

  script_to_address: (addr) ->
    d = util.address_to_pubkeyhash(addr)
    throw 'invalid address' unless d
    [ver, pubkeyhash] = d
    b = []
    b.push new Buffer([0x76, 0xA9, 0x14])
    b.push pubkeyhash
    b.push new Buffer([0x88, 0xAC])
    return Buffer.concat(b)

  script_to_pubkey: (pubkey) ->
    b = []
    b.push new Buffer([0x21])
    b.push util.unhexlify(pubkey)
    b.push new Buffer([0xAC])
    return Buffer.concat(b)

  uint256_from_compact: (c) ->
    bytes = c.shiftRight(24).and(0xFF)
    c.and(0xFFFFFF).shiftLeft(8 * (bytes - 3))

  ser_uint256: (u, be = false) ->
    format = if be then 'big' else 'little'
    u = new bignum(u) unless u.div
    rs = []
    for i in [0 ... 8]
      long = u.and(0xFFFFFFFF).toNumber()
      buff = binpack.packUInt32(long, format)
      rs.push buff
      u = u.shiftRight(32)
    return Buffer.concat(rs)

  deser_uint256: (u, be = false) ->
    u = new Buffers([u]) unless u.splice
    format = if be then 'big' else 'little'
    r = new bignum(0)
    for i in [0 ... 8]
      t = new bignum(binpack.unpackUInt32(util.bufShift(u, 4), format))
      long = t.shiftLeft(i * 32)
      r = r.add(long)
    return r

  reverse_hash: (h) ->
    a = []
    for i in [0...64] by 8
      a.push h[56-i..63-i]
    a.join('')

  reverse_hex: (h, step = 1) ->
    len = h.length / step
    # reverse 20 groups of 4 bytes
    r = ''
    for i in [0...len]
      n = i*step
      p = h[n..n+step-1]
      rp = ''
      for n in [0..p.length] by 2
        rp += p[p.length-n..p.length-n+1]
      r += rp
    return r

  pad_hex: (s, bytes = 32) ->
    return s if s.length == bytes * 2

    for i in [0...bytes*2-s.length]
      s = "0" + s

    return s

  reverse_bin: (b, step = 1) ->
    if step == 1
      return new Buffer(b.toString().split('').reverse().join(''))
    hex = util.hexlify(b)
    rhex = util.reverse_hex(hex, step * 2)
    return util.unhexlify(rhex)

  unhexlify: (str) ->
    b = []
    for i in [0 ... str.length] by 2
      b.push parseInt(str[i .. i + 1], 16)
    return new Buffer(b)

  hexlify: (buf) ->
    s = ''
    for i in [0 ... buf.length]
      x = buf[i].toString(16)
      x = '0' + x if x.length == 1
      s += x
    return s

  sha256: (buf) ->
    shasum = crypto.createHash('sha256')
    shasum.update(buf)

  unixtime: -> Math.floor(+new Date()/1000)

  dblsha: (buf) ->
    first = util.sha256(buf).digest()
    second = util.sha256(first).digest()

  scrypt: (buf) -> scrypt(buf)

  ser_vector: (l) ->
    b = []
    b.push util.serBufLen(l.length)
    b.push i.serialize() for i in l
    return Buffer.concat(b)

  deser_vector: (f, c) ->
    bLen = util.deserBufLen(f)
    r = []
    for i in [0 ... bLen]
      t = new c()
      t.deserialize(f)
      r.push t
    return r

  string2buf: (s) -> new Buffer(s)
  buf2string: (b) -> String.fromCharCode.apply(String, b)

  ser_number: (n) ->
    s = [0x01]
    while n > 127
      s[0] += 1
      s.push n % 256
      n = Math.floor(n / 256)
    s.push n
    return new Buffer(s)

  ser_string: (s) ->
    bLen = util.serBufLen(s.length)
    b = util.string2buf(s)
    return new Buffer.concat([bLen, b])

  deser_string: (b) ->
    len = util.deserBufLen(b)
    util.bufShift(b,len)

  bufShift: (b, bytes) -> b.splice(0,bytes).toBuffer()

  deserBufLen: (b) ->
    nit = binpack.unpackUInt8(util.bufShift(b, 1))
    switch nit
      when 253
        nit = binpack.unpackUInt16(util.bufShift(b,2), 'little')
      when 254
        nit = binpack.unpackUInt32(util.bufShift(b,4), 'little')
      when 255
        nit = binpack.unpackUInt64(util.bufShift(b,8), 'little')
    return nit

  serBufLen: (len) ->
    r = []
    if len < 253
      r.push binpack.packUInt8(len)
    else if len < 0x10000
      r.push new Buffer([253])
      r.push binpack.packUInt16(len, 'little')
    else if len < 0x100000000
      r.push new Buffer([254])
      r.push binpack.packUInt32(len, 'little')
    else
      r.push new Buffer([255])
      r.push binpack.packUInt64(len, 'little')
    return Buffer.concat(r)

  minutesFrom: (time) -> (new Date() - time) / (60 * 1000)

module.exports = util
